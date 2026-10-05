#!/usr/bin/env lua5.4

-- Replay a Lemmy community, as seen by one instance, on freechains
-- (events from lemmy-events.py): posts/comments as signed posts by
-- actor id, modlog removals as REVOKES with the moderator's reason,
-- restores as UNREVOKES with the original payload, author deletes
-- as free self-revokes. No votes (per-user votes are not public).
-- OPEN mode: ungated; each moderator signs with its own key.
-- GATED mode: `--dictator` = first moderator key; begs + welcomes;
-- MODS=own: a moderator revokes when affordable, else the dictator
-- does (as wiki); MODS=dict: the dictator signs all (as GitHub).
-- SINGLE INSTANCE: BASE is wiped on start.

-------------------------------------------------------------------------------
-- config

local function env (name, default)
    local v = os.getenv(name)
    if v == nil then
        return default
    elseif v == 'true' then
        return true
    elseif v == 'false' or v == 'nil' then
        return v == 'true'
    else
        return tonumber(v) or v
    end
end

local SRC      = env('SRC',      'lemmy.dbzer0.com-adhd@lemmy.dbzer0.com')
local LIMIT    = env('LIMIT',    false)
local WINDOW   = env('WINDOW',   5000)
local SWEEP    = env('SWEEP',    true)
local GATED    = env('GATED',    false)
local MODS     = env('MODS',     'own')      -- own | dict
local WELCOME  = env('WELCOME',  'always')   -- always | never
local ALIAS    = env('ALIAS',    '/' .. SRC:match('%-([^@]+)@'))
local BASE     = env('BASE',     './.freechains-' .. SRC ..
                                 (GATED and '-gated' or ''))
local N_REVOKE = env('N_REVOKE', 1000)

local GIT = env('GIT', true) and {
    ['pack.threads']      = '2',
    ['pack.windowMemory'] = '512m',
} or {}

-------------------------------------------------------------------------------
-- helpers (as gh-simple)

function exec (cmd)
    local f = io.popen(cmd .. " 2>&1")
    local v = f:read('*a')
    f:close()
    return (string.gsub(v, "%s+$", ""))
end

function now ()
    return tonumber(exec("date +%s.%N"))
end

BASE = exec("realpath -m " .. BASE)
local ROOT = BASE .. '/root'
local KEYS = BASE .. '/keys'
local DIR  = ROOT .. '/chains/' .. string.sub(ALIAS, 2) .. '/'
local FC   = "freechains --root=" .. ROOT
local DATA = exec("realpath -m ../data/lemmy/" .. SRC)   -- absolute: git -C chdirs

function disk ()
    local total = tonumber(exec("du -sb " .. DIR .. " | cut -f1")) or 0
    local co    = exec("git -C " .. DIR .. " count-objects -v")
    local loose = (tonumber(co:match("size: (%d+)"))      or 0) * 1024
    local pack  = (tonumber(co:match("size%-pack: (%d+)")) or 0) * 1024
    return total, pack, loose
end

function report (tag, N)
    local g, pack, loose = disk()
    print(string.format("== N=%d  %-6s git=%.1f MB  (pack %.1f, loose %.1f)",
        N, tag, g/1e6, pack/1e6, loose/1e6))
end

-------------------------------------------------------------------------------
-- setup

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
local DICT = KEYS .. '/dictator'
os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. DICT .. " -q")
if GATED then
    print(exec(FC .. " --now=0 chains add '" .. ALIAS ..
        "' init --dictator=" .. DICT))
else
    print(exec(FC .. " --now=0 chains add '" .. ALIAS .. "' init"))
end
for k,v in pairs(GIT) do
    os.execute("git -C " .. DIR .. " config " .. k .. " " .. v)
end

local USERS  = {}
local nusers = 0

--[[
-- Ensure a keypair for a member or moderator.
-- Inputs:
--  - user [string]: actor key ('feddit.org/u/alice') or mod key
--    ('mod/lemmy.dbzer0.com/2')
-- Outputs:
--  - [string]: private key path (.pub sibling for reps)
-- Callers:
--  - replay loop, reps, signer [lemmy-simple.lua]
--]]
function key (user)
    if not USERS[user] then
        nusers = nusers + 1
        USERS[user] = 'u' .. nusers
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " ..
            KEYS .. "/" .. USERS[user] .. " -q")
    end
    return KEYS .. "/" .. USERS[user]
end

--[[
-- Reps of a member at virtual time ts (gated bookkeeping).
-- Inputs:
--  - user [string]: actor or mod key
--  - ts   [integer]: virtual time
-- Outputs:
--  - [integer]: balance
-- Errors:
--  - "<user> : reps : <output>" : freechains query failed
-- Callers:
--  - replay loop, signer [lemmy-simple.lua]
--]]
local function reps (user, ts)
    local v = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' reps member " .. key(user) .. ".pub")
    return tonumber(v) or error(user .. ' : reps : ' .. v)
end

local nown, ndict = 0, 0

--[[
-- Key that signs a moderator's revoke/unrevoke.
-- Inputs:
--  - mod    [string]: mod key
--  - amount [integer]: reps to spend
--  - ts     [integer]: virtual time
-- Outputs:
--  - [string]: private key path (moderator or dictator)
-- Callers:
--  - replay loop [lemmy-simple.lua]
--]]
local function signer (mod, amount, ts)
    if MODS == 'own' and (not GATED or reps(mod, ts) >= amount) then
        nown = nown + 1
        return key(mod)
    end
    ndict = ndict + 1
    return DICT
end

-------------------------------------------------------------------------------
-- replay

local CID      = {}   -- item key -> cid
local AUTHOR   = {}   -- item key -> actor key
local LIKES    = {}   -- item key -> reps liked onto it (welcomes)
local WELCOMED = {}   -- actor -> welcome count
local REVOKED  = {}   -- actor -> true
local REVOKEDP = {}   -- item key -> true
local RECID    = {}   -- actor -> true
local REASONS  = {}   -- reason -> count
local N        = 0
local nposts, nrevokes, nrestores, ndeletes = 0, 0, 0, 0
local nbans, nskip_t, nskip_r = 0, 0, 0   -- bans | missing target | state
local nbirths, nres_i, nres_v, nparked = 0, 0, 0, 0
local clamped, tpost, last_ts = 0, 0, 0
local T0  = now()

local function tick ()
    N = N + 1
    if N % WINDOW == 0 then
        print(string.format(
            "== N=%d  ev avg=%.3fs  posts=%d  revokes=%d  restores=%d  deletes=%d  skip_t=%d  skip_r=%d  clamped=%d  elapsed=%.0fs",
            N, tpost/WINDOW, nposts, nrevokes, nrestores, ndeletes,
            nskip_t, nskip_r, clamped, now()-T0))
        if GATED then
            print(string.format(
                "== N=%d  births=%d  res_i=%d  res_v=%d  parked=%d  own=%d  dict=%d",
                N, nbirths, nres_i, nres_v, nparked, nown, ndict))
        end
        tpost = 0
        report('before', N)
        if SWEEP then
            local t1  = now()
            local out = exec(FC .. " chain '" .. ALIAS .. "' sweep")
            print(string.format("== N=%d  sweep=%.1fs  [%s]", N, now()-t1, out))
            report('after', N)
        end
    end
    return N == LIMIT
end

for l in io.lines(DATA .. ".tsv") do
    local ts, kind, id, user, target, reason =
        l:match("^(%d+)\t(%a+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    ts = tonumber(ts)
    if ts < last_ts then
        ts = last_ts
        clamped = clamped + 1
    end
    last_ts = ts
    local t0 = now()

    if kind == 'post' then
        local body = DATA .. ".bodies/" .. id:gsub('/', '_')
        local beg = ''
        if GATED and reps(user, ts) < 500 then
            beg = ' --beg'
        end
        local cmd = FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
            "' post --sign=" .. key(user)
        local hash = exec(cmd .. beg .. " file " .. body)
        -- the unsigned reps query may lag the signed post's own
        -- refunds: flip the beg decision once on a gate error
        if not hash:match('^%x+$') and hash:find('sufficient reputation', 1, true) then
            beg = (beg == '') and ' --beg' or ''
            hash = exec(cmd .. beg .. " file " .. body)
        end
        assert(hash:match('^%x+$'), id .. ' : ' .. hash)
        nposts = nposts + 1
        CID[id], AUTHOR[id], LIKES[id] = hash, user, 0
        if beg ~= '' then
            if WELCOME == 'never' and REVOKED[user] then
                CID[id] = nil          -- parked: no revokes
                nparked = nparked + 1
            else
                local v = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                    "' like 1000 action " .. hash .. " --sign=" .. DICT)
                assert(v:match('^%x+$'), user .. ' : welcome : ' .. v)
                LIKES[id] = 1000
                local w = (WELCOMED[user] or 0) + 1
                WELCOMED[user] = w
                if w == 1 then
                    nbirths = nbirths + 1
                elseif REVOKED[user] then
                    nres_v = nres_v + 1
                else
                    nres_i = nres_i + 1
                end
            end
        end

    elseif kind == 'remove' or kind == 'delete' then
        local cid = CID[target]
        if not cid then
            nskip_t = nskip_t + 1
        elseif REVOKEDP[target] then
            nskip_r = nskip_r + 1      -- already revoked
        else
            -- delete: the author, free; remove: outweigh the likes
            local amount = N_REVOKE + LIKES[target]
            local sign = (kind == 'delete') and key(user)
                         or signer(user, amount, ts)
            local why = (reason ~= '') and
                (" --why='" .. reason:gsub("'", "'\\''") .. "'") or ''
            local out = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' revoke " .. amount .. " " .. cid .. " --sign=" .. sign ..
                why)
            assert(out:match('^%x+$'), cid .. ' : ' .. out)
            REVOKEDP[target] = true
            if kind == 'delete' then
                ndeletes = ndeletes + 1
            else
                nrevokes = nrevokes + 1
                REASONS[reason] = (REASONS[reason] or 0) + 1
                local a = AUTHOR[target]
                if (WELCOMED[a] or 0) > 1 then
                    RECID[a] = true
                end
                REVOKED[a] = true
            end
        end

    elseif kind == 'restore' then
        local cid = CID[target]
        if not cid then
            nskip_t = nskip_t + 1
        elseif not REVOKEDP[target] then
            nskip_r = nskip_r + 1      -- not revoked
        else
            local amount = N_REVOKE + LIKES[target]
            local out = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' unrevoke " .. amount .. " " .. cid .. " --sign=" ..
                signer(user, amount, ts) .. " --file=" .. DATA ..
                ".bodies/" .. target:gsub('/', '_'))
            assert(out:match('^%x+$'), cid .. ' : ' .. out)
            REVOKEDP[target] = nil
            nrestores = nrestores + 1
        end

    elseif kind == 'ban' or kind == 'unban' then
        nbans = nbans + 1              -- counted; the member's posts follow

    end                                -- addmod: ignored

    tpost = tpost + (now() - t0)
    if tick() then break end
end

local nrecid = 0
for _ in pairs(RECID) do
    nrecid = nrecid + 1
end
local rs = {}
for k, v in pairs(REASONS) do
    rs[#rs+1] = (k == '' and '(none)' or k) .. '=' .. v
end
table.sort(rs)
print(string.format(
    "== END N=%d  posts=%d  revokes=%d  restores=%d  deletes=%d  bans=%d  users=%d  skip_t=%d  skip_r=%d  clamped=%d  elapsed=%.0fs",
    N, nposts, nrevokes, nrestores, ndeletes, nbans, nusers, nskip_t,
    nskip_r, clamped, now()-T0))
print("== END reasons " .. table.concat(rs, ' | '))
print(string.format("== END signers own=%d  dict=%d", nown, ndict))
if GATED then
    print(string.format(
        "== END births=%d  res_i=%d  res_v=%d  recid=%d  parked=%d",
        nbirths, nres_i, nres_v, nrecid, nparked))
end
