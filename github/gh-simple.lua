#!/usr/bin/env lua5.4

-- Replay a GitHub repo's issues on freechains (events from
-- gh-events.py): issues/comments as signed posts by login,
-- 👍/👎 as like/dislike by the reacting login, minimized
-- comments as REVOKES by the `maintainer` key (the minimizer is
-- not exposed). The first corpus with LIKE and REVOKE.
-- OPEN mode: ungated. GATED mode: `--dictator` = maintainer;
-- begs + welcomes; votes only when affordable (else skipped);
-- resurrection split by prior revocation; revoke reasons kept.
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

local REPO     = env('REPO',     'yt-dlp-yt-dlp')  -- under ../data/github/
local LIMIT    = env('LIMIT',    false)
local WINDOW   = env('WINDOW',   5000)
local SWEEP    = env('SWEEP',    true)
local GATED    = env('GATED',    false)
local WELCOME  = env('WELCOME',  'always')   -- always | never
local ALIAS    = env('ALIAS',    '/' .. REPO:match('[^-]+$'))
local BASE     = env('BASE',     './.freechains-' .. REPO ..
                                 (GATED and '-gated' or ''))
local N_VOTE   = env('N_VOTE',   1000)
local N_REVOKE = env('N_REVOKE', 1000)

local GIT = env('GIT', true) and {
    ['pack.threads']      = '2',
    ['pack.windowMemory'] = '512m',
} or {}

-------------------------------------------------------------------------------
-- helpers (as chat-simple)

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
local DATA = exec("realpath -m ../data/github/" .. REPO)   -- absolute: git -C chdirs

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
local DICT = KEYS .. '/maintainer'
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
-- Ensure a keypair for a login.
-- Inputs:
--  - user [string]: GitHub login (or 'ghost')
-- Outputs:
--  - [string]: private key path (.pub sibling for reps)
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
-- Reps of a login at virtual time ts (gated bookkeeping).
-- Inputs:
--  - user [string]: login
--  - ts   [integer]: virtual time
-- Outputs:
--  - [integer]: balance
--]]
local function reps (user, ts)
    local v = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' reps member " .. key(user) .. ".pub")
    return tonumber(v) or error(user .. ' : reps : ' .. v)
end

-------------------------------------------------------------------------------
-- replay

local CID      = {}   -- post id -> cid
local AUTHOR   = {}   -- post id -> login
local LIKES    = {}   -- post id -> reps liked onto it (revoke axis)
local WELCOMED = {}   -- login -> welcome count
local REVOKED  = {}   -- login -> true
local REVOKEDP = {}   -- post id -> true
local RECID    = {}   -- login -> true
local REASONS  = {}   -- reason -> count
local N        = 0
local nposts, nlikes, ndis, nrevokes = 0, 0, 0, 0
local nskip_t, nskip_v = 0, 0      -- missing target | unaffordable vote
local nbirths, nres_i, nres_v, nparked = 0, 0, 0, 0
local clamped, tpost, last_ts = 0, 0, 0
local T0  = now()
local TMP = BASE .. '/payload'

local function tick ()
    N = N + 1
    if N % WINDOW == 0 then
        print(string.format(
            "== N=%d  ev avg=%.3fs  posts=%d  likes=%d  dislikes=%d  revokes=%d  skip_t=%d  skip_v=%d  clamped=%d  elapsed=%.0fs",
            N, tpost/WINDOW, nposts, nlikes, ndis, nrevokes, nskip_t, nskip_v,
            clamped, now()-T0))
        if GATED then
            print(string.format(
                "== N=%d  births=%d  res_i=%d  res_v=%d  parked=%d",
                N, nbirths, nres_i, nres_v, nparked))
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
        -- empty bodies get a placeholder IN PLACE: the path must
        -- stay valid (a like on a revoked post re-supplies it)
        local body = DATA .. ".bodies/" .. id
        local f = io.open(body)
        local sz = f and f:seek('end') or 0
        if f then f:close() end
        if sz == 0 then
            local fh = io.open(body, 'w')
            fh:write("(empty)")
            fh:close()
        end
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
                CID[id] = nil          -- parked: no votes, no revokes
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

    elseif kind == 'like' or kind == 'dislike' then
        local cid = CID[target]
        if not cid then
            nskip_t = nskip_t + 1
        elseif GATED and reps(user, ts) < N_VOTE then
            nskip_v = nskip_v + 1
        else
            -- a like on a REVOKED post must carry the original payload
            local file = ''
            if kind == 'like' and REVOKEDP[target] then
                file = " --file=" .. DATA .. ".bodies/" .. target
            end
            local out = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' " .. kind .. " " .. N_VOTE .. " action " .. cid ..
                " --sign=" .. key(user) .. file)
            assert(out:match('^%x+$'), cid .. ' : ' .. out)
            if kind == 'like' then
                nlikes = nlikes + 1
                LIKES[target] = LIKES[target] + N_VOTE
                if REVOKEDP[target] then
                    print("like-on-revoked", cid, target, LIKES[target])
                end
            else
                ndis = ndis + 1
            end
        end

    elseif kind == 'minimize' then
        local cid = CID[target]
        if not cid then
            nskip_t = nskip_t + 1
        else
            local amount = N_REVOKE + LIKES[target]
            local out = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' revoke " .. amount .. " " .. cid .. " --sign=" .. DICT)
            assert(out:match('^%x+$'), cid .. ' : ' .. out)
            nrevokes = nrevokes + 1
            REVOKEDP[target] = true
            REASONS[reason] = (REASONS[reason] or 0) + 1
            print("revoke", cid, target, reason, LIKES[target])
            local a = AUTHOR[target]
            if (WELCOMED[a] or 0) > 1 then
                RECID[a] = true
            end
            REVOKED[a] = true
        end
    end

    tpost = tpost + (now() - t0)
    if tick() then break end
end

local nrecid = 0
for _ in pairs(RECID) do
    nrecid = nrecid + 1
end
local rs = {}
for k, v in pairs(REASONS) do
    rs[#rs+1] = k .. '=' .. v
end
table.sort(rs)
print(string.format(
    "== END N=%d  posts=%d  likes=%d  dislikes=%d  revokes=%d  users=%d  skip_t=%d  skip_v=%d  clamped=%d  elapsed=%.0fs",
    N, nposts, nlikes, ndis, nrevokes, nusers, nskip_t, nskip_v, clamped, now()-T0))
print("== END reasons " .. table.concat(rs, ' '))
if GATED then
    print(string.format(
        "== END births=%d  res_i=%d  res_v=%d  recid=%d  parked=%d",
        nbirths, nres_i, nres_v, nrecid, nparked))
end
