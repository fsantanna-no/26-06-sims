#!/usr/bin/env lua5.4

-- P2P replay on hubs-59 (see `hubs50.dia`): 5 supers (fully
-- connected), 9 mids M1..M9 (each on its 2 nearest supers; Mi
-- carries i leaves), 45 leaves; edge leaves also on the
-- neighbouring mid; sibling links in fans of 4+ leaves.
-- Loop per action:
--  1. a leaf acts; its mid pulls it
--  2. leaves pull from their mid(s) + random super pairs +
--     random sibling pairs
--  3. random mid/super pairs (matching on M-S and S-S links)
--  repeat 2-3 until every HEAD agrees (or RMAX rounds)
-- Each step runs in LANES parallel lanes, one job per written
-- peer (one writer per peer; sources are only read by `git
-- fetch`). A pull is skipped when the receiver already has the
-- source's HEAD.
-- MODE=simple: artificial inline posts (the only mode so far).
-- SINGLE RUN: BASE is wiped on start.

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

local MODE  = env('MODE',  'simple')
local N_ACT = env('N_ACT', 10)          -- simple: number of actions
local GAP   = env('GAP',   3600)        -- simple: chain secs between actions
local D     = env('D',     60)          -- chain secs per round
local RMAX  = env('RMAX',  40)          -- max rounds per action
local LANES = env('LANES', 6)
local SEED  = env('SEED',  1)
local DUMP  = env('DUMP',  false)       -- print the edges and exit
local ALIAS = env('ALIAS', '/simple')
local BASE  = env('BASE',  './.freechains-p2p-' .. MODE)
local T0    = env('T0',    1700000000)

math.randomseed(SEED)

-------------------------------------------------------------------------------
-- helpers (as lemmy-p2p)

function exec (cmd)
    local f = io.popen(cmd .. " 2>&1")
    local v = f:read('*a')
    f:close()
    return (string.gsub(v, "%s+$", ""))
end

function now ()
    return tonumber(exec("date +%s.%N"))
end

-------------------------------------------------------------------------------
-- topology: hubs-59 (fixed, as drawn in hubs50.dia)

local NS, NM = 5, 9
local SUP, MID, LEAF = {}, {}, {}   -- peer ids (0-based)
local NAME, TIER = {}, {}
local EDGES = {}                    -- {a, b, kind}
local ADJ = {}

--[[
-- Record an undirected link.
-- Inputs:
--  - a, b [integer]: peer ids
--  - kind [string]: SS | SM | LM | LX (leaf to neighbour mid) | LL
-- Outputs:
--  - none
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function link (a, b, kind)
    EDGES[#EDGES+1] = { a, b, kind }
    ADJ[a][#ADJ[a]+1] = b
    ADJ[b][#ADJ[b]+1] = a
end

local N = 0
for i = 0, NS-1 do
    SUP[#SUP+1] = N; NAME[N] = 'S' .. i; TIER[N] = 'S'; N = N + 1
end
for m = 0, NM-1 do
    MID[#MID+1] = N; NAME[N] = 'M' .. (m+1); TIER[N] = 'M'; N = N + 1
end
for p = 0, N-1 do ADJ[p] = {} end

-- supers: fully connected
for i = 1, NS do
    for j = i+1, NS do link(SUP[i], SUP[j], 'SS') end
end

-- mids: evenly spaced (40 deg) clockwise from 70 deg, interleaved
-- M1 M6 M2 M7 M3 M8 M4 M9 M5; each on its 2 bracketing supers
local SLOTS = { 0, 5, 1, 6, 2, 7, 3, 8, 4 }
local ANG = {}
for k, m in ipairs(SLOTS) do
    ANG[m] = 70 - 40*(k-1)
end
for m = 0, NM-1 do
    local t = (90 - ANG[m]) % 360           -- clockwise from S0
    local i = math.floor(t / 72)
    link(MID[m+1], SUP[i % 5 + 1], 'SM')
    link(MID[m+1], SUP[(i+1) % 5 + 1], 'SM')
end

-- leaves: Mi carries i leaves (ids after the mids)
local FAN, HOME, ANGL = {}, {}, {}
for m = 0, NM-1 do
    FAN[m] = {}
    local n = m + 1
    for j = 0, n-1 do
        local l = N
        NAME[l] = 'L' .. l; TIER[l] = 'L'; ADJ[l] = {}
        LEAF[#LEAF+1] = l; FAN[m][#FAN[m]+1] = l; HOME[l] = m
        ANGL[l] = ANG[m] + (j - (n-1)/2) * 4.3
        link(l, MID[m+1], 'LM')
        N = N + 1
    end
end

-- edge leaves also on the neighbouring mid (angular neighbours)
local ORDER = {}
for m = 0, NM-1 do ORDER[#ORDER+1] = m end
table.sort(ORDER, function (a, b) return ANG[a] % 360 < ANG[b] % 360 end)
local CROSS = {}
for i, m in ipairs(ORDER) do
    for _, nb in ipairs{ ORDER[(i-2) % NM + 1], ORDER[i % NM + 1] } do
        local best, bd
        for _, l in ipairs(FAN[m]) do
            local d = math.abs(((ANGL[l] - ANG[nb] + 180) % 360) - 180)
            if not bd or d < bd then best, bd = l, d end
        end
        local dup = false
        for _, c in ipairs(CROSS) do
            if (c[1] == best and c[2] == nb) or (#FAN[m] == 1 and c[1] == best) then
                dup = true
            end
        end
        if not dup then
            CROSS[#CROSS+1] = { best, nb }
            link(best, MID[nb+1], 'LX')
        end
    end
end

-- sibling links: fans of n >= 4 leaves get k adjacent pairs
local KSIB = { [4]=2, [5]=2, [6]=3, [7]=3, [8]=4, [9]=4 }
for m = 0, NM-1 do
    for i = 0, (KSIB[m+1] or 0) - 1 do
        link(FAN[m][2*i+1], FAN[m][2*i+2], 'LL')
    end
end

-- mids of each leaf (own first, then the neighbouring one)
local MIDS = {}
for _, l in ipairs(LEAF) do MIDS[l] = { MID[HOME[l]+1] } end
for _, c in ipairs(CROSS) do
    table.insert(MIDS[c[1]], MID[c[2]+1])
end

if DUMP then
    for _, e in ipairs(EDGES) do
        print(e[3], NAME[e[1]], NAME[e[2]])
    end
    os.exit(0)
end

-------------------------------------------------------------------------------
-- peers on disk

BASE = exec("realpath -m " .. BASE)
local KEYS  = BASE .. '/keys'
local CHAIN = string.sub(ALIAS, 2)

--[[
-- Root dir of a peer.
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [string]: absolute root dir
-- Callers:
--  - dir, fc, main chunk [p2p.lua]
--]]
local function root (p)
    return string.format("%s/p%02d", BASE, p)
end

--[[
-- Chain dir (bare git repo) of a peer.
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [string]: absolute chain dir, with a trailing slash
-- Callers:
--  - pull, heads, main chunk [p2p.lua]
--]]
local function dir (p)
    return root(p) .. '/chains/' .. CHAIN .. '/'
end

--[[
-- Shell line for one pull, with the skip check and a status line.
-- Inputs:
--  - to   [integer]: receiver (written)
--  - from [integer]: source (only read)
--  - ts   [integer]: virtual time
-- Outputs:
--  - [string]: `pull <to> <from> <ts>` (shell function, see run)
-- Callers:
--  - step2, step3 [p2p.lua]
--]]
local function pull (to, from, ts)
    return string.format("pull %d %d %d", to, from, ts)
end

local STATS = { pulls=0, skips=0, fails=0, steps=0, wall=0 }
local FAILS = {}

--[[
-- Run one step: jobs (lists of pull lines, one job per written
-- peer or pair) spread over LANES lanes, longest first to the
-- least loaded lane; waits for all; tallies the status lines.
-- Inputs:
--  - jobs [table]: { {line, ...}, ... }
--  - tag  [string]: step name, for the logs
-- Outputs:
--  - none (updates STATS, FAILS)
-- Errors:
--  - "step <tag> : missing status": a pull left no status line
-- Callers:
--  - action, round [p2p.lua]
--]]
local function run (jobs, tag)
    if #jobs == 0 then
        return
    end
    table.sort(jobs, function (a, b) return #a > #b end)
    local lanes, load = {}, {}
    for i = 1, LANES do lanes[i], load[i] = {}, 0 end
    for _, job in ipairs(jobs) do
        local best = 1
        for i = 2, LANES do
            if load[i] < load[best] then best = i end
        end
        for _, l in ipairs(job) do table.insert(lanes[best], l) end
        load[best] = load[best] + #job
    end
    local st = BASE .. '/status'
    local sh = { "set +e",
        -- pull <to> <from> <ts>: skip if <to> has <from>'s HEAD
        "pull () {",
        "  local T=$(printf '" .. BASE .. "/p%02d' $1) F=$(printf '" .. BASE .. "/p%02d' $2)",
        "  local h=$(git -C $F/chains/" .. CHAIN .. "/ rev-parse HEAD)",
        "  if git -C $T/chains/" .. CHAIN .. "/ cat-file -e $h^{commit} 2>/dev/null; then",
        "    echo \"skip $1 $2 0\" >> " .. st .. ".$LANE",
        "  else",
        "    out=$(freechains --root=$T --now=$3 chain " .. ALIAS ..
            " sync recv $F/chains/" .. CHAIN .. "/ 2>&1); rc=$?",
        "    echo \"pull $1 $2 $rc $(echo \"$out\" | grep -m1 ERROR | tr ' ' _)\" >> " .. st .. ".$LANE",
        "  fi",
        "}",
        "rm -f " .. st .. ".*" }
    local n = 0
    for i = 1, LANES do
        if #lanes[i] > 0 then
            sh[#sh+1] = "( LANE=" .. i .. " ; " .. table.concat(lanes[i], " ; ") .. " ) &"
            n = n + #lanes[i]
        end
    end
    sh[#sh+1] = "wait"
    local f = io.open(BASE .. '/step.sh', 'w')
    f:write(table.concat(sh, "\n") .. "\n")
    f:close()
    local t0 = now()
    os.execute("bash " .. BASE .. "/step.sh")
    STATS.wall  = STATS.wall + (now() - t0)
    STATS.steps = STATS.steps + 1
    local seen = 0
    for i = 1, LANES do
        local fh = io.open(st .. '.' .. i)
        if fh then
            for l in fh:lines() do
                seen = seen + 1
                local kind, to, from, rc, err = l:match("^(%a+) (%d+) (%d+) (%d+) ?(.*)$")
                if kind == 'skip' then
                    STATS.skips = STATS.skips + 1
                elseif rc == '0' then
                    STATS.pulls = STATS.pulls + 1
                else
                    STATS.fails = STATS.fails + 1
                    local k = (err ~= '' and err or ('rc=' .. rc))
                    FAILS[k] = (FAILS[k] or 0) + 1
                end
            end
            fh:close()
        end
    end
    assert(seen == n, "step " .. tag .. " : missing status (" .. seen .. "/" .. n .. ")")
end

--[[
-- HEADs of all peers.
-- Inputs:
--  - none
-- Outputs:
--  - [boolean]: true when all HEADs are equal
--  - [integer]: number of distinct HEADs
-- Callers:
--  - round loop, main chunk [p2p.lua]
--]]
local function heads ()
    local cmd = {}
    for p = 0, N-1 do
        cmd[#cmd+1] = "git -C " .. dir(p) .. " rev-parse HEAD"
    end
    local out = exec(table.concat(cmd, " ; "))
    local set, n = {}, 0
    for h in out:gmatch("%x+") do
        if not set[h] then set[h], n = true, n + 1 end
    end
    return n == 1, n
end

--[[
-- Random matching on a list of links (each peer at most once).
-- Inputs:
--  - links [table]: { {a, b}, ... }
-- Outputs:
--  - [table]: chosen pairs
-- Callers:
--  - step2, step3 [p2p.lua]
--]]
local function matching (links)
    local ls = {}
    for i, e in ipairs(links) do ls[i] = e end
    for i = #ls, 2, -1 do
        local j = math.random(i)
        ls[i], ls[j] = ls[j], ls[i]
    end
    local busy, out = {}, {}
    for _, e in ipairs(ls) do
        if not busy[e[1]] and not busy[e[2]] then
            busy[e[1]], busy[e[2]] = true, true
            out[#out+1] = e
        end
    end
    return out
end

local L_SS, L_LL, L_MS = {}, {}, {}
for _, e in ipairs(EDGES) do
    if e[3] == 'SS' then
        L_SS[#L_SS+1] = e
        L_MS[#L_MS+1] = e
    elseif e[3] == 'SM' then
        L_MS[#L_MS+1] = e
    elseif e[3] == 'LL' then
        L_LL[#L_LL+1] = e
    end
end

--[[
-- Step 2: leaves pull from their mid(s); random super pairs and
-- random sibling pairs exchange. A leaf in a sibling pair shares
-- one job with its partner (one writer per peer).
-- Inputs:
--  - ts [integer]: virtual time
-- Outputs:
--  - none
-- Callers:
--  - round loop [p2p.lua]
--]]
local function step2 (ts)
    local jobs, inpair = {}, {}
    for _, e in ipairs(matching(L_LL)) do
        local a, b = e[1], e[2]
        inpair[a], inpair[b] = true, true
        local job = {}
        for _, m in ipairs(MIDS[a]) do job[#job+1] = pull(a, m, ts) end
        for _, m in ipairs(MIDS[b]) do job[#job+1] = pull(b, m, ts) end
        job[#job+1] = pull(a, b, ts)
        job[#job+1] = pull(b, a, ts)
        jobs[#jobs+1] = job
    end
    for _, l in ipairs(LEAF) do
        if not inpair[l] then
            local job = {}
            for _, m in ipairs(MIDS[l]) do job[#job+1] = pull(l, m, ts) end
            jobs[#jobs+1] = job
        end
    end
    for _, e in ipairs(matching(L_SS)) do
        jobs[#jobs+1] = { pull(e[1], e[2], ts), pull(e[2], e[1], ts) }
    end
    run(jobs, '2')
end

--[[
-- Step 3: random mid/super pairs exchange (matching on M-S and
-- S-S links).
-- Inputs:
--  - ts [integer]: virtual time
-- Outputs:
--  - none
-- Callers:
--  - round loop [p2p.lua]
--]]
local function step3 (ts)
    local jobs = {}
    for _, e in ipairs(matching(L_MS)) do
        jobs[#jobs+1] = { pull(e[1], e[2], ts), pull(e[2], e[1], ts) }
    end
    run(jobs, '3')
end

--[[
-- Rounds of steps 2-3 until all HEADs agree, or RMAX rounds.
-- Inputs:
--  - ts [integer]: virtual time of the first round
-- Outputs:
--  - [integer]: rounds run
--  - [boolean]: converged
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function rounds (ts)
    for r = 1, RMAX do
        local t = ts + r*D
        step2(t)
        step3(t)
        if heads() then
            return r, true
        end
    end
    return RMAX, false
end

-------------------------------------------------------------------------------
-- setup: S0 inits, the others clone from an already created
-- neighbour (BFS order, one BFS layer per parallel step)

os.execute("rm -rf " .. BASE)
os.execute("mkdir -p " .. KEYS)
print(string.format("== hubs-59: peers=%d links=%d (SS %d, SM %d, LM %d, LX %d, LL %d) lanes=%d",
    N, #EDGES, #L_SS, #L_MS - #L_SS, #LEAF, #CROSS, #L_LL, LANES))

print(exec("freechains --root=" .. root(0) .. " --now=" .. T0 ..
    " chains add '" .. ALIAS .. "' init"))
local made, layer = { [0] = true }, { 0 }
while #layer > 0 do
    local sh, next = {}, {}
    for _, p in ipairs(layer) do
        for _, q in ipairs(ADJ[p]) do
            if not made[q] then
                made[q] = true
                next[#next+1] = q
                sh[#sh+1] = "freechains --root=" .. root(q) ..
                    " chains add '" .. ALIAS .. "' clone " .. dir(p) ..
                    " > /dev/null 2>&1 &"
            end
        end
    end
    if #sh > 0 then
        local f = io.open(BASE .. '/clone.sh', 'w')
        f:write(table.concat(sh, "\n") .. "\nwait\n")
        f:close()
        os.execute("bash " .. BASE .. "/clone.sh")
    end
    layer = next
end
local ok0, n0 = heads()
assert(ok0, "setup : clones disagree (" .. n0 .. " heads)")

-- one key per leaf (the authors)
for _, l in ipairs(LEAF) do
    os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. KEYS .. "/" .. NAME[l] .. " -q")
end

-------------------------------------------------------------------------------
-- simple test: N_ACT artificial posts, each followed by rounds

assert(MODE == 'simple', "mode " .. MODE .. " : not yet")

local R = {}
local AUTH = {}
local t0 = now()
for a = 1, N_ACT do
    local ts = T0 + a*GAP
    local l  = LEAF[math.random(#LEAF)]
    AUTH[l]  = true
    -- 1. the leaf acts; its own mid pulls it
    local h = exec("freechains --root=" .. root(l) .. " --now=" .. ts ..
        " chain '" .. ALIAS .. "' post --sign=" .. KEYS .. "/" .. NAME[l] ..
        " inline 'simple " .. a .. " by " .. NAME[l] .. "'")
    assert(h:match('^%x+$'), NAME[l] .. ' : post : ' .. h)
    run({ { pull(MID[HOME[l]+1], l, ts) } }, '1')
    -- 2-3 until converged
    local r, ok = rounds(ts)
    R[#R+1] = r
    print(string.format("== act %2d  %-4s -> %-3s  rounds=%2d %s  pulls=%d skips=%d fails=%d  elapsed=%.0fs",
        a, NAME[l], NAME[MID[HOME[l]+1]], r, ok and 'ok' or 'NOT CONVERGED',
        STATS.pulls, STATS.skips, STATS.fails, now() - t0))
end

-------------------------------------------------------------------------------
-- check: one `list order`, one `reps` per author, on every peer

local function same (cmd)
    local ref, bad = nil, 0
    for p = 0, N-1 do
        local out = exec("freechains --root=" .. root(p) .. " chain '" ..
            ALIAS .. "' " .. cmd)
        if ref == nil then
            ref = out
        elseif out ~= ref then
            bad = bad + 1
        end
    end
    return bad, ref
end

local bad_o, order = same("list order")
local norder = select(2, order:gsub("%x+", ""))
local bad_r = 0
for l in pairs(AUTH) do
    bad_r = bad_r + same("reps member " .. KEYS .. "/" .. NAME[l] .. ".pub")
end
table.sort(R)
local fs = {}
for k, v in pairs(FAILS) do fs[#fs+1] = k .. ' x' .. v end
print(string.format("== END actions=%d  rounds median=%d max=%d  pulls=%d skips=%d fails=%d  steps=%d step-wall=%.0fs  elapsed=%.0fs",
    N_ACT, R[(#R+1)//2], R[#R], STATS.pulls, STATS.skips, STATS.fails,
    STATS.steps, STATS.wall, now() - t0))
print(string.format("== END order: %d actions, %d of %d peers differ | reps: %d mismatches over %d authors",
    norder, bad_o, N - 1, bad_r, (function () local n = 0 for _ in pairs(AUTH) do n = n + 1 end return n end)()))
print("== END failures: " .. (#fs > 0 and table.concat(fs, ' | ') or 'none'))
print(bad_o == 0 and bad_r == 0 and "== PASS" or "== FAIL")
