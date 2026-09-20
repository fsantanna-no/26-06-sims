#!/usr/bin/env lua5.4

-- Replay the comp.compilers archive on an OPEN chain, one signed
-- post per message (mirror of ../chat/chat-simple.lua).
-- Payload = the mail record (headers + body), ~3kB each.
-- Measures, per window: post latency, disk growth, sweep cost.
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

local MBOX   = env('MBOX',   '../data/yyy.mbox')
local LIMIT  = env('LIMIT',  false)              -- stop after N msgs (false = all)
local WINDOW = env('WINDOW', 5000)               -- report every WINDOW msgs
local SWEEP  = env('SWEEP',  true)               -- `sweep` at every report
local ALIAS  = env('ALIAS',  '/compilers')       -- alias (must start with '/')
local BASE   = env('BASE',   '../.freechains')   -- root + keys (relative)

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
-- setup

print(string.format("## MBOX=%s LIMIT=%s WINDOW=%d SWEEP=%s GIT=%s",
    MBOX, tostring(LIMIT), WINDOW, tostring(SWEEP), tostring(next(GIT) ~= nil)))
os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
print(exec(FC .. " --now=0 chains add '" .. ALIAS .. "' init"))
for k,v in pairs(GIT) do
    os.execute("git -C " .. DIR .. " config " .. k .. " " .. v)
end

local USERS  = {}
local nusers = 0

--[[
-- Ensure a keypair for user; From lines are arbitrary bytes, so
-- the key file is named by a sanitized, capped slug.
--]]
function key (user)
    local slug = user:gsub("[^%w]", "_"):sub(1, 60)
    local path = KEYS .. '/' .. slug
    if not USERS[slug] then
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. path .. " -q")
        USERS[slug] = true
        nusers = nusers + 1
    end
    return path
end

-------------------------------------------------------------------------------
-- mbox parsing (as paper.lua)

local MON = {
    Jan=1, Feb=2, Mar=3, Apr=4,  May=5,  Jun=6,
    Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12
}

local f = assert(io.open(MBOX))

function read_until (patt)
    while true do
        local l = f:read('*l')
        if not l then
            return nil
        end
        local ret = { string.match(l, patt) }
        if #ret > 0 then
            return table.unpack(ret)
        end
    end
end

-------------------------------------------------------------------------------
-- replay

local N       = 0
local tpost   = 0
local clamped = 0       -- out-of-order times raised to the clock
local last_ts = 0
local T0      = now()
local TMP     = BASE .. '/payload'

while true do
    local from = read_until("^From: (.*)")
    if not from then break end
    local subj = read_until("^Subject: (.*)") or ''
    local date = read_until("^Date: (.*)") or ''
    read_until("^$")
    local body = ''
    local term = false
    while true do
        local l = f:read('*l')
        if (not l) or string.match(l, "^From %-?%d+$") then
            term = (not l)
            break
        end
        body = body ..'\n'.. l
    end

    local ts; do
        local p = "[^%d]*(%d+)[ -](%a+)[ -](%d+) (%d+):(%d+)"
        local d,m,y,hh,mm = string.match(date, p)
        local M
        if d then
            M = MON[m]
        else
            local p = "(%d+)/(%d+)/(%d+)"
            y,M,d = string.match(date, p)
            hh,mm = 0,0
        end
        assert(d, date)
        y = tonumber(y)
        if y < 1000 then
            if y < 30 then
                y = y + 2000
            else
                y = y + 1900
            end
        end
        ts = os.time({ year=y, month=M, day=d, hour=hh, min=mm, sec=0 })
    end

    -- `too old` refuses < NOW(backs)-1h: raise stragglers to the
    -- running clock and count them
    if ts < last_ts then
        ts = last_ts
        clamped = clamped + 1
    end
    last_ts = ts

    -- payload = the record, via FILE (bodies are shell-hostile)
    local fh = io.open(TMP, 'w')
    fh:write("From: "..from.."\nSubject: "..subj.."\nDate: "..date.."\n"..body.."\n")
    fh:close()

    local t0 = now()
    local hash = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS ..
        "' post --sign=" .. key(from) .. " file " .. TMP)
    tpost = tpost + (now() - t0)
    assert(string.match(hash, '^%x+$'), from .. ' : ' .. hash)
    N = N + 1
    print(N, ts, hash)

    if N % WINDOW == 0 then
        print(string.format("== N=%d  post avg=%.3fs  users=%d  clamped=%d  elapsed=%.0fs",
            N, tpost/WINDOW, nusers, clamped, now()-T0))
        tpost = 0
        report('before', N)
        if SWEEP then
            local t1  = now()
            local out = exec(FC .. " chain '" .. ALIAS .. "' sweep")
            print(string.format("== N=%d  sweep=%.1fs  [%s]", N, now()-t1, out))
            report('after', N)
        end
    end
    if term or N == LIMIT then
        break
    end
end

print(string.format("== END N=%d  users=%d  clamped=%d  elapsed=%.0fs",
    N, nusers, clamped, now()-T0))
