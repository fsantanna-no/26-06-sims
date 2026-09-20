#!/usr/bin/env lua5.4

-- Replay one Wikipedia article's FULL edit history: each revision
-- is a signed post (payload = wikitext); a revert (sha1 equal to
-- an earlier revision) REVOKES the intermediate revisions.
-- OPEN mode (default): ungated chain, IP editors share `anon`.
-- GATED mode (GATED=true): `--dictator` chain; per-IP keys;
-- reps < 500 begs and the dictator welcomes (like 1000); a
-- reverter below 1000 reps cannot revoke, the dictator does.
-- Counters: births, resurrections (innocent|vandal), recidivists,
-- community vs dictator revokes.
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

local PAGE     = env('PAGE',     'ab')       -- prefix under ../data/wiki/
local LIMIT    = env('LIMIT',    false)      -- stop after N events
local WINDOW   = env('WINDOW',   5000)       -- report every WINDOW events
local SWEEP    = env('SWEEP',    true)
local GATED    = env('GATED',    false)      -- dictator-gated chain
local WELCOME  = env('WELCOME',  'always')   -- always | never (re-welcome revoked)
local IPKEYS   = env('IPKEYS',   GATED)      -- key per IP (else shared anon)
local ALIAS    = env('ALIAS',    '/' .. PAGE)
local BASE     = env('BASE',     './.freechains-' .. PAGE ..
                                 (GATED and '-gated' or ''))
local N_REVOKE = env('N_REVOKE', 1000)       -- reps per revoke

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

--[[
-- ISO date to unix seconds ("2001-10-16T20:46:35Z").
-- Inputs:
--  - s [string]: ISO timestamp
-- Outputs:
--  - [integer]: unix seconds
--]]
local function iso (s)
    local y,M,d,hh,mm,ss = s:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    return os.time({ year=y, month=M, day=d, hour=hh, min=mm, sec=ss })
end

-------------------------------------------------------------------------------
-- streaming export parser

--[[
-- Iterate revisions of `../data/wiki/<PAGE>*.xml` in file order.
-- Handles multi-line <text>; dedups batch-boundary revisions.
-- Inputs:
--  - none (reads PAGE)
-- Outputs:
--  - [function]: iterator of { id, ts, sha1, user, ip, text }
--]]
local function revisions ()
    local files = {}
    local fs = exec("ls ../data/wiki/" .. PAGE .. "*.xml | sort")
    for f in fs:gmatch("[^\n]+") do
        files[#files+1] = f
    end
    assert(#files > 0, "no ../data/wiki/" .. PAGE .. "*.xml")
    local SEEN = {}
    return coroutine.wrap(function ()
        for _, path in ipairs(files) do
            local rev, intext
            for l in io.lines(path) do
                if l:find("<revision>") then
                    rev = { text = {} }
                elseif rev then
                    if intext then
                        local e = l:match("^(.*)</text>")
                        if e then
                            rev.text[#rev.text+1] = e
                            intext = false
                        else
                            rev.text[#rev.text+1] = l
                        end
                    elseif l:find("</revision>") then
                        if rev.id and not SEEN[rev.id] then
                            SEEN[rev.id] = true
                            rev.text = table.concat(rev.text, "\n")
                            coroutine.yield(rev)
                        end
                        rev = nil
                    elseif not rev.id and l:match("<id>(%d+)</id>") then
                        rev.id = l:match("<id>(%d+)</id>")
                    elseif l:find("<timestamp>") then
                        rev.ts = iso(l:match("<timestamp>([^<]+)"))
                    elseif l:find("<sha1>") then
                        rev.sha1 = l:match("<sha1>([^<]+)")
                    elseif l:find("<username>") then
                        rev.user = l:match("<username>([^<]*)")
                    elseif l:find("<ip>") then
                        rev.ip = l:match("<ip>([^<]*)")
                    else
                        local t = l:match('<text[^>]*>(.*)</text>')
                        if t then
                            rev.text[#rev.text+1] = t
                        else
                            t = l:match("<text[^>]*>(.*)")
                            if t then
                                rev.text[#rev.text+1] = t
                                intext = true
                            end
                        end
                    end
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- setup

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
local DICT = KEYS .. '/wp'
if GATED then
    os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. DICT .. " -q")
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
-- Ensure a keypair for editor (shared `anon` unless IPKEYS).
-- Inputs:
--  - user [string]: editor name, ip, or 'anon'
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
-- Reps of editor at virtual time ts (gated bookkeeping).
-- Inputs:
--  - user [string]: editor id
--  - ts   [integer]: virtual time of the query
-- Outputs:
--  - [integer]: current balance
--]]
local function reps (user, ts)
    local v = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' reps member " .. key(user) .. ".pub")
    return tonumber(v) or error(user .. ' : reps : ' .. v)
end

-------------------------------------------------------------------------------
-- replay

local REVS      = {}   -- ordered: { cid, who, revoked, parked }
local IDX       = {}   -- sha1 -> last index in REVS
local WELCOMED  = {}   -- editor -> welcome count
local REVOKED   = {}   -- editor -> true (ever had a rev revoked)
local RECID     = {}   -- editor -> true (revoked after resurrection)
local N         = 0
local nrevs     = 0
local nrevokes  = 0
local nbirths   = 0
local nres_i    = 0    -- innocent resurrections
local nres_v    = 0    -- vandal resurrections
local ncomm     = 0    -- community-signed revokes
local ndict     = 0    -- dictator-signed revokes
local nparked   = 0    -- begs never welcomed (WELCOME=never)
local clamped   = 0
local tpost     = 0
local last_ts   = 0
local T0        = now()
local TMP       = BASE .. '/payload'

--[[
-- Window/limit bookkeeping after each chain event.
-- Inputs:
--  - none (uses upvalues)
-- Outputs:
--  - [boolean]: true to stop (LIMIT reached)
--]]
local function tick ()
    N = N + 1
    if N % WINDOW == 0 then
        print(string.format(
            "== N=%d  ev avg=%.3fs  revokes=%d  clamped=%d  elapsed=%.0fs",
            N, tpost/WINDOW, nrevokes, clamped, now()-T0))
        if GATED then
            print(string.format(
                "== N=%d  births=%d  res_i=%d  res_v=%d  comm=%d  dict=%d  parked=%d",
                N, nbirths, nres_i, nres_v, ncomm, ndict, nparked))
        end
        tpost = 0
        report('before', N)
        if SWEEP then
            local t1  = now()
            local out = exec(FC .. " chain '" .. ALIAS .. "' sweep")
            print(string.format("== N=%d  sweep=%.1fs  [%s]",
                N, now()-t1, out))
            report('after', N)
        end
    end
    return N == LIMIT
end

for rev in revisions() do
    local ts = rev.ts
    if ts < last_ts then
        ts = last_ts
        clamped = clamped + 1
    end
    last_ts = ts
    local who = rev.user or (IPKEYS and rev.ip) or 'anon'

    -- post the revision (beg when gated and broke)
    local t0  = now()
    local fh  = io.open(TMP, 'w')
    fh:write(rev.text)
    fh:close()
    local beg = ''
    if GATED and reps(who, ts) < 500 then
        beg = ' --beg'
    end
    local cmd = FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' post --sign=" .. key(who)
    local hash = exec(cmd .. beg .. " file " .. TMP)
    -- the unsigned reps query may lag the signed post's own
    -- refunds: flip the beg decision once on a gate error
    if not hash:match('^%x+$') and hash:find('sufficient reputation', 1, true) then
        beg = (beg == '') and ' --beg' or ''
        hash = exec(cmd .. beg .. " file " .. TMP)
    end
    assert(hash:match('^%x+$'), rev.id .. ' : ' .. hash)
    nrevs = nrevs + 1
    local entry = { cid = hash, who = who }
    REVS[#REVS+1] = entry

    -- welcome the beg (birth or resurrection), or leave parked
    if beg ~= '' then
        if WELCOME == 'never' and REVOKED[who] then
            entry.parked = true
            nparked = nparked + 1
        else
            local v = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' like 1000 action " .. hash .. " --sign=" .. DICT)
            assert(v:match('^%x+$'), who .. ' : welcome : ' .. v)
            entry.likes = 1000
            local w = (WELCOMED[who] or 0) + 1
            WELCOMED[who] = w
            if w == 1 then
                nbirths = nbirths + 1
            elseif REVOKED[who] then
                nres_v = nres_v + 1
            else
                nres_i = nres_i + 1
            end
        end
    end
    tpost = tpost + (now() - t0)
    if tick() then break end

    -- revert? revoke the revisions since the matched one
    local prev = rev.sha1 and IDX[rev.sha1]
    if prev then
        for i = prev+1, #REVS-1 do
            local r = REVS[i]
            if not (r.revoked or r.parked) then
                local t1 = now()
                local signer = DICT
                if not GATED then
                    signer = key(who)
                    ncomm = ncomm + 1
                elseif reps(who, ts) >= N_REVOKE + (r.likes or 0) then
                    signer = key(who)
                    ncomm = ncomm + 1
                else
                    ndict = ndict + 1
                end
                -- a like counts on the revoke axis: outweigh it
                local amount = N_REVOKE + (r.likes or 0)
                local out = exec(FC .. " --now=" .. ts .. " chain '" ..
                    ALIAS .. "' revoke " .. amount .. " " .. r.cid ..
                    " --sign=" .. signer)
                assert(out:match('^%x+$'), r.cid .. ' : ' .. out)
                r.revoked = true
                nrevokes = nrevokes + 1
                if (WELCOMED[r.who] or 0) > 1 then
                    RECID[r.who] = true
                end
                REVOKED[r.who] = true
                tpost = tpost + (now() - t1)
                if tick() then goto done end
            end
        end
    end
    if rev.sha1 then
        IDX[rev.sha1] = #REVS
    end
end
::done::

local nrecid = 0
for _ in pairs(RECID) do
    nrecid = nrecid + 1
end
print(string.format(
    "== END N=%d  revs=%d  revokes=%d  users=%d  clamped=%d  elapsed=%.0fs",
    N, nrevs, nrevokes, nusers, clamped, now()-T0))
if GATED then
    print(string.format(
        "== END births=%d  res_i=%d  res_v=%d  recid=%d  comm=%d  dict=%d  parked=%d",
        nbirths, nres_i, nres_v, nrecid, ncomm, ndict, nparked))
end
