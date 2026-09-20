#!/usr/bin/env lua5.4

-- Replay a Stack Exchange site on an OPEN chain: questions and
-- answers as signed posts, up/down votes as like/dislike on them.
-- Voters are ANONYMIZED in the dump, so one shared `voter` key
-- casts every vote (open chain: it may run into debt).
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

local SITE   = env('SITE',   'retro')            -- site under ../data/se/
local LIMIT  = env('LIMIT',  false)              -- stop after N events (false = all)
local WINDOW = env('WINDOW', 5000)               -- report every WINDOW events
local SWEEP  = env('SWEEP',  true)
local ALIAS  = env('ALIAS',  '/' .. SITE)
local BASE   = env('BASE',   './.freechains-' .. SITE)
local N_VOTE = env('N_VOTE', 1000)               -- reps per vote

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

-------------------------------------------------------------------------------
-- load events

--[[
-- ISO date to unix seconds ("2016-04-19T20:11:37.597").
--]]
local function iso (s)
    local y,M,d,hh,mm,ss = s:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    return os.time({ year=y, month=M, day=d, hour=hh, min=mm, sec=ss })
end

local function attr (l, k)
    return l:match(k .. '="([^"]*)"')
end

local EV    = {}    -- { ts, seq, 'post'|'vote', ... }
local BODY  = {}    -- seid -> payload
local PT0   = {}    -- seid -> creation ts (vote clamping)
local seq   = 0

for l in io.lines("../data/se/" .. SITE .. "/Posts.xml") do
    local ty = attr(l, "PostTypeId")
    if ty == "1" or ty == "2" then
        local id = attr(l, "Id")
        local ts = iso(attr(l, "CreationDate"))
        local u  = attr(l, "OwnerUserId") or "deleted"
        seq = seq + 1
        EV[#EV+1] = { ts=ts, seq=seq, kind='post', id=id, user=u }
        PT0[id] = ts
        BODY[id] = (attr(l, "Title") or "") .. "\n" .. (attr(l, "Body") or "")
    end
end
local nposts = #EV

for l in io.lines("../data/se/" .. SITE .. "/Votes.xml") do
    local ty = attr(l, "VoteTypeId")
    if (ty == "2" or ty == "3") and BODY[attr(l, "PostId")] then
        local id = attr(l, "PostId")
        -- vote dates are DAY-granular (00:00): raise each past
        -- its target's creation, or it sorts before the post
        local ts = iso(attr(l, "CreationDate"))
        if ts <= PT0[id] then
            ts = PT0[id] + 1
        end
        seq = seq + 1
        EV[#EV+1] = { ts=ts, seq=seq, kind='vote', id=id, up=(ty=="2") }
    end
end

table.sort(EV, function (a, b)
    if a.ts == b.ts then
        return a.seq < b.seq
    end
    return a.ts < b.ts
end)

print(string.format("## SITE=%s posts=%d votes=%d events=%d LIMIT=%s",
    SITE, nposts, #EV-nposts, #EV, tostring(LIMIT)))

-------------------------------------------------------------------------------
-- setup

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
print(exec(FC .. " --now=0 chains add '" .. ALIAS .. "' init"))
for k,v in pairs(GIT) do
    os.execute("git -C " .. DIR .. " config " .. k .. " " .. v)
end

local USERS = {}
function key (user)
    local path = KEYS .. '/u' .. user
    if not USERS[user] then
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. path .. " -q")
        USERS[user] = true
    end
    return path
end

-------------------------------------------------------------------------------
-- replay

local CID     = {}   -- seid -> chain cid
local PTS     = {}   -- seid -> replayed post time
local N       = 0
local tpost   = 0
local clamped = 0
local skipped = 0    -- votes on posts that failed to land
local last_ts = 0
local T0      = now()
local TMP     = BASE .. '/payload'

for _, e in ipairs(EV) do
    local ts = e.ts
    if ts < last_ts then
        ts = last_ts
        clamped = clamped + 1
    end
    last_ts = ts

    local t0 = now()
    if e.kind == 'post' then
        local fh = io.open(TMP, 'w')
        fh:write(BODY[e.id])
        fh:close()
        local hash = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
            "' post --sign=" .. key(e.user) .. " file " .. TMP)
        assert(hash:match('^%x+$'), e.id .. ' : ' .. hash)
        CID[e.id] = hash
        PTS[e.id] = ts
        BODY[e.id] = nil
    else
        local cid = CID[e.id]
        if cid then
            local verb = e.up and 'like' or 'dislike'
            local out = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
                "' " .. verb .. " " .. N_VOTE .. " action " .. cid ..
                " --sign=" .. key('voter'))
            assert(out:match('^%x+$'), cid .. ' : ' .. out)
        else
            skipped = skipped + 1
        end
    end
    tpost = tpost + (now() - t0)
    N = N + 1

    if N % WINDOW == 0 then
        print(string.format(
            "== N=%d  ev avg=%.3fs  clamped=%d  skipped=%d  elapsed=%.0fs",
            N, tpost/WINDOW, clamped, skipped, now()-T0))
        tpost = 0
        report('before', N)
        if SWEEP then
            local t1  = now()
            local out = exec(FC .. " chain '" .. ALIAS .. "' sweep")
            print(string.format("== N=%d  sweep=%.1fs  [%s]", N, now()-t1, out))
            report('after', N)
        end
    end
    if N == LIMIT then
        break
    end
end

print(string.format("== END N=%d  clamped=%d  skipped=%d  elapsed=%.0fs",
    N, clamped, skipped, now()-T0))
