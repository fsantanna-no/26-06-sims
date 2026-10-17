#!/usr/bin/env lua5.4

-- P2P replay on hubs-59, asymmetric (see `hubs50.dia`).
-- 5 supers S1-S5: ring + chords S1-S3, S1-S4.
-- 9 mids M1-M9: M1-M3 on 3 supers, M4-M6 on 2, M7-M9 on 1.
-- 45 leaves L01-L45: fans 15/8/6/5/4/3/2/1/1, one mid each.
-- Backup links (M ring, leaf second mid) wait for churn.
-- Local first (G.SYNC): a scheduled link (SM, LM) only carries
-- pulls at its sessions (period per kind, seeded phase per mid /
-- leaf); authors post on their leaf anytime.
-- Sync rule: push with a relay delay (26/10/06).
-- Chain time runs in ticks of T.tick: pulls due in one tick
-- share waves (event times shift < T.tick).
-- A peer that gets something new arms a timer of U(T.relay)
-- chain secs (keep: a pending timer is not restarted).
-- When it fires, every neighbour lacking something pulls from it.
-- T.relay = {min, max} secs; {0, 0}: instantaneous.
-- Fork: the author lacks an earlier action when it posts.
-- Work runs in waves of LANES tasks, all in parallel.
-- In a wave, writers are distinct, and no writer is a source.
-- Holders per action are tracked here (no git checks).
-- After the last action, the pending timers drain.
-- Every SWEEP actions, all peers sweep (pack loose objects).
-- MODE=simple: artificial inline posts.
-- MODE=corpus: the first LIMIT events of SRC.tsv (posts only).
-- SINGLE RUN: G.BASE is wiped on start (RESUME=1: restored
-- from the last checkpoint instead, see G.CKPT_N).
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
-- topology: hubs-59, asymmetric (fixed, as drawn in hubs50.dia)
-- peer ids: S1-S5 = 0-4, M1-M9 = 5-13, leaves L01-L45 = 14-58
-- primary links carry pushes; backup links (`_bk`) are kept
-- apart: used only while a primary uplink is down (churn)

local TOPO = dofile(DIR .. "/topo.lua")

local NS, NM, NL = TOPO._ns, TOPO._nm, TOPO._nl
local SUP, MID, LEAF = {}, {}, {}   -- peer ids, by tier
local NAME, TIER = {}, {}
local EDGES, ADJ, BKUP = {}, {}, {} -- BKUP: backup links
local KIND = {}                     -- KIND[a][b]: SS | SM | LM

--[[
-- Record an undirected primary link.
-- Inputs:
--  - a, b [integer]: peer ids
--  - kind [string]: SS | SM | LM
-- Outputs:
--  - none
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function link (a, b, kind)
    EDGES[#EDGES+1] = { a, b, kind }
    KIND[a] = KIND[a] or {}
    KIND[b] = KIND[b] or {}
    KIND[a][b], KIND[b][a] = kind, kind
    ADJ[a][#ADJ[a]+1] = b
    ADJ[b][#ADJ[b]+1] = a
end

local N = NS + NM + NL
for p = 0, N-1 do
    ADJ[p] = {}
    if p < NS then
        SUP[#SUP+1] = p; NAME[p] = 'S' .. (p + 1); TIER[p] = 'S'
    elseif p < NS + NM then
        MID[#MID+1] = p; NAME[p] = 'M' .. (p - NS + 1); TIER[p] = 'M'
    else
        LEAF[#LEAF+1] = p; NAME[p] = string.format('L%02d', p - NS - NM + 1); TIER[p] = 'L'
    end
end
local ID = {}
for p = 0, N-1 do ID[NAME[p]] = p end

for p = 0, N-1 do
    assert(TOPO[NAME[p]], "topo: missing " .. NAME[p])
    for _, x in ipairs(TOPO[NAME[p]]) do
        local q = assert(ID[x], "topo: unknown " .. x)
        local kind = TIER[p] .. TIER[q]
        if kind == 'MS' then
            kind = 'SM'
        end
        link(p, q, kind)
    end
    for _, x in ipairs((TOPO._bk or {})[NAME[p]] or {}) do
        local q = assert(ID[x], "topo: unknown " .. x)
        BKUP[#BKUP+1] = { p, q, (TIER[p] == 'L') and 'LX' or 'MM' }
    end
end

-- the primary mid of each leaf: its first mid link (PRESYNC)
local UP = {}
for _, l in ipairs(LEAF) do
    for _, q in ipairs(ADJ[l]) do
        if TIER[q] == 'M' then
            UP[l] = q
            break
        end
    end
end

-- MIX: class of each peer (on | ps | lf): a mid's from G.MIX,
-- a leaf's from its primary mid, supers always on
local CLASS = {}
if G.MIX then
    for p = 0, N-1 do
        if TIER[p] == 'S' then
            CLASS[p] = 'on'
        elseif TIER[p] == 'M' then
            CLASS[p] = assert(G.MIX[NAME[p]], "mix: missing " .. NAME[p])
        end
    end
    for _, l in ipairs(LEAF) do
        CLASS[l] = CLASS[UP[l]]
    end
end

if G.DUMP then
    for _, e in ipairs(EDGES) do
        print(e[3], NAME[e[1]], NAME[e[2]])
    end
    for _, e in ipairs(BKUP) do
        print(e[3] .. '*', NAME[e[1]], NAME[e[2]])
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
-- of the source HEAD, else mg), the sync time, and the commits,
-- bytes and actions (non-merge commits) received, the source
-- HEAD and the receiver's new HEAD (MERGES).
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
        -- received: commits, bytes of new objects (uncompressed);
        -- --topo-order: merges are dated 0 (date walk errs)
        "  local hn=$(git -C $T" .. C .. " rev-parse HEAD)",
        "  local nc=$(git -C $T" .. C .. " rev-list --topo-order --count $ht..$hn)",
        "  local nb=$(git -C $T" .. C .. " rev-list --topo-order --objects $ht..$hn | cut -d' ' -f1 | git -C $T" .. C .. " cat-file --batch-check='%(objectsize)' | awk '{s+=$1} END {print s+0}')",
        "  local na=$(git -C $T" .. C .. " rev-list --topo-order --no-merges --count $ht..$hn)",
        "  echo \"pull $2 $3 $rc $k $((t1-t0)) $nc:$nb:$na:$hf:$hn $(echo \"$out\" | grep -m1 ERROR | tr ' ' _)\" > $B/status.$1",
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
        -- postf <lane> <leaf> <ts> <key> <file>
        "postf () {",
        "  local T=$(printf \"$B/p%02d\" $2)",
        "  local t0=$(date +%s%N)",
        "  out=$(freechains --root=$T --now=$3 chain " .. G.ALIAS ..
            " post --sign=$4 file $5 2>&1); rc=$?",
        "  local t1=$(date +%s%N)",
        "  echo \"post $2 0 $rc po $((t1-t0)) $(echo \"$out\" | head -1 | tr ' ' _)\" > $B/status.$1",
        "}",
        "rm -f $B/status.*" }
    for i, t in ipairs(tasks) do
        if t[1] == 'pull' then
            sh[#sh+1] = string.format("pull %d %d %d %d &", i, t[2], t[3], t[4])
        elseif t[6] then
            sh[#sh+1] = string.format("postf %d %d %d %s '%s' &", i, t[2], t[3], t[4], t[6])
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

-- MERGES: each peer's HEAD, and the HEADs it absorbed (its own,
-- pulled ones): a source HEAD outside the set may hold merges
local HEAD, SEEN = {}, {}
local MGONLY = 0                    -- pulls for merges only

--[[
-- Is a pull useful: the source holds an action the receiver lacks?
-- With MERGES, also: the source HEAD is unseen by the receiver.
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
    local h = HEAD[from]
    if G.MERGES and h and not (SEEN[to] and SEEN[to][h]) then
        MGONLY = MGONLY + 1
        return true
    end
    return false
end

local STATS = { pulls=0, idle=0, waves=0, wall=0, forks=0, noop=0 }
local POST, FF, MG = {}, {}, {}     -- times (s), in order
local BORN, VIS = {}, {}            -- post chain time; secs to everywhere
local NC, NB, NA = {}, {}, {}       -- per pull: commits, bytes, actions
local PT = {}                       -- per pull: time (s)
local RX, TX = {}, {}               -- per peer: pulls received, served
local TMAX = 0                      -- latest wave chain time
local RCN = {}                      -- churn: commits per reconnect pull
local CH = { defer=0, backup=0, ring=0, rc=0 }   -- churn: pull counts
local CLA, PCL = {}, {}             -- MIX: class per action, per pull
local MXP, MXF, MXV = {}, {}, {}    -- MIX: posts, forks, visibility per class

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
            HEAD[to] = rest
            SEEN[to] = SEEN[to] or {}
            SEEN[to][rest] = true
            BORN[act] = ts
        else
            if rc ~= '0' then
                error(string.format("wave : pull %s <- %s : rc=%s %s",
                    NAME[to], NAME[from], rc, rest))
            end
            STATS.pulls = STATS.pulls + 1
            local nc, nb, na, hf, hn =
                rest:match("^(%d+):(%d+):(%d+):(%x*):(%x*)")
            NC[#NC+1], NB[#NB+1], NA[#NA+1] = tonumber(nc), tonumber(nb), tonumber(na)
            PT[#PT+1] = tonumber(ns) / 1e9
            PCL[#PT] = CLASS[to]
            if tasks[i][5] == 'rc' then
                CH.rc = CH.rc + 1
                RCN[#RCN+1] = tonumber(nc)
            end
            RX[to], TX[from] = (RX[to] or 0) + 1, (TX[from] or 0) + 1
            HEAD[to] = hn
            SEEN[to] = SEEN[to] or {}
            SEEN[to][hf], SEEN[to][hn] = true, true
            local list = (k == 'ff') and FF or MG
            list[#list+1] = tonumber(ns) / 1e9
            for _, a in ipairs(gain[i]) do
                if not HOLD[a][to] then
                    HOLD[a][to], CNT[a] = true, CNT[a] + 1
                end
            end
        end
    end
    TMAX = math.max(TMAX, ts)
    for a in pairs(ACTIVE) do
        if CNT[a] == N then
            ACTIVE[a], HOLD[a] = nil, nil
            VIS[#VIS+1] = ts - BORN[a]
            if CLA[a] then
                local v = MXV[CLA[a]] or {}
                v[#v+1], MXV[CLA[a]] = ts - BORN[a], v
            end
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

--[[
-- Sum of a list of times.
-- Inputs:
--  - xs [table]: times (s)
-- Outputs:
--  - [number]: the sum (s)
-- Callers:
--  - main chunk [p2p.lua]: the "work" of a report
--]]
local function sum (xs)
    local s = 0
    for _, x in ipairs(xs) do
        s = s + x
    end
    return s
end

--[[
-- Median, p90 and max of a list (sorts a copy).
-- Inputs:
--  - xs [table]: numbers
-- Outputs:
--  - [number]: median, p90, max (0 when empty)
-- Callers:
--  - main chunk [p2p.lua]: the END report
--]]
local function q (xs)
    local ys = table.move(xs, 1, #xs, 1, {})
    table.sort(ys)
    return ys[(#ys + 1) // 2] or 0, ys[math.ceil(#ys * 0.9)] or 0,
        ys[#ys] or 0
end

-------------------------------------------------------------------------------
-- events: { ts, user, msg | nil, file | nil } in time order
--  - simple: N_ACT artificial posts, T.action apart, by leaves
--  - corpus: the first LIMIT events of SRC.tsv (posts only)

local EVENTS = {}
if G.MODE == 'simple' then
    for a = 1, G.N_ACT do
        EVENTS[a] = { G.T0 + a*G.T.action, nil, 'simple ' .. a, nil }
    end
else
    local src = DIR .. '/' .. G.SRC
    for l in io.lines(src .. '.tsv') do
        local ts, kind, id, user = l:match("^(%d+)\t(%a+)\t([^\t]*)\t([^\t]*)\t")
        assert(kind == 'post', "corpus : kind " .. tostring(kind) .. " : not yet")
        EVENTS[#EVENTS+1] = { tonumber(ts), user, nil, src .. '.bodies/' .. id }
        if #EVENTS == G.LIMIT then break end
    end
    G.T0 = EVENTS[1][1] - 3600
end

-------------------------------------------------------------------------------
-- setup: S1 inits, the others clone from an already created
-- neighbour (BFS order, one BFS layer per parallel step)

-- the last checkpoint: run state and a copy of G.BASE
local CKPT = G.BASE .. '.ckpt'
if G.RESUME then
    -- peers as they were at the checkpoint (it stays intact)
    exec("rm -rf " .. G.BASE .. " && cp -a " .. CKPT .. " " .. G.BASE)
else
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
end

-- keys: one per leaf (simple), one per author (corpus, lazily)
local KEYOF, PLACE, NAUTH = {}, {}, 0

--[[
-- Leaf and key of an event's author (sticky, uniform on leaves).
-- Inputs:
--  - user [string|nil]: author (nil: simple, a random leaf posts)
-- Outputs:
--  - [integer]: leaf
--  - [string]: private key path
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function author (user)
    if user == nil then
        local l = LEAF[math.random(#LEAF)]
        user = NAME[l]
        PLACE[user] = l
    elseif not PLACE[user] then
        PLACE[user] = LEAF[math.random(#LEAF)]
    end
    if not KEYOF[user] then
        NAUTH = NAUTH + 1
        KEYOF[user] = KEYS .. '/a' .. NAUTH
        os.execute("ssh-keygen -t ed25519 -N '' -C '' -f " .. KEYOF[user] .. " -q")
    end
    return PLACE[user], KEYOF[user]
end

-------------------------------------------------------------------------------
-- replay: EVENTS, each preceded by the pushes due before it

local HEAP, TIMER = {}, {}          -- pending fires; peer -> fire time

--[[
-- Push a fire onto the heap (min by time, then by insertion).
-- Inputs:
--  - t [number]: chain time of the fire
--  - p [integer]: peer (source)
--  - q [integer|nil]: receiver of a deferred pull (session)
--  - tag [string|nil]: churn: 'rc' reconnect, 'df' deferred pull
-- Outputs:
--  - none
-- Callers:
--  - arm, due [p2p.lua]
--]]
local SEQ = 0
local function hpush (t, p, q, tag)
    SEQ = SEQ + 1
    local e, i = { t, SEQ, p, q, tag }, #HEAP + 1
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
    local lo, hi = G.T.relay[1], G.T.relay[2]
    TIMER[p] = t + lo + math.random() * (hi - lo)
    hpush(TIMER[p], p)
end

-------------------------------------------------------------------------------
-- ticks: chain time is cut in ticks of G.T.tick secs; every pull
-- due in one tick may share a wave (event times shift < tick)

local PEND = {}                     -- due pulls, in order: {to, from, t}
local TICK = nil                    -- end of the current tick

-- local first: session phases (drawn only when G.SYNC is on, so
-- runs without it keep their random sequence)
local SYNC = G.SYNC or {}
local PHASE, SCHED = {}, {}         -- owner -> phase; "p:q" -> pending
for p = 0, N-1 do
    local k = (TIER[p] == 'M') and 'SM' or ((TIER[p] == 'L') and 'LM')
    if k and (SYNC[k] or 0) > 0 then
        PHASE[p] = math.random() * SYNC[k]
        if (G.SLOT or 0) > 0 then   -- whole slots: shared dial-ins
            PHASE[p] = math.floor(PHASE[p] / G.SLOT) * G.SLOT
        end
    end
end

-------------------------------------------------------------------------------
-- churn: seeded outages per peer (G.CHURN), own RNG

local DOWN = {}                     -- peer -> { {s, e}, ... } in order
local BK, RING = {}, {}             -- leaf -> backup mid; mid -> ring mids
for _, e in ipairs(BKUP) do
    if e[3] == 'LX' then
        BK[e[1]] = e[2]
    else
        RING[e[1]] = RING[e[1]] or {}
        RING[e[2]] = RING[e[2]] or {}
        table.insert(RING[e[1]], e[2])
        table.insert(RING[e[2]], e[1])
    end
end

--[[
-- A uniform RNG in [0, 1) (xorshift64), independent of math.random.
-- Inputs:
--  - seed [integer]: non-zero seed
-- Outputs:
--  - [function]: each call returns the next number
-- Callers:
--  - main chunk [p2p.lua]: the outage schedule
--]]
local function rng (seed)
    local x = seed
    return function ()
        x = x ~ (x << 13)
        x = x ~ (x >> 7)
        x = x ~ (x << 17)
        return ((x >> 11) & ((1 << 53) - 1)) / 2.0^53
    end
end

--[[
-- Availability of a peer under churn (nil: no outages).
-- Inputs:
--  - p [integer]: peer id
-- Outputs:
--  - [number|nil]: fraction of time up
-- Callers:
--  - main chunk [p2p.lua]: the outage schedule
--]]
local function avail (p)
    local C = G.CHURN
    local c = CLASS[p]
    if TIER[p] == 'S' then
        return C.S
    elseif TIER[p] == 'M' then
        return (c == nil or c == 'on') and C.on or C.mid
    elseif c == 'on' or (c == nil and (SYNC.LM or 0) <= 0) then
        return C.on
    end
    return nil              -- leaf with sessions
end

--[[
-- The outage of a peer that covers a chain time.
-- Inputs:
--  - p [integer]: peer id
--  - t [number]: chain time
-- Outputs:
--  - [table|nil]: { s, e } covering t, nil when up
-- Callers:
--  - up, nextup [p2p.lua]
--]]
local function outage (p, t)
    local D = DOWN[p]
    if not D then
        return nil
    end
    local lo, hi = 1, #D
    while lo <= hi do
        local m = (lo + hi) // 2
        if D[m][2] <= t then
            lo = m + 1
        elseif D[m][1] > t then
            hi = m - 1
        else
            return D[m]
        end
    end
    return nil
end

--[[
-- Is a peer up at a chain time.
-- Inputs:
--  - p [integer]: peer id
--  - t [number]: chain time
-- Outputs:
--  - [boolean]
-- Callers:
--  - route [p2p.lua]
--]]
local function up (p, t)
    return outage(p, t) == nil
end

--[[
-- Chain time when a peer is up again (t itself when up).
-- Inputs:
--  - p [integer]: peer id
--  - t [number]: chain time
-- Outputs:
--  - [number]: the end of the covering outage, or t
-- Callers:
--  - route [p2p.lua]
--]]
local function nextup (p, t)
    local o = outage(p, t)
    return o and o[2] or t
end

if G.CHURN then
    local C = G.CHURN
    local t0 = EVENTS[1][1]
    local t1 = EVENTS[#EVENTS][1] + 86400
    -- Pareto with median `down`, capped: xm and the capped mean
    local a = C.alpha
    local xm = C.down / 2^(1/a)
    local md = xm * a / (a - 1) - xm^a * C.cap^(1 - a) / (a - 1)
    for p = 0, N-1 do
        local av = avail(p)
        if av then
            local r = rng(C.seed * 1000003 + p + 1)
            local mu = md * av / (1 - av)   -- mean up time
            local D, t = {}, t0 + r() * mu
            while t < t1 do
                local d = math.min(C.cap, xm * (1 - r())^(-1 / a))
                D[#D+1] = { t, t + d }
                -- reconnect: pull from every primary neighbour
                for _, q in ipairs(ADJ[p]) do
                    hpush(t + d, q, p, 'rc')
                end
                t = t + d - math.log(1 - r()) * mu
            end
            DOWN[p] = D
        end
    end
end

--[[
-- Route a pull under churn: both ends up as is; a leaf whose
-- mid is down uses its backup mid; a mid whose supers are all
-- down uses an up ring mid; else defer to when both are up.
-- Inputs:
--  - to, from [integer]: receiver, source
--  - t        [number]: chain time
--  - tag      [string|nil]: kept on a deferred pull
-- Outputs:
--  - [integer|nil]: receiver, source (nil: deferred)
-- Callers:
--  - step, main chunk [p2p.lua]
--]]
local function route (to, from, t, tag)
    if not G.CHURN or (up(to, t) and up(from, t)) then
        return to, from
    end
    -- the end that is up, the one that is down
    local u, d = to, from
    if not up(to, t) then u, d = from, to end
    if up(u, t) then
        local alt
        if TIER[u] == 'L' and d == UP[u] and BK[u] and up(BK[u], t) then
            alt = BK[u]
            CH.backup = CH.backup + 1
        elseif TIER[u] == 'M' and TIER[d] == 'S' then
            local any = false
            for _, q in ipairs(ADJ[u]) do
                if TIER[q] == 'S' and up(q, t) then any = true end
            end
            if not any then
                for _, q in ipairs(RING[u] or {}) do
                    if up(q, t) then alt = q; break end
                end
                if alt then CH.ring = CH.ring + 1 end
            end
        end
        if alt then
            if u == to then return to, alt end
            return alt, from
        end
    end
    CH.defer = CH.defer + 1
    local s = math.max(nextup(to, t), nextup(from, t))
    if s <= t then s = t + 1 end
    hpush(s, from, to, tag or 'df')     -- tagged: no session flag
    return nil
end

--[[
-- Next session of a scheduled link at or after a chain time.
-- The lower-tier peer owns the link (mid: SM, leaf: LM); an
-- owner of class on (MIX) is always on.
-- Inputs:
--  - p, q [integer]: the link ends
--  - t    [number]: chain time
-- Outputs:
--  - [number|nil]: session time, nil if the link is always on
-- Callers:
--  - due [p2p.lua]
--]]
local function session (p, q, t)
    local k = KIND[p][q]
    local per = SYNC[k] or 0
    local o = (TIER[p] == 'L' or (TIER[p] == 'M' and k == 'SM')) and p or q
    if per <= 0 or CLASS[o] == 'on' then
        return nil              -- always on (MIX: class on)
    end
    local ph = PHASE[o]
    return ph + math.ceil((t - ph) / per) * per
end

--[[
-- Move the fires due before a chain time into PEND (as pulls).
-- A fired peer's neighbours pull from it, in order; over a
-- scheduled link the pull waits for the link's next session.
-- Inputs:
--  - lim [number]: fires strictly before `lim`
-- Outputs:
--  - none
-- Callers:
--  - step [p2p.lua]
--]]
local function due (lim)
    while #HEAP > 0 and HEAP[1][1] < lim do
        local e = hpop()
        local t, p, r = e[1], e[3], e[4]
        if r then                       -- session: deferred pull
            if not e[5] then
                SCHED[p .. ':' .. r] = nil
            end
            PEND[#PEND+1] = { r, p, t, e[5] }
        elseif TIMER[p] == t then
            TIMER[p] = nil
            for _, q in ipairs(ADJ[p]) do
                local s = session(p, q, t)
                if not s then
                    PEND[#PEND+1] = { q, p, t }
                elseif not SCHED[p .. ':' .. q] then
                    SCHED[p .. ':' .. q] = true
                    hpush(s, p, q)
                end
            end
        end
    end
end

--[[
-- Build and run one wave: `first` tasks (e.g. a post), then due
-- pulls in order, up to LANES.
-- A pull waits when its receiver or source is busy in the wave,
-- or touched by an earlier waiting pull (keeps the order).
-- A pull with nothing new is dropped.
-- Receivers gain, so they arm their timers (at the pull's time).
-- Inputs:
--  - first [table]: tasks that go first (may be empty)
--  - ts    [integer]: chain time of the wave
--  - act   [integer]: id of a posted action (nil if no post)
-- Outputs:
--  - [boolean]: a wave ran
-- Callers:
--  - advance, main chunk [p2p.lua]
--]]
local function step (first, ts, act)
    local W, R, WD, RD, tasks, rest = {}, {}, {}, {}, {}, {}
    for _, t in ipairs(first) do
        tasks[#tasks+1] = t
        W[t[2]] = true
        if t[1] == 'pull' then
            R[t[3]] = true      -- its source: no writer in the wave
        end
    end
    for i, x in ipairs(PEND) do
        if #tasks >= G.LANES then
            table.move(PEND, i, #PEND, #rest + 1, rest)
            break
        end
        local to, from = route(x[1], x[2], x[3], x[4])
        if not to then
            -- deferred (churn)
        elseif W[to] or R[to] or WD[to] or RD[to] or W[from] or WD[from] then
            rest[#rest+1] = { to, from, x[3], x[4] }
            WD[to], RD[from] = true, true
        elseif useful(to, from) then
            W[to], R[from] = true, true
            tasks[#tasks+1] = { 'pull', to, from, math.floor(x[3]), x[4] }
        else
            STATS.noop = STATS.noop + 1
        end
    end
    PEND = rest
    if #tasks == 0 then
        return false
    end
    wave(tasks, ts, act)
    for _, t in ipairs(tasks) do
        if t[1] == 'pull' then arm(t[2], t[4]) end
    end
    return true
end

--[[
-- Run every pull due strictly before a chain time, tick by tick.
-- Inputs:
--  - upto [number]: chain time (math.huge: drain)
-- Outputs:
--  - [integer]: waves run
-- Callers:
--  - main chunk [p2p.lua]
--]]
local function advance (upto)
    local waves = 0
    while true do
        if #PEND == 0 then
            if #HEAP == 0 or HEAP[1][1] >= upto then break end
            TICK = (math.floor(HEAP[1][1] / G.T.tick) + 1) * G.T.tick
        end
        due(math.min(TICK, upto))
        if #PEND == 0 then
            -- nothing due in this tick (stale timers only)
        elseif step({}, math.floor(PEND[1][3]), nil) then
            waves = waves + 1
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

--[[
-- Sweep every peer (erase revoked payloads, pack loose objects),
-- in LANES lanes; peers are idle between actions (one writer).
-- Inputs:
--  - none
-- Outputs:
--  - [number]: wall secs
-- Callers:
--  - main chunk [p2p.lua]: every G.SWEEP actions
--]]
local function sweep ()
    local lanes = {}
    for p = 0, N-1 do
        local i = p % G.LANES + 1
        lanes[i] = lanes[i] or {}
        table.insert(lanes[i], "freechains --root=" .. root(p) ..
            " chain " .. G.ALIAS .. " sweep > /dev/null 2>&1")
    end
    local sh = {}
    for _, l in pairs(lanes) do
        sh[#sh+1] = "( " .. table.concat(l, " ; ") .. " ) &"
    end
    local f = io.open(G.BASE .. '/sweep.sh', 'w')
    f:write(table.concat(sh, "\n") .. "\nwait\n")
    f:close()
    local t0 = now()
    os.execute("bash " .. G.BASE .. "/sweep.sh")
    return now() - t0
end

local R, AUTH = {}, {}
local t0 = now()
local NE = #EVENTS

-------------------------------------------------------------------------------
-- checkpoint: the run state as Lua source, between actions

--[[
-- A number as Lua source (floats stay floats, inf as 1e999).
-- Inputs:
--  - v [number]
-- Outputs:
--  - [string]: also read back by `tonumber`
-- Callers:
--  - dump [p2p.lua]
--]]
local function num (v)
    if math.type(v) == 'integer' then
        return string.format('%d', v)
    elseif v == math.huge or v == -math.huge then
        return (v > 0) and '1e999' or '-1e999'
    end
    local x = string.format('%.17g', v)
    if not x:find('[.eE]') then x = x .. '.0' end
    return x
end

--[[
-- Append the Lua source of a value (no shared or cyclic tables).
-- Lists of numbers or words and sets of words are packed into
-- one string (N, L, S), unpacked by `restore`.
-- Inputs:
--  - v   [number|string|boolean|table]
--  - out [table]: source pieces
-- Outputs:
--  - none (appends to `out`)
-- Callers:
--  - dump (itself), save [p2p.lua]
--]]
local function dump (v, out)
    local t = type(v)
    if t == 'number' then
        out[#out+1] = num(v)
    elseif t == 'string' then
        out[#out+1] = string.format('%q', v)
    elseif t == 'boolean' then
        out[#out+1] = tostring(v)
    else
        assert(t == 'table', "dump : " .. t)
        local n, c, nl, wl, ws = #v, 0, true, true, true
        for k, x in pairs(v) do
            c = c + 1
            local ik = math.type(k) == 'integer' and k >= 1 and k <= n
            nl = nl and ik and type(x) == 'number'
            wl = wl and ik and type(x) == 'string' and x:find('^%S+$') ~= nil
            ws = ws and x == true and type(k) == 'string' and k:find('^%S+$') ~= nil
            if not (nl or wl or ws) then break end
        end
        local w = {}
        if c > 0 and c == n and nl then
            for i = 1, n do w[i] = num(v[i]) end
            out[#out+1] = 'N' .. string.format('%q', table.concat(w, ' '))
        elseif c > 0 and c == n and wl then
            out[#out+1] = 'L' .. string.format('%q', table.concat(v, ' '))
        elseif c > 0 and ws then
            for k in pairs(v) do w[#w+1] = k end
            out[#out+1] = 'S' .. string.format('%q', table.concat(w, ' '))
        else
            out[#out+1] = '{'
            for k, x in pairs(v) do
                out[#out+1] = '['
                dump(k, out)
                out[#out+1] = ']='
                dump(x, out)
                out[#out+1] = ',\n'
            end
            out[#out+1] = '}'
        end
    end
end

--[[
-- Save a checkpoint after action `a`: the run state into
-- G.BASE/state.lua, then G.BASE copied to CKPT (replaced only
-- once the copy is complete).
-- Inputs:
--  - a [integer]: last action done
-- Outputs:
--  - [number]: wall secs
-- Callers:
--  - main chunk [p2p.lua]: every G.CKPT_N actions
--]]
local function save (a)
    local c0 = now()
    local st = {
        a = a, el = c0 - t0,
        HOLD = HOLD, CNT = CNT, ACTIVE = ACTIVE,
        HEAD = HEAD, SEEN = SEEN, MGONLY = MGONLY,
        HEAP = HEAP, SEQ = SEQ, TIMER = TIMER, PEND = PEND,
        TICK = TICK, SCHED = SCHED,
        KEYOF = KEYOF, PLACE = PLACE, NAUTH = NAUTH, AUTH = AUTH,
        STATS = STATS, POST = POST, FF = FF, MG = MG, BORN = BORN,
        VIS = VIS, NC = NC, NB = NB, NA = NA, PT = PT, RX = RX,
        TX = TX, TMAX = TMAX, RCN = RCN, CH = CH, CLA = CLA,
        PCL = PCL, MXP = MXP, MXF = MXF, MXV = MXV, R = R,
    }
    local out = { 'return ' }
    dump(st, out)
    local f = assert(io.open(G.BASE .. '/state.lua', 'w'))
    f:write(table.concat(out), '\n')
    f:close()
    exec("rm -rf " .. CKPT .. ".new && cp -a " .. G.BASE .. " " .. CKPT ..
        ".new && rm -rf " .. CKPT .. " && mv " .. CKPT .. ".new " .. CKPT)
    return now() - c0
end

--[[
-- Load the run state saved by `save` (G.BASE is the restored copy).
-- Inputs:
--  - none
-- Outputs:
--  - [integer]: last action done
-- Errors:
--  - assert: no or bad state.lua
-- Callers:
--  - main chunk [p2p.lua]: RESUME=1
--]]
local function restore ()
    local env = {
        N = function (x)
            local t = {}
            for w in x:gmatch('%S+') do t[#t+1] = tonumber(w) end
            return t
        end,
        L = function (x)
            local t = {}
            for w in x:gmatch('%S+') do t[#t+1] = w end
            return t
        end,
        S = function (x)
            local t = {}
            for w in x:gmatch('%S+') do t[w] = true end
            return t
        end,
    }
    local st = assert(loadfile(G.BASE .. '/state.lua', 't', env))()
    HOLD, CNT, ACTIVE = st.HOLD, st.CNT, st.ACTIVE
    HEAD, SEEN, MGONLY = st.HEAD, st.SEEN, st.MGONLY
    HEAP, SEQ, TIMER, PEND = st.HEAP, st.SEQ, st.TIMER, st.PEND
    TICK, SCHED = st.TICK, st.SCHED
    KEYOF, PLACE, NAUTH, AUTH = st.KEYOF, st.PLACE, st.NAUTH, st.AUTH
    STATS, POST, FF, MG, BORN = st.STATS, st.POST, st.FF, st.MG, st.BORN
    VIS, NC, NB, NA, PT = st.VIS, st.NC, st.NB, st.NA, st.PT
    RX, TX, TMAX, RCN, CH = st.RX, st.TX, st.TMAX, st.RCN, st.CH
    CLA, PCL, MXP, MXF, MXV = st.CLA, st.PCL, st.MXP, st.MXF, st.MXV
    R = st.R
    t0 = now() - st.el
    return st.a
end

local A0 = 0                        -- last action done (resume)
if G.RESUME then
    A0 = restore()
    math.randomseed(G.SEED, A0)
    print(string.format("== resume at %d", A0))
end

for a = A0 + 1, NE do
    local e = EVENTS[a]
    local ts = e[1]
    local ta, pa = now(), STATS.pulls
    local jf, jm = #FF + 1, #MG + 1
    -- the pushes due strictly before this action
    local w = advance(ts)
    -- the post: fork if the author lacks earlier actions
    local l, key = author(e[2])
    AUTH[key] = true
    -- sync, post, re-sync: first the leaf pulls from its mid
    local m = (G.PRESYNC or CLASS[l] == 'ps') and UP[l]
    if m then
        local to, from = route(l, m, ts)
        if to and useful(to, from) then
            step({ { 'pull', to, from, ts } }, ts)
            w = w + 1
        end
    end
    local miss = lacks(l)
    if miss > 0 then STATS.forks = STATS.forks + 1 end
    if G.MIX then
        local c = CLASS[l]
        CLA[a] = c
        MXP[c] = (MXP[c] or 0) + 1
        MXF[c] = (MXF[c] or 0) + ((miss > 0) and 1 or 0)
    end
    -- the post shares its wave with pulls due in its tick
    TICK = (math.floor(ts / G.T.tick) + 1) * G.T.tick
    due(TICK)
    step({ { 'post', l, ts, key,
        e[3] and (e[3] .. ' by ' .. NAME[l]), e[4] } }, ts, a)
    arm(l, ts)
    -- ... then the mid pulls the post (and relays it as usual)
    if m then
        local to, from = route(m, l, ts)
        if to then
            step({ { 'pull', to, from, ts } }, ts)
            w = w + 1
        end
    end
    w = w + 1
    R[#R+1] = w
    local nf, sf = mma(FF, jf)
    local nm, sm = mma(MG, jm)
    print(string.format(". %5d %3ds  %s  [%03d]  miss=%d  post=%.2f  pulls=%02d  ff[%02d]=%s  mg[%02d]=%s",
        a, math.floor(now() - ta), NAME[l], w, miss, POST[#POST],
        STATS.pulls - pa, nf, sf, nm, sm))
    if G.SWEEP and a % G.SWEEP == 0 then
        print(string.format("== %d sweep %.0fs  peer %s", a, sweep(),
            exec("du -sh " .. root(0) .. " | cut -f1")))
    end
    if G.KEEP and a % G.KEEP_N == 0 then
        -- copy S1, L45 (idle between actions); ev.sh in background
        local k = string.format("%s/.freechains-keep/%s-%dk", DIR, G.KEEP, a // 1000)
        exec("rm -rf " .. k .. " && mkdir -p " .. k .. " && cp -a " ..
            root(0) .. " " .. root(N-1) .. " " .. KEYS .. " " .. k)
        print(string.format("== %d kept %s", a, k))
        if G.EV_N > 0 and a % G.EV_N == 0 then
            os.execute(string.format("sh %s/ev/ev.sh %s-%dk %d > %s/logs/ev-%s-%dk.log 2>&1 &",
                DIR, G.KEEP, a // 1000, ts + 3600, DIR, G.KEEP, a // 1000))
        end
    end
    if a % 10 == 0 then
        local _,  sp = mma(POST, 1)
        local nf, sf = mma(FF, 1)
        local nm, sm = mma(MG, 1)
        print()
        -- work: summed post + pull times (all lanes); par: work
        -- over elapsed (how many ran at once)
        local el = now() - t0
        local wk = sum(POST) + sum(FF) + sum(MG)
        print(string.format("== %d %4ds  forks=%d (%d%%)  post=%s  pulls=%d  ff[%4d]=%s  mg[%4d]=%s  idle=%d  work=%ds  par=%.1f",
            a, math.floor(el), STATS.forks, 100*STATS.forks//a,
            sp, STATS.pulls, nf, sf, nm, sm, STATS.idle,
            math.floor(wk), wk / el))
        print()
    end
    -- checkpoint (after sweep/keep), then reseed: math.random
    -- state cannot be saved, so every run reseeds here
    if G.CKPT_N > 0 and a % G.CKPT_N == 0 and a < NE then
        print(string.format("== %d ckpt %.0fs  %s", a, save(a),
            exec("du -sh " .. CKPT .. " | cut -f1")))
        math.randomseed(G.SEED, a)
    end
end

-- final drain: the pending timers, until none is left
local dw = advance(math.huge)
assert(next(ACTIVE) == nil, "drain : actions not everywhere")
print(string.format("== END drain waves=%d", dw))
local merges = tonumber(exec("git -C " .. dir(0) .. " rev-list --merges --count HEAD"))
print(string.format("== END forks=%d of %d actions (%d%%)  merges in DAG=%d",
    STATS.forks, NE, 100*STATS.forks//NE, merges))
print(string.format("== END pulls dropped (nothing new)=%d  merge-only=%d",
    STATS.noop, MGONLY))
table.sort(VIS)
print(string.format("== END visibility (post -> all peers) secs: median=%.0f p90=%.0f max=%.0f",
    VIS[(#VIS + 1) // 2] or 0, VIS[math.ceil(#VIS * 0.9)] or 0, VIS[#VIS] or 0))

-------------------------------------------------------------------------------
-- check: one `list order`, one `reps` per author, on every peer
-- at chain time (last action + relay): the wall clock would fold
-- years of daily slots (slow, every member capped)

local TEND = math.ceil(math.max(EVENTS[NE][1] + G.T.relay[2], TMAX))

local function same (cmd)
    local ref, bad = nil, 0
    for p = 0, N-1 do
        local out = exec("freechains --root=" .. root(p) .. " --now=" ..
            TEND .. " chain '" .. G.ALIAS .. "' " .. cmd)
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
-- reps: the first 10 authors (keys a1..a10), on every peer
local bad_r, keys = 0, {}
for k in pairs(AUTH) do keys[#keys+1] = k end
table.sort(keys)
for i = 1, math.min(10, #keys) do
    bad_r = bad_r + same("reps member " .. keys[i] .. ".pub")
end
table.sort(R)
print(string.format("== END actions=%d  waves per action median=%d max=%d  pulls=%d  waves=%d wave-wall=%.0fs  idle=%d  elapsed=%.0fs",
    NE, R[(#R+1)//2], R[#R], STATS.pulls,
    STATS.waves, STATS.wall, STATS.idle, now() - t0))
-- per pull: time, commits and actions received; time per
-- received commit and per received action (totals, and the
-- median of the per-pull ratios)
do
    local p1, p2, p3 = q(PT)
    local a1, a2, a3 = q(NA)
    local tc, ta = {}, {}
    for i = 1, #PT do
        if NC[i] > 0 then tc[#tc+1] = PT[i] / NC[i] end
        if NA[i] > 0 then ta[#ta+1] = PT[i] / NA[i] end
    end
    local st, sc, sa = sum(PT), sum(NC), sum(NA)
    print(string.format("== END per pull: time median=%.2f p90=%.2f max=%.2f mean=%.2f  actions median=%d p90=%d max=%d",
        p1, p2, p3, st / math.max(1, #PT), a1, a2, a3))
    print(string.format("== END per commit: %.3fs (total %.0fs / %d commits, median of pulls %.3f)  per action: %.3fs (%d actions, median %.3f)  commits per action %.2f",
        st / math.max(1, sc), st, sc, (q(tc)), st / math.max(1, sa), sa, (q(ta)), sc / math.max(1, sa)))
end
-- MIX, per class (author's leaf; pulls by receiver): forks,
-- visibility, time per pull, per received commit and action
if G.MIX then
    for _, c in ipairs({ 'on', 'ps', 'lf' }) do
        local n, st, sc, sa = 0, 0, 0, 0
        for i = 1, #PT do
            if PCL[i] == c then
                n, st = n + 1, st + PT[i]
                sc, sa = sc + NC[i], sa + NA[i]
            end
        end
        local v1, v2, v3 = q(MXV[c] or {})
        print(string.format("== END class %s: forks=%d of %d (%d%%)  visibility median=%.0f p90=%.0f max=%.0f  pulls=%d  per pull %.2fs  per commit %.3fs  per action %.3fs",
            c, MXF[c] or 0, MXP[c] or 0,
            100 * (MXF[c] or 0) // math.max(1, MXP[c] or 0), v1, v2, v3,
            n, st / math.max(1, n), st / math.max(1, sc),
            st / math.max(1, sa)))
    end
end
-- churn: realized downtime per tier, rerouted, deferred and
-- reconnect pulls (commits caught up per reconnect pull)
if G.CHURN then
    local span = EVENTS[NE][1] - EVENTS[1][1]
    local dt = {}
    for _, t in ipairs({ 'S', 'M', 'L' }) do
        local s, n = 0, 0
        for p = 0, N-1 do
            if TIER[p] == t and DOWN[p] then
                n = n + 1
                for _, o in ipairs(DOWN[p]) do
                    if o[1] < EVENTS[NE][1] then
                        s = s + math.min(o[2], EVENTS[NE][1]) - o[1]
                    end
                end
            end
        end
        dt[#dt+1] = string.format("%s %.1f%% (%d peers)", t,
            100 * s / math.max(1, n * span), n)
    end
    local r1, r2, r3 = q(RCN)
    print(string.format("== END churn: down %s  deferred=%d  backup=%d  ring=%d  reconnect pulls=%d commits median=%d p90=%d max=%d",
        table.concat(dt, ", "), CH.defer, CH.backup, CH.ring, CH.rc,
        r1, r2, r3))
end
-- per pull: commits and bytes received; per peer: pulls by tier
local c1, c2, c3 = q(NC)
local b1, b2, b3 = q(NB)
print(string.format("== END per pull: commits median=%d p90=%d max=%d  bytes median=%d p90=%d max=%d  total=%.1fMB",
    c1, c2, c3, b1, b2, b3, sum(NB) / 1e6))
for _, t in ipairs({ 'S', 'M', 'L' }) do
    local rx, tx = {}, {}
    for p = 0, N-1 do
        if TIER[p] == t then
            rx[#rx+1], tx[#tx+1] = RX[p] or 0, TX[p] or 0
        end
    end
    local r1, _, r3 = q(rx)
    local t1, _, t3 = q(tx)
    print(string.format("== END pulls per %s peer: received median=%d max=%d  served median=%d max=%d",
        t, r1, r3, t1, t3))
end
print(string.format("== END order: %d actions, %d of %d peers differ | reps: %d mismatches over %d authors",
    norder, bad_o, N - 1, bad_r, math.min(10, #keys)))
print((bad_o == 0 and bad_r == 0 and norder == NE) and "== PASS" or "== FAIL")
