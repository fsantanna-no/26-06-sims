#!/usr/bin/env lua5.4

-- Simplest chat replay on an OPEN chain (no pioneers, no gates).
-- Every message is a signed post; nothing else.
-- Measures, per window of WINDOW messages:
--  - post latency: avg wall time of `post` (grows with state size)
--  - disk growth: loose bytes written in the window
--  - sweep cost: time of `sweep` and the packed floor after it
-- SINGLE INSTANCE: BASE is wiped on start.

-------------------------------------------------------------------------------
-- config

-- (each may be overridden by an env var of the same name)
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

local CHAT   = env('CHAT',   '../data/wikimedia.chat')   -- input log
local LIMIT  = env('LIMIT',  10000)              -- stop after N msgs (nil = all)
local WINDOW = env('WINDOW', 5000)               -- report every WINDOW msgs
local SWEEP  = env('SWEEP',  true)               -- `sweep` at every report
local ALIAS  = env('ALIAS',  '/chat')            -- alias (must start with '/')
local BASE   = env('BASE',   '../.freechains')   -- root + keys (relative)

-- git config for the chain repo: bounds gc memory (the default
-- OOMs at ~6.6 GB from 10k msgs on); costs ~40% sweep time
-- (GIT=false disables it)
local GIT = env('GIT', true) and {
    ['pack.threads']      = '2',
    ['pack.windowMemory'] = '512m',
} or {}

-------------------------------------------------------------------------------
-- helpers

--[[
-- Run a shell command and return its trimmed output.
-- Inputs:
--  - cmd [string]: shell command
-- Outputs:
--  - [string]: stdout+stderr without trailing blanks
--]]
function exec (cmd)
    local f = io.popen(cmd .. " 2>&1")
    local v = f:read('*a')
    f:close()
    return (string.gsub(v, "%s+$", ""))
end

--[[
-- Wall clock in seconds (os.clock ignores child processes).
-- Outputs:
--  - [number]: seconds since epoch, ns resolution
--]]
function now ()
    return tonumber(exec("date +%s.%N"))
end

-- absolute paths: git -C chdirs, so relative --sign would break
BASE = exec("realpath -m " .. BASE)
local ROOT = BASE .. '/root'
local KEYS = BASE .. '/keys'
local DIR  = ROOT .. '/chains/' .. string.sub(ALIAS, 2) .. '/'
local FC   = "freechains --root=" .. ROOT

--[[
-- Chain repo disk usage.
-- Outputs:
--  - [number]: total bytes (du)
--  - [number]: packed bytes
--  - [number]: loose bytes
--]]
function disk ()
    local total = tonumber(exec("du -sb " .. DIR .. " | cut -f1")) or 0
    local co    = exec("git -C " .. DIR .. " count-objects -v")
    local loose = (tonumber(co:match("size: (%d+)"))      or 0) * 1024
    local pack  = (tonumber(co:match("size%-pack: (%d+)")) or 0) * 1024
    return total, pack, loose
end

--[[
-- Print a disk line.
-- Inputs:
--  - tag [string]: label
--  - N   [number]: messages so far
--]]
function report (tag, N)
    local g, pack, loose = disk()
    print(string.format("== N=%d  %-6s git=%.1f MB  (pack %.1f, loose %.1f)",
        N, tag, g/1e6, pack/1e6, loose/1e6))
end

-------------------------------------------------------------------------------
-- setup

print(string.format("## LIMIT=%s WINDOW=%d SWEEP=%s GIT=%s",
    tostring(LIMIT), WINDOW, tostring(SWEEP), tostring(next(GIT) ~= nil)))
os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
print(exec(FC .. " --now=0 chains add '" .. ALIAS .. "' init"))
for k,v in pairs(GIT) do
    os.execute("git -C " .. DIR .. " config " .. k .. " " .. v)
end

local USERS = {}

--[[
-- Ensure a keypair for user.
-- Inputs:
--  - user [string]: nickname
-- Outputs:
--  - [string]: private key path
--]]
function key (user)
    local path = KEYS .. '/' .. user
    if not USERS[user] then
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. path .. " -q")
        USERS[user] = true
    end
    return path
end

-------------------------------------------------------------------------------
-- replay

local N       = 0
local tpost   = 0     -- post seconds in the window
local clamped = 0     -- out-of-order times raised to the clock
local last_ts = 0
for l in io.lines(CHAT) do
    l = string.gsub(l, "'", " ")
    local y,m,d,hh,mm,ss,user,msg = string.match(l,
        "(%d%d%d%d)(%d%d)(%d%d) %[(%d%d):(%d%d):(%d%d)%] %<([%a%d-_]+)%>\t(.*)")
    if y then
        local ts = os.time({ year=y, month=m, day=d, hour=hh, min=mm, sec=ss })
        -- `too old` refuses < NOW(backs)-1h: raise stragglers to the
        -- running clock and count them (the log has a misfiled day)
        if ts < last_ts then
            ts = last_ts
            clamped = clamped + 1
        end
        last_ts = ts
        local t0 = now()
        local hash = exec(FC .. " --now=" .. ts .. " chain '" .. ALIAS .. "' post --sign=" .. key(user) .. " inline -- '" .. msg .. "'")
        tpost = tpost + (now() - t0)
        assert(string.match(hash, '^%x+$'), user .. ' : ' .. hash)
        N = N + 1
        print(N, ts, user, hash)

        if N % WINDOW == 0 then
            print(string.format("== N=%d  post avg=%.3fs  clamped=%d", N, tpost/WINDOW, clamped))
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
end
