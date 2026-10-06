#!/usr/bin/env lua5.4

-- P2P replay on hubs-59 (see `hubs50.dia`).
-- 5 supers, fully connected.
-- 9 mids M01..M09, each on its 2 nearest supers.
-- Mi carries i leaves, 45 leaves in all.
-- Edge leaves also link to the neighbouring mid.
-- Sibling links in fans of 4+ leaves.
-- Sync rule: push with a relay delay (26/10/06).
-- A peer that gets something new arms a timer of U(0, T.relay)
-- chain secs (keep: a pending timer is not restarted).
-- When it fires, every neighbour lacking something pulls from it.
-- T.relay = 0: instantaneous (chat).
-- Fork: the author lacks an earlier action when it posts.
-- Work runs in waves of LANES tasks, all in parallel.
-- In a wave, writers are distinct, and no writer is a source.
-- Holders per action are tracked here (no git checks).
-- After the last action, the pending timers drain.
-- MODE=simple: artificial inline posts (the only mode so far).
-- SINGLE RUN: G.BASE is wiped on start.
-- Settings: edit config.lua (table G, no env).

-------------------------------------------------------------------------------
-- config

local DIR = arg[0]:match("^(.*)/") or "."
local G = dofile(DIR .. "/config.lua")

math.randomseed(G.SEED)

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
-- peer ids: S01-S05 = 0-4, M01-M09 = 5-13, leaves L14-L58 = 14-58

local TOPO = dofile(DIR .. "/topo.lua")


local NS, NM, NL = TOPO._ns, TOPO._nm, TOPO._nl
local SUP, MID, LEAF = {}, {}, {}   -- peer ids, by tier
local NAME, TIER, HOME = {}, {}, {} -- HOME: leaf -> mid index (0-based)
local EDGES, ADJ, MIDS = {}, {}, {} -- MIDS: leaf -> mid ids, own first
local CROSS = {}

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

local N = NS + NM + NL
for p = 0, N-1 do
    ADJ[p] = {}
    if p < NS then
        SUP[#SUP+1] = p; NAME[p] = string.format('S%02d', p + 1); TIER[p] = 'S'
    elseif p < NS + NM then
        MID[#MID+1] = p; NAME[p] = string.format('M%02d', p - NS + 1); TIER[p] = 'M'
    else
        LEAF[#LEAF+1] = p; NAME[p] = 'L' .. p; TIER[p] = 'L'
    end
end
local ID = {}
for p = 0, N-1 do ID[NAME[p]] = p end

for p = 0, N-1 do
    assert(TOPO[NAME[p]], "topo: missing " .. NAME[p])
    for _, x in ipairs(TOPO[NAME[p]]) do
        local q = ID[x]
        local kind = TIER[p] .. TIER[q]
        if kind == 'MS' then
            kind = 'SM'
        elseif kind == 'LM' then
            if MIDS[p] then              -- second mid: neighbouring
                kind = 'LX'
                table.insert(MIDS[p], q)
                CROSS[#CROSS+1] = { p, x }
            else                         -- first mid: own
                HOME[p], MIDS[p] = q - NS, { q }
            end
        end
        link(p, q, kind)
    end
end

if G.DUMP then
    for _, e in ipairs(EDGES) do
        print(e[3], NAME[e[1]], NAME[e[2]])
    end
    os.exit(0)
end

-------------------------------------------------------------------------------
-- peers on disk

G.BASE = exec("realpath -m " .. G.BASE)
local KEYS  = G.BASE .. '/keys'
local CHAIN = string.sub(G.ALIAS, 2)

--[[
-- Root dir of a peer.
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [string]: absolute root dir
-- Callers:
--  - dir, main chunk [p2p.lua]
--]]
local function root (p)
    return string.format("%s/p%02d", G.BASE, p)
end

--[[
-- Chain dir (bare git repo) of a peer.
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [string]: absolute chain dir, with a trailing slash
-- Callers:
--  - heads, main chunk [p2p.lua]
--]]
local function dir (p)
    return root(p) .. '/chains/' .. CHAIN .. '/'
end

--[[
-- HEADs of all peers.
-- Inputs:
--  - none
-- Outputs:
--  - [boolean]: true when all HEADs are equal
--  - [integer]: number of distinct HEADs
-- Callers:
--  - setup, main chunk [p2p.lua]
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
-- Shell lines for one wave: one task per lane, all in parallel.
-- `pull` records the sync kind (ff: receiver HEAD is an ancestor
-- of the source HEAD, else mg) and the sync time.
-- `post` records the post time and the new hash.
-- Inputs:
--  - tasks [table]: { {'pull', to, from, ts} | {'post', leaf, ts,
--    key, msg}, ... }, at most LANES
-- Outputs:
--  - [string]: the bash script
-- Callers:
--  - wave [p2p.lua]
--]]
local function script (tasks)
    local C = "/chains/" .. CHAIN .. "/"
    local sh = { "set +e", "B=" .. G.BASE,
        -- pull <lane> <to> <from> <ts>
        "pull () {",
        "  local T=$(printf \"$B/p%02d\" $2) F=$(printf \"$B/p%02d\" $3)",
        "  local ht=$(git -C $T" .. C .. " rev-parse HEAD) hf=$(git -C $F" .. C .. " rev-parse HEAD)",
        "  local k=mg",
        "  git -C $F" .. C .. " merge-base --is-ancestor $ht $hf 2>/dev/null && k=ff",
        "  local t0=$(date +%s%N)",
        "  out=$(freechains --root=$T --now=$4 chain " .. G.ALIAS ..
            " sync recv $F" .. C .. " 2>&1); rc=$?",
        "  local t1=$(date +%s%N)",
        "  echo \"pull $2 $3 $rc $k $((t1-t0)) $(echo \"$out\" | grep -m1 ERROR | tr ' ' _)\" > $B/status.$1",
        "}",
        -- post <lane> <leaf> <ts> <key> <msg>
        "post () {",
        "  local T=$(printf \"$B/p%02d\" $2)",
        "  local t0=$(date +%s%N)",
        "  out=$(freechains --root=$T --now=$3 chain " .. G.ALIAS ..
            " post --sign=$4 inline \"$5\" 2>&1); rc=$?",
        "  local t1=$(date +%s%N)",
        "  echo \"post $2 0 $rc po $((t1-t0)) $(echo \"$out\" | head -1 | tr ' ' _)\" > $B/status.$1",
        "}",
        "rm -f $B/status.*" }
    for i, t in ipairs(tasks) do
        if t[1] == 'pull' then
            sh[#sh+1] = string.format("pull %d %d %d %d &", i, t[2], t[3], t[4])
        else
            sh[#sh+1] = string.format("post %d %d %d %s '%s' &", i, t[2], t[3], t[4], t[5])
        end
    end
    sh[#sh+1] = "wait"
    return table.concat(sh, "\n") .. "\n"
end

-------------------------------------------------------------------------------
-- holders: which peers hold each action not yet everywhere
-- A pull copies all of the source's actions to the receiver.
-- An action held by all N peers is retired.

local HOLD, CNT, ACTIVE = {}, {}, {}

--[[
-- Is a pull useful: the source holds an action the receiver lacks?
-- Inputs:
--  - to, from [integer]: receiver, source
-- Outputs:
--  - [boolean]
-- Callers:
--  - play [p2p.lua]
--]]
local function useful (to, from)
    for a in pairs(ACTIVE) do
        if HOLD[a][from] and not HOLD[a][to] then
            return true
        end
    end
    return false
end

local STATS = { pulls=0, idle=0, waves=0, wall=0, forks=0, noop=0 }
local POST, FF, MG = {}, {}, {}     -- times (s), in order

--[[
-- Run one wave: the tasks, one per lane, in parallel.
-- Then updates the holders.
-- Inputs:
--  - tasks [table]: at most LANES tasks
--  - ts    [integer]: virtual time of the wave
--  - act   [integer]: id of a posted action (nil if no post)
-- Outputs:
--  - [integer]: tasks run
-- Errors:
--  - "wave : missing status (<n>/<m>)": a task left no status
--  - "wave : pull <to> <- <from> : rc=<rc> <err>": a pull failed
--  - "wave : post <leaf> : rc=<rc> <out>": a post failed
-- Callers:
--  - play [p2p.lua]
--]]
local function wave (tasks, ts, act)
    -- gains from the holders at wave start (sources are not written)
    local gain = {}
    for i, t in ipairs(tasks) do
        if t[1] == 'pull' then
            local g = {}
            for a in pairs(ACTIVE) do
                if HOLD[a][t[3]] and not HOLD[a][t[2]] then g[#g+1] = a end
            end
            gain[i] = g
        end
    end
    local f = io.open(G.BASE .. '/wave.sh', 'w')
    f:write(script(tasks))
    f:close()
    local t0 = now()
    os.execute("bash " .. G.BASE .. "/wave.sh")
    STATS.wall  = STATS.wall + (now() - t0)
    STATS.waves = STATS.waves + 1
    STATS.idle  = STATS.idle + (G.LANES - #tasks)
    for i = 1, #tasks do
        local fh = io.open(G.BASE .. '/status.' .. i)
        assert(fh, "wave : missing status (" .. (i-1) .. "/" .. #tasks .. ")")
        local l = fh:read('l')
        fh:close()
        local kind, to, from, rc, k, ns, rest =
            l:match("^(%a+) (%d+) (%d+) (%d+) (%a+) (%d+) ?(.*)$")
        to, from = tonumber(to), tonumber(from)
        if kind == 'post' then
            if rc ~= '0' or not rest:match('^%x+$') then
                error(string.format("wave : post %s : rc=%s %s", NAME[to], rc, rest))
            end
            POST[#POST+1] = tonumber(ns) / 1e9
            HOLD[act], CNT[act], ACTIVE[act] = { [to] = true }, 1, true
        else
            if rc ~= '0' then
                error(string.format("wave : pull %s <- %s : rc=%s %s",
                    NAME[to], NAME[from], rc, rest))
            end
            STATS.pulls = STATS.pulls + 1
            local list = (k == 'ff') and FF or MG
            list[#list+1] = tonumber(ns) / 1e9
            for _, a in ipairs(gain[i]) do
                if not HOLD[a][to] then
                    HOLD[a][to], CNT[a] = true, CNT[a] + 1
                end
            end
        end
    end
    for a in pairs(ACTIVE) do
        if CNT[a] == N then
            ACTIVE[a], HOLD[a] = nil, nil
        end
    end
    return #tasks
end

--[[
-- Min/avg/max of a slice of a list of times.
-- Inputs:
--  - xs [table]: times (s)
--  - i0 [integer]: first index of the slice
-- Outputs:
--  - [integer]: count
--  - [string]: "min/avg/max" or "-.--/-.--/-.--"
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function mma (xs, i0)
    local n, s, lo, hi = 0, 0, math.huge, 0
    for i = i0, #xs do
        local x = xs[i]
        n, s = n + 1, s + x
        if x < lo then lo = x end
        if x > hi then hi = x end
    end
    if n == 0 then
        return 0, "-.--/-.--/-.--"
    end
    return n, string.format("%.2f/%.2f/%.2f", lo, s/n, hi)
end

-------------------------------------------------------------------------------
-- setup: S01 inits, the others clone from an already created
-- neighbour (BFS order, one BFS layer per parallel step)

os.execute("rm -rf " .. G.BASE)
os.execute("mkdir -p " .. KEYS)
exec("freechains --root=" .. root(0) .. " --now=" .. G.T0 ..
    " chains add '" .. G.ALIAS .. "' init")
local made, layer = { [0] = true }, { 0 }
while #layer > 0 do
    local sh, next = {}, {}
    for _, p in ipairs(layer) do
        for _, q in ipairs(ADJ[p]) do
            if not made[q] then
                made[q] = true
                next[#next+1] = q
                sh[#sh+1] = "freechains --root=" .. root(q) ..
                    " chains add '" .. G.ALIAS .. "' clone " .. dir(p) ..
                    " > /dev/null 2>&1 &"
            end
        end
    end
    if #sh > 0 then
        local f = io.open(G.BASE .. '/clone.sh', 'w')
        f:write(table.concat(sh, "\n") .. "\nwait\n")
        f:close()
        os.execute("bash " .. G.BASE .. "/clone.sh")
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
-- simple test: N_ACT artificial posts, each followed by waves

assert(G.MODE == 'simple', "mode " .. G.MODE .. " : not yet")

local HEAP, TIMER = {}, {}          -- pending fires; peer -> fire time

--[[
-- Push a fire onto the heap (min by time, then by insertion).
-- Inputs:
--  - t [number]: chain time of the fire
--  - p [integer]: peer
-- Outputs:
--  - none
-- Callers:
--  - arm [p2p.lua]
--]]
local SEQ = 0
local function hpush (t, p)
    SEQ = SEQ + 1
    local e, i = { t, SEQ, p }, #HEAP + 1
    HEAP[i] = e
    while i > 1 do
        local j = i // 2
        local a, b = HEAP[j], HEAP[i]
        if a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) then break end
        HEAP[i], HEAP[j] = a, b
        i = j
    end
end

--[[
-- Pop the earliest fire.
-- Inputs:
--  - none
-- Outputs:
--  - [table]: { t, seq, p }
-- Callers:
--  - advance [p2p.lua]
--]]
local function hpop ()
    local top, last = HEAP[1], table.remove(HEAP)
    if #HEAP > 0 then
        HEAP[1] = last
        local i = 1
        while true do
            local l, r, m = 2*i, 2*i + 1, i
            local lt = function (x, y)
                return HEAP[x][1] < HEAP[y][1] or
                    (HEAP[x][1] == HEAP[y][1] and HEAP[x][2] < HEAP[y][2])
            end
            if l <= #HEAP and lt(l, m) then m = l end
            if r <= #HEAP and lt(r, m) then m = r end
            if m == i then break end
            HEAP[i], HEAP[m] = HEAP[m], HEAP[i]
            i = m
        end
    end
    return top
end

--[[
-- Arm the relay timer of a peer that got something new.
-- Keep: a pending timer is not restarted.
-- Inputs:
--  - p [integer]: peer
--  - t [number]: chain time of the gain
-- Outputs:
--  - none
-- Callers:
--  - main chunk, fire [p2p.lua]
--]]
local function arm (p, t)
    if TIMER[p] then
        return
    end
    TIMER[p] = t + math.random() * G.T.relay
    hpush(TIMER[p], p)
end

--[[
-- Fire a peer's timer: every neighbour lacking something pulls
-- from it, in waves of LANES (receivers distinct, source read).
-- Each receiver gained, so it arms its own timer.
-- Inputs:
--  - p [integer]: peer
--  - t [number]: chain time of the fire
-- Outputs:
--  - [integer]: waves run
-- Callers:
--  - advance [p2p.lua]
--]]
local function fire (p, t)
    TIMER[p] = nil
    local qs = {}
    for _, q in ipairs(ADJ[p]) do
        if useful(q, p) then qs[#qs+1] = q end
    end
    local waves = 0
    for i = 1, #qs, G.LANES do
        local tasks = {}
        for j = i, math.min(i + G.LANES - 1, #qs) do
            tasks[#tasks+1] = { 'pull', qs[j], p, math.floor(t) }
        end
        wave(tasks, math.floor(t), nil)
        waves = waves + 1
    end
    for _, q in ipairs(qs) do arm(q, t) end
    return waves
end

--[[
-- Run every fire due up to a chain time, in order.
-- Inputs:
--  - upto [number]: chain time (math.huge: drain)
-- Outputs:
--  - [integer]: waves run
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function advance (upto)
    local waves = 0
    while #HEAP > 0 and HEAP[1][1] <= upto do
        local e = hpop()
        if TIMER[e[3]] == e[1] then
            waves = waves + fire(e[3], e[1])
        end
    end
    return waves
end

--[[
-- How many earlier actions a peer lacks (> 0: its post forks).
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [integer]: active actions not held by `p`
-- Callers:
--  - main chunk [p2p.lua]: before each post
--]]
local function lacks (p)
    local n = 0
    for a in pairs(ACTIVE) do
        if not HOLD[a][p] then n = n + 1 end
    end
    return n
end

local R, AUTH = {}, {}
local t0 = now()
for a = 1, G.N_ACT do
    local ts = G.T0 + a*G.T.action
    local ta, pa = now(), STATS.pulls
    local jf, jm = #FF + 1, #MG + 1
    -- the pushes due before this action
    local w = advance(ts)
    -- the post: fork if the author lacks earlier actions
    local l = LEAF[math.random(#LEAF)]
    AUTH[l] = true
    local miss = lacks(l)
    if miss > 0 then STATS.forks = STATS.forks + 1 end
    wave({ { 'post', l, ts, KEYS .. "/" .. NAME[l],
        'simple ' .. a .. ' by ' .. NAME[l] } }, ts, a)
    arm(l, ts)
    R[#R+1] = w
    local nf, sf = mma(FF, jf)
    local nm, sm = mma(MG, jm)
    print(string.format(". %5d %3ds  %s  [%03d]  miss=%d  post=%.2f  pulls=%02d  ff[%02d]=%s  mg[%02d]=%s",
        a, math.floor(now() - ta), NAME[l], w, miss, POST[#POST],
        STATS.pulls - pa, nf, sf, nm, sm))
    if a % 10 == 0 then
        local _,  sp = mma(POST, 1)
        local nf, sf = mma(FF, 1)
        local nm, sm = mma(MG, 1)
        print()
        print(string.format("== %d %4ds  forks=%d (%d%%)  post=%s  pulls=%d  ff[%4d]=%s  mg[%4d]=%s  idle=%d",
            a, math.floor(now() - t0), STATS.forks, 100*STATS.forks//a,
            sp, STATS.pulls, nf, sf, nm, sm, STATS.idle))
        print()
    end
end

-- final drain: the pending timers, until none is left
local dw = advance(math.huge)
assert(next(ACTIVE) == nil, "drain : actions not everywhere")
print(string.format("== END drain waves=%d", dw))
local merges = tonumber(exec("git -C " .. dir(0) .. " rev-list --merges --count HEAD"))
print(string.format("== END forks=%d of %d actions (%d%%)  merges in DAG=%d",
    STATS.forks, G.N_ACT, 100*STATS.forks//G.N_ACT, merges))

-------------------------------------------------------------------------------
-- check: one `list order`, one `reps` per author, on every peer

local function same (cmd)
    local ref, bad = nil, 0
    for p = 0, N-1 do
        local out = exec("freechains --root=" .. root(p) .. " chain '" ..
            G.ALIAS .. "' " .. cmd)
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
print(string.format("== END actions=%d  waves per action median=%d max=%d  pulls=%d  waves=%d wave-wall=%.0fs  idle=%d  elapsed=%.0fs",
    G.N_ACT, R[(#R+1)//2], R[#R], STATS.pulls,
    STATS.waves, STATS.wall, STATS.idle, now() - t0))
print(string.format("== END order: %d actions, %d of %d peers differ | reps: %d mismatches over %d authors",
    norder, bad_o, N - 1, bad_r, (function () local n = 0 for _ in pairs(AUTH) do n = n + 1 end return n end)()))
print((bad_o == 0 and bad_r == 0 and norder == G.N_ACT) and "== PASS" or "== FAIL")
