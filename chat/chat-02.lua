#!/usr/bin/env lua5.4

-- Port of tpd-21/chat/chat-02.lua to freechains.vcs (single root).
-- SINGLE INSTANCE: the shared root is wiped on start, so two
-- concurrent runs corrupt each other.

function exec (cmd)
    local f = io.popen(cmd .. " 2>&1")
    local v = f:read('*a')
    f:close()
    return (string.gsub(v, "%s+$", ""))
end

-- absolute paths: git '-C <repo>' chdirs first, so a relative --sign breaks
local BASE = exec("realpath -m ../.freechains")
local ROOT = BASE .. '/root'
local KEYS = BASE .. '/keys'

-- chain disk: repos are BARE (the chain dir IS the git dir) and
-- state lives in git blobs (refs/states/*). Measure the whole dir
-- and split packed vs loose. count-objects -v reports KiB.
-- (the '#chat'/ trailing slash follows the alias symlink)
function disk ()
    local dir   = ROOT .. "/chains/'#chat'/"
    local total = tonumber(exec("du -sb " .. dir .. " 2>/dev/null | cut -f1")) or 0
    local co    = exec("git -C " .. dir .. " count-objects -v 2>/dev/null")
    local loose = (tonumber(co:match("size: (%d+)"))      or 0) * 1024
    local pack  = (tonumber(co:match("size%-pack: (%d+)")) or 0) * 1024
    return total, pack, loose
end

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)

local USERS = {}

function keys (user)
    if not USERS[user] then
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. KEYS .. "/" .. user .. " -q")
        USERS[user] = {
            user    = user,
            pub     = exec("cat " .. KEYS .. "/" .. user .. ".pub"),
            n       = 0,
            likes   = 0,
            new     = 0,
            extra   = 0,
            blocked = 0,
        }
    end
    return USERS[user]
end

-- the pioneer creates the chain and thus holds the initial reps
keys('Ashlee')
--print(exec("freechains --root=" .. ROOT .. " --now=0 chains add '#chat' init --pioneer=" .. KEYS .. "/Ashlee"))
print(exec("freechains --root=" .. ROOT .. " --now=0 chains add '#chat' init"))

-- wall clock in seconds (os.clock ignores child processes)
function now ()
    return tonumber(exec("date +%s.%N"))
end

-- full dump: per-user table, totals, disk (every 5k msgs and at end)
function report (N)
    local T = {}
    local ns, nlikes, nnew, nextra, nblocked = 0, 0, 0, 0, 0
    for _,t in pairs(USERS) do
        T[#T+1] = t
    end
    table.sort(T, function (t1,t2) return t1.likes > t2.likes end)
    for _,t in ipairs(T) do
        ns       = ns + t.n
        nlikes   = nlikes + t.likes
        nnew     = nnew + t.new
        nextra   = nextra + t.extra
        nblocked = nblocked + t.blocked
        print(string.format("%12s", string.sub(t.user,1,12)), t.likes, t.n)
    end

    -- (c) new-user unblocks, (d) extra likes to unblock existing users
    print(#T, 'users', '|', 'likes', nlikes, '|', 'msgs', ns)
    print('(c) new  ', nnew, nnew/ns, 'pct')
    print('(d) extra', nextra, nextra/ns, 'pct')
    print('blocked  ', nblocked, nblocked/ns, 'pct')

    local g, pack, loose = disk()
    print(string.format("== N=%d  git=%.1f MB  (pack %.1f, loose %.1f)",
        N, g/1e6, pack/1e6, loose/1e6))
end

local N = 0
local tpost, npost = 0, 0     -- accumulated post time in the window
for l in io.lines('../data/wikimedia.chat') do
    l = string.gsub(l, "'", " ")
    local y,m,d,hh,mm,ss,user,msg = string.match(l, "(%d%d%d%d)(%d%d)(%d%d) %[(%d%d):(%d%d):(%d%d)%] %<([%a%d-_]+)%>\t(.*)")
    if y then
        local ts = os.time({ year=y, month=m, day=d, hour=hh, min=mm, sec=ss })
        local t  = keys(user)
        t.n = t.n + 1

        -- query reps at the same virtual time as the post
        -- raw units: a signed post needs `cost` (500); below that,
        -- `--beg` is the only path (and is refused at >= 500)
        local reps = tonumber(exec("freechains --root=" .. ROOT .. " --now=" .. ts .. " chain '#chat' reps author \"" .. t.pub .. "\""))
        --local beg  = (reps < 500) and ' --beg' or ''
        local beg  = ''

        -- '--' ends option parsing so a message starting with '-' is text
        local t0 = now()
        local hash = exec("freechains --root=" .. ROOT .. " --now=" .. ts .. " chain '#chat' post --sign=" .. KEYS .. "/" .. user .. beg .. " inline -- '" .. msg .. "'")
        tpost = tpost + (now() - t0)
        npost = npost + 1
        assert(string.match(hash, '^%x+$'), user .. ' : ' .. hash)

        -- welcoming like from the pioneer unblocks a begging post
        -- (a beg like must carry at least `cost`: 1000 admits the
        -- post and leaves its author 450, the old `like 1`)
        if beg ~= '' then
            local v = exec("freechains --root=" .. ROOT .. " --now=" .. ts .. " chain '#chat' like 1000 action " .. hash .. " --sign=" .. KEYS .. "/Ashlee")
            if string.match(v, '^%x+$') then
                -- (c) first like bootstraps a new user; (d) later ones are extra
                if t.likes == 0 then
                    t.new = 1
                else
                    t.extra = t.extra + 1
                end
                t.likes = t.likes + 1
            else
                -- the pioneer's budget is finite: an unaffordable
                -- welcome leaves the beg parked (message undelivered)
                assert(string.find(v, 'insufficient reputation', 1, true), user .. ' : like : ' .. v)
                t.blocked = t.blocked + 1
            end
        end

        print(N, ts, user, reps, hash)
    end
    N = N + 1
    if N % 5000 == 0 then
        print(string.format("== N=%d  post avg=%.2fs (%d posts)",
            N, tpost/npost, npost))
        tpost, npost = 0, 0
        report(N)
        -- sweep: pack states, reap unanchored; disk before/after
        local t0 = now()
        local out = exec("freechains --root=" .. ROOT .. " chain '#chat' sweep")
        local g, pack, loose = disk()
        print(string.format("== N=%d  sweep=%.1fs  git=%.1f MB  (pack %.1f, loose %.1f)  [%s]",
            N, now()-t0, g/1e6, pack/1e6, loose/1e6, out))
    end
end

report(N)
