#!/usr/bin/env lua5.4

-- Replay a Lemmy community on TWO freechains peers, one per
-- instance: H (home, lemmy.dbzer0.com) and F (feddit.org).
-- Events from both instance streams (lemmy-events.py) are merged
-- and deduplicated by item key; each event runs on the peer of
-- its actor (feddit.org actors on F, everyone else on H, since
-- federated posts reach the home first).
-- Federation = sync by pull (`sync recv <dir>`), no daemons:
--  - F pulls from H every SYNC events (home -> subscriber)
--  - H pulls from F every SYNC events until BLOCK (the block
--    lemmy.dbzer0.com -> feddit.org), never after: ONE-WAY
--    partition, as observed in Lemmy
-- OPEN chain only; no votes. SINGLE RUN: BASE is wiped on start.

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

local COMM     = env('COMM',     'adhd@lemmy.dbzer0.com')
local HOME     = env('HOME_I',   'lemmy.dbzer0.com')
local COPY     = env('COPY_I',   'feddit.org')
local BLOCK    = env('BLOCK',    1771450954)     -- fediseer: 2026-02-18 21:42 UTC
local SYNC     = env('SYNC',     10)             -- events between syncs
local LOCALMOD = env('LOCALMOD', 'sync')         -- sync | skip (F mods)
local LIMIT    = env('LIMIT',    false)
local WINDOW   = env('WINDOW',   2000)
local SWEEP    = env('SWEEP',    true)
local ALIAS    = env('ALIAS',    '/' .. COMM:match('^[^@]+'))
local BASE     = env('BASE',     './.freechains-p2p-' .. COMM)
local N_REVOKE = env('N_REVOKE', 1000)

-------------------------------------------------------------------------------
-- helpers (as lemmy-simple)

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
local KEYS = BASE .. '/keys'
local DATA = exec("realpath -m ../data/lemmy")

-- peers: root, chain dir, CLI prefix
local P = {}
for _, p in ipairs{'H', 'F'} do
    local root = BASE .. '/' .. p
    P[p] = {
        root = root,
        dir  = root .. '/chains/' .. string.sub(ALIAS, 2) .. '/',
        fc   = "freechains --root=" .. root,
    }
end

-------------------------------------------------------------------------------
-- merged stream

--[[
-- Load one instance stream.
-- Inputs:
--  - inst [string]: instance host
-- Outputs:
--  - [table]: events {ts, kind, id, user, target, reason, src}
-- Callers:
--  - main chunk [lemmy-p2p.lua]
--]]
local function load (inst)
    local evs = {}
    local src = DATA .. '/' .. inst .. '-' .. COMM
    for l in io.lines(src .. '.tsv') do
        local ts, kind, id, user, target, reason =
            l:match("^(%d+)\t(%a+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        evs[#evs+1] = { ts=tonumber(ts), kind=kind, id=id, user=user,
                        target=target, reason=reason, src=src }
    end
    return evs
end

--[[
-- Peer of an actor: COPY actors and COPY mods on F, all else H.
-- Inputs:
--  - user [string]: actor key or mod key
-- Outputs:
--  - [string]: 'H' or 'F'
-- Callers:
--  - main chunk [lemmy-p2p.lua]
--]]
local function peer (user)
    local host = user:match('^mod/([^/]+)/') or user:match('^([^/]+)/')
    return (host == COPY) and 'F' or 'H'
end

-- merge: posts by item key (earliest), actions by (kind, target)
-- (earliest: a later one is the other instance's federated copy)
local EV, SEEN = {}, {}
local ndup = 0
for _, inst in ipairs{HOME, COPY} do
    for _, e in ipairs(load(inst)) do
        local k
        if e.kind == 'post' then
            k = 'post ' .. e.id
        elseif e.kind == 'remove' or e.kind == 'restore'
            or e.kind == 'delete' then
            k = e.kind .. ' ' .. e.target
        end
        if k then
            local old = SEEN[k]
            if not old then
                SEEN[k] = e
                EV[#EV+1] = e
            else
                ndup = ndup + 1
                if e.ts < old.ts then          -- keep the earliest
                    old.ts, old.user, old.reason = e.ts, e.user, e.reason
                end
            end
        end                                    -- ban/addmod: ignored
    end
end
table.sort(EV, function (a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    return a.kind == 'post' and b.kind ~= 'post'
end)
print(string.format("== merged events=%d  dups=%d", #EV, ndup))

-------------------------------------------------------------------------------
-- setup

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
local T_1 = EV[1].ts
print(exec(P.H.fc .. " --now=" .. T_1 .. " chains add '" .. ALIAS .. "' init"))
print(exec(P.F.fc .. " --now=" .. T_1 .. " chains add '" .. ALIAS ..
    "' clone " .. P.H.dir))

local USERS  = {}
local nusers = 0

--[[
-- Ensure a keypair for a member or moderator (shared by peers).
-- Inputs:
--  - user [string]: actor key or mod key
-- Outputs:
--  - [string]: private key path
-- Callers:
--  - replay loop [lemmy-p2p.lua]
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
-- Payload file of an item, from whichever stream has it.
-- Inputs:
--  - e [table]: the item's post event
-- Outputs:
--  - [string]: body path
-- Callers:
--  - replay loop [lemmy-p2p.lua]
--]]
local function body (e)
    return e.src .. '.bodies/' .. e.id:gsub('/', '_')
end

local nsync, nfail, tsync = { H=0, F=0 }, { H=0, F=0 }, 0
local FAILS = {}   -- first line of a failed sync -> count

--[[
-- Pull the chain into peer `to` from peer `from`.
-- Inputs:
--  - to   [string]: 'H' or 'F' (receiver)
--  - from [string]: 'H' or 'F' (sender)
--  - ts   [integer]: virtual time
-- Outputs:
--  - [boolean]: true on success
-- Callers:
--  - federate, main chunk [lemmy-p2p.lua]
--]]
local function pull (to, from, ts)
    local t0  = now()
    local out = exec(P[to].fc .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' sync recv " .. P[from].dir .. "; echo rc=$?")
    tsync = tsync + (now() - t0)
    nsync[to] = nsync[to] + 1
    if out:match('rc=0$') then
        return true
    end
    nfail[to] = nfail[to] + 1
    local msg = (out:match('[^\n]*ERROR[^\n]*') or out:match('^[^\n]*'))
    FAILS[msg] = (FAILS[msg] or 0) + 1
    return false
end

--[[
-- One federation round: F pulls from H; H pulls from F only
-- before the block.
-- Inputs:
--  - ts [integer]: virtual time
-- Outputs:
--  - none
-- Callers:
--  - replay loop, main chunk [lemmy-p2p.lua]
--]]
local function federate (ts)
    pull('F', 'H', ts)
    if ts < BLOCK then
        pull('H', 'F', ts)
    end
end

-------------------------------------------------------------------------------
-- replay

local CID      = { H={}, F={} }   -- item key -> cid, per peer
local REVOKEDP = {}               -- item key -> true
local N        = 0
local nposts, nrevokes, nrestores, ndeletes = 0, 0, 0, 0
local nskip_t, nskip_r, nskip_l = 0, 0, 0   -- missing | state | local mod
local byp      = { H=0, F=0 }
local tact, last_ts = 0, 0
local T0 = now()

--[[
-- Cid of an item (from whichever peer posted it); the action
-- fails on a peer that has not received it yet.
-- Inputs:
--  - p   [string]: 'H' or 'F'
--  - key [string]: item key
-- Outputs:
--  - [string|nil]: cid, if any peer posted the item
-- Callers:
--  - replay loop [lemmy-p2p.lua]
--]]
local function cid (p, key)
    return CID[p][key] or CID[p == 'H' and 'F' or 'H'][key]
end

for _, e in ipairs(EV) do
    local ts = math.max(e.ts, last_ts)
    last_ts = ts
    local p  = peer(e.user)
    local fc = P[p].fc .. " --now=" .. ts .. " chain '" .. ALIAS .. "' "
    local t0 = now()

    if e.kind == 'post' then
        local hash = exec(fc .. "post --sign=" .. key(e.user) ..
            " file " .. body(e))
        assert(hash:match('^%x+$'), e.id .. ' : ' .. hash)
        CID[p][e.id] = hash
        nposts = nposts + 1
        byp[p] = byp[p] + 1

    elseif p == 'F' and e.user:match('^mod/') and LOCALMOD == 'skip' then
        nskip_l = nskip_l + 1

    elseif e.kind == 'remove' or e.kind == 'delete' then
        local c = cid(p, e.target)
        if not c then
            nskip_t = nskip_t + 1
        elseif REVOKEDP[e.target] then
            nskip_r = nskip_r + 1
        else
            local why = (e.reason ~= '') and
                (" --why='" .. e.reason:gsub("'", "'\\''") .. "'") or ''
            local out = exec(fc .. "revoke " .. N_REVOKE .. " " .. c ..
                " --sign=" .. key(e.user) .. why)
            if out:match('^%x+$') then
                REVOKEDP[e.target] = true
                if e.kind == 'delete' then
                    ndeletes = ndeletes + 1
                else
                    nrevokes = nrevokes + 1
                end
                byp[p] = byp[p] + 1
            else
                nskip_t = nskip_t + 1
                print('revoke-fail', p, e.target, out:match('^[^\n]*'))
            end
        end

    elseif e.kind == 'restore' then
        local c = cid(p, e.target)
        if not c then
            nskip_t = nskip_t + 1
        elseif not REVOKEDP[e.target] then
            nskip_r = nskip_r + 1
        else
            local src = SEEN['post ' .. e.target]
            local out = exec(fc .. "unrevoke " .. N_REVOKE .. " " .. c ..
                " --sign=" .. key(e.user) .. " --file=" .. body(src))
            if out:match('^%x+$') then
                REVOKEDP[e.target] = nil
                nrestores = nrestores + 1
                byp[p] = byp[p] + 1
            else
                nskip_t = nskip_t + 1
                print('unrevoke-fail', p, e.target, out:match('^[^\n]*'))
            end
        end
    end
    tact = tact + (now() - t0)

    N = N + 1
    if N % SYNC == 0 then
        federate(ts)
    end
    if N % WINDOW == 0 then
        print(string.format(
            "== N=%d  ev avg=%.3fs  posts=%d (H %d, F %d)  revokes=%d  deletes=%d  syncs H=%d F=%d  fails H=%d F=%d  sync=%.0fs  elapsed=%.0fs",
            N, tact/WINDOW, nposts, byp.H, byp.F, nrevokes, ndeletes,
            nsync.H, nsync.F, nfail.H, nfail.F, tsync, now()-T0))
        tact = 0
        if SWEEP then
            for _, q in ipairs{'H', 'F'} do
                exec(P[q].fc .. " chain '" .. ALIAS .. "' sweep")
            end
        end
    end
    if N == LIMIT then break end
end

-------------------------------------------------------------------------------
-- end: last round, then compare the two views

federate(last_ts)

--[[
-- Consensus order of a peer, as a set and a count.
-- Inputs:
--  - p [string]: 'H' or 'F'
-- Outputs:
--  - [table]: set of action ids
--  - [integer]: number of actions
-- Callers:
--  - main chunk [lemmy-p2p.lua]
--]]
local function order (p)
    local set, n = {}, 0
    for id in exec(P[p].fc .. " chain '" .. ALIAS .. "' list order")
        :gmatch('%x+') do
        if #id >= 40 and not set[id] then
            set[id], n = true, n + 1
        end
    end
    return set, n
end

local SH, nh = order('H')
local SF, nf = order('F')
local onlyh, onlyf = 0, 0
for id in pairs(SH) do if not SF[id] then onlyh = onlyh + 1 end end
for id in pairs(SF) do if not SH[id] then onlyf = onlyf + 1 end end

local fs = {}
for k, v in pairs(FAILS) do
    fs[#fs+1] = k .. ' x' .. v
end
print(string.format(
    "== END N=%d  posts=%d (H %d, F %d)  revokes=%d  restores=%d  deletes=%d  users=%d  skip_t=%d  skip_r=%d  skip_l=%d  elapsed=%.0fs",
    N, nposts, byp.H, byp.F, nrevokes, nrestores, ndeletes, nusers,
    nskip_t, nskip_r, nskip_l, now()-T0))
print(string.format(
    "== END syncs H=%d F=%d  fails H=%d F=%d  sync time=%.0fs",
    nsync.H, nsync.F, nfail.H, nfail.F, tsync))
print(string.format(
    "== END order H=%d  F=%d  only-H=%d  only-F=%d", nh, nf, onlyh, onlyf))
print("== END sync failures: " .. (#fs > 0 and table.concat(fs, ' | ') or 'none'))
