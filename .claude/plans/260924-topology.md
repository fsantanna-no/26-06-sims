# Goal

- run the replays on MANY peers, not a single root
- measure what only multiple peers can show:
  forks, convergence, hard forks, wire cost, churn recovery
- NOT a reproduction of earlier topologies
- 59 peers in one super-peer topology, hubs-59 (decided
  26/10/05)

# What freechains changes

- NO real-time deadline: network latency only moves wall
  clock, not chain semantics (no NetEm)
- the fork-generating knobs are in CHAIN time: how many sync
  rounds fit between actions, and how long a partition lasts
  against `time.fork` (7 days)
- virtual time stays dataset-driven (`--now=<ts>`), so peers
  share a monotone clock even while partitioned

# Topology: hubs-59 (26/10/05)

- 3 tiers, diameter 5 (leaf-mid-super-super-mid-leaf)
    - 5 supers (S): fully connected core, 10 links
    - 9 mids (M1-M9): each on 2 neighbouring supers (no mid
      cut off by one super down)
    - 45 leaves (L): M1..M9 carry 1..9 leaves (skew: big vs
      small instances)
    - cross links: the 2 edge leaves of each fan also link to
      the neighbouring mid on their side -> 17 leaves on 2
      mids (Gnutella leaves: up to 3 ultrapeers; Yang and
      Garcia-Molina: 2-redundancy), 28 on 1 mid (KaZaA-like)
    - sibling links in fans >= 4 leaves (adjacent pairs):
      4 -> 2, 5 -> 2, 6 -> 3, 7 -> 3, 8 -> 4, 9 -> 4 (18 links;
      local links, e.g. LAN or Scuttlebutt; none in measured
      super-peer networks)
    - 108 links; all pairs mean 3.4 hops, max 5; leaf to leaf
      mean 3.8 (31% at 5)
- as Monero's core-periphery, Kazaa, Skype; Lemmy-like
  (instances = mids, users = leaves)
- placement: authors UNIFORM over the 45 leaves (sticky)
- diagram: `p2p/hubs50.dia` (hubs-59; file name kept)

# Loop (waves of 6 lanes, 26/10/06)

- wave = 6 tasks, one per lane, all in parallel, then `wait`
- per action:
    - wave 1: the leaf posts (`--now=ts`) + 5 useful pulls
    - wave 2: its own mid pulls the post + 5 useful pulls
    - waves 3..K: 6 useful pulls
    - K = GAP / D (D = chain secs per wave); K = 10 now
    - stop early once every peer holds every action
- drain after the last action: waves until every peer holds
  every action (cap `RMAX` waves)
- useful pull: along a link, the source holds an action the
  receiver lacks
    - tracked in Lua: holders per action not yet everywhere;
      a pull copies all the source's actions; retired at 59
    - no skip checks, no HEAD checks (replaced, 26/10/06)
    - models peers syncing when they have news, not blind
      gossip: fewer forks per K than the old loop
- in a wave: writers distinct, no writer is a source (one
  writer per peer; a pull only `git fetch`es the source)
- picks uniform among useful directed links, greedy
- K = 10 gives <= 60 pulls per action, ~58 needed: saturated,
  stragglers carry over (mock: 10 waves every action)
- old loop (steps 2-3 in rounds, random matchings, skip
  checks): replaced; its runs stay as records in Order
- simulated (old loop, no freechains, 1 action per loop):
    - an action reaches all 59 in ~11 rounds (p90 16)
    - fork share by k: 1 -> 100%, 4 -> 79%, 8 -> 27%,
      12 -> 7%, 16 -> 2.5%, 24 -> 0% (tpd-21: 14-18%)
- long partitions are scheduled
- `p2p/p2p.lua` reusing each corpus event stream; single-peer
  drivers untouched

# Partitions (scheduled)

- cut 2-3 mids from their supers: each mid + its
  single-homed leaves is an island (e.g. M1, M5, M9);
  dual-homed leaves fall back to their other mid; siblings
  keep syncing among themselves
- durations: 1 day (< `time.fork`) | 8 days (> `time.fork`:
  hard forks and recovery cost on reconnect)
- contrast: one super down partitions nothing (every mid has
  a second super)

# Parameters

- peers: 59 (smaller counts only for smoke)
- d (chain time per round): picks k and so the fork share;
  calibrate to ~10-20% forks (tpd-21: 14-18%)
- partition: none | 2-3 mids x 1 day | 2-3 mids x 8 days
- corpus slice: 5k events first; full `adhd` (33k) after

# Metrics

- fork ratio: branches in `list dag` over total actions
- convergence: identical `list order` across peers, and the
  rounds needed after the last event
- hard forks: syncs refused as `hard fork`, and the repost
  cost to recover
- wire cost: bytes per sync (git pack sizes) and per event;
  states are local so they never travel
- churn recovery: rounds and wall time for an island to match
  the others' order after reconnecting
- reps divergence: max spread of a member's reps across
  peers before convergence

# Sizing (26/10/05, estimates)

- machine: i7-1355U (2P + 8E cores, 15 W, throttles), 15 GB
  RAM (~4 GB free), 171 GB disk free
- tree-trash single peer (lemmy open): 0.22 s/ev flat
- per peer, full `adhd`: 278 MB chain at END + ~50 MB loose
  (sweep every 500 events) = ~0.33 GB; keys shared (59 MB)
    - 59 peers: ~20 GB disk
- MEASURED (lemmy P2P smoke): replayed action ~0.15 s; empty
  sync 0.5 s, 28 MB (skipped by the HEAD check)
- MEASURED concurrency (26/10/05): 24 pulls of 10 new actions
  each (2k-action chain), 2 repetitions
    - 1 at a time: 42.6 s (1.78 s per pull), peak 60 MB
    - 4 lanes: 9.5 s; 6 lanes: 6.3-6.6 s (6.6x), ~190 MB
    - 8 / 12 / 24 at once: 6.2-6.8 s (no gain), 300 / 420 /
      760 MB (~30 MB per concurrent pull)
    - pulls are CPU-bound: 6 lanes is the plateau; all at once
      only costs memory
- floor: every peer replays every action, 58 x ~0.1 s; with
  6 lanes ~1-2 s per action
- full `adhd` ~1-2 days; 5k slice a few hours (to confirm)
- RAM: ~30-100 MB per concurrent process; ~2 GB at 20
  concurrent

# References (real P2P, 26/10/05)

- Bitcoin: testnet sample 733 nodes, avg degree 16.6,
  diameter 5, power-law degrees (TxProbe, arXiv 1812.00942);
  block propagation median < 1 s, p90 < 10 s, stale < 0.1%
  (2021+; 1-2% in 2015)
- Ethereum: avg degree 47, power law gamma ~2.34, 3-4 hops,
  ~200 ms per transaction (Ethna, arXiv 2010.01373); no data
- Monero: core-periphery, super-peers (arXiv 2504.17809,
  2504.15986)
- Nebula (ProbeLab): DHT crawls every 2 h of IPFS, Ethereum,
  Filecoin, Polkadot, Celestia; neighbours = k-bucket entries
  (routing, not data links: caveat); public dataset
  `baselight.app/u/probelab/dataset/nebula_crawls`
- Scuttlebutt: follow-graph gossip, closest to a forum (ACM
  ICN 2019); no topology dataset found

# Races (26/10/05)

- plain `git daemon`: SAFE
    - fetches are read-only
    - pushes: objects in quarantine, ref update under a lock
      with compare-and-swap; a concurrent push is rejected
- freechains `--hub`: NOT SAFE (by reading the code)
    - the `pre-receive` hook runs `freechains sync recv
      <sender>` inside the receiver, then rejects the push
    - no locking in `src/`; tip moved by `update-ref HEAD
      <cid>` WITHOUT old value (e.g. `like.lua:218`): no CAS
    - two writers on one peer (two sends, or send + local
      post) -> last `update-ref` wins, the other action
      silently drops out; `refs/states/*` may be read half
      written
    - fetches from other peers stay safe
- simulations unaffected: sequential, pull without daemons
- fix upstream (freechains repo, not here): `flock` around
  mutating commands, or `update-ref` with old value + retry

# Order

- [x] `p2p/race.sh`: hub + concurrent senders + local posts;
  check every post in hub `list order`, `reps` still works
    - [x] written; first run (8 senders x 5 posts, 10 hub
      posts) confirmed races before any loss count:
        - concurrent recvs share ONE temp file
          `<chain>/state-stdin`: "bug found : cannot open
          state-stdin" in the hooks
        - concurrent local posts: "malformed commit : invalid
          signature"
    - [x] full run (8 senders x 5 posts + 10 hub posts, x3)
        - concurrent sends: 23 of 24 failed; 35-41 of 50
          actions missing at the hub per round
        - sequential resend recovers all sender posts
        - SILENT LOSS: round 1, one hub post printed its cid,
          exists in the repo (`get metadata`), but is NOT in
          `list order` even after resends (lost `update-ref`)
        - hub local posts: 2-3 of 10 fail per round
    - causes (tree-trash, `src/freechains/...`):
        - `chain/ssh.lua:140`: one `allowed_signers` file per
          repo, overwritten/removed by concurrent verifies ->
          "invalid signature" (19 of 22 send errors)
        - `chain/state.lua:194`: one `state-stdin` per chain;
          `state.lua:849`: `state-tmp-<i>` -> "bug found :
          cannot open state-stdin", "table index is nil"
        - `chain/post.lua:44`: one `payload-tmp` per chain
        - HEAD by `update-ref` without old value (no CAS)
    - fix upstream: per-process temp names (pid suffix or
      `mktemp`) AND a chain lock (`flock`) for writers
    - plan written: `/x/x/freechains/vcs/.claude/plans/
      261005-races.md` (readers-writer lock, temps, CAS)
- [x] revisit Sizing after the lemmy P2P smoke
- [x] redraw `p2p/hubs50.dia` as hubs-59
- [ ] `p2p/p2p.lua`: the loop above, parallel steps; the
  hubs-59 wiring in `p2p/topo.lua` (as in `hubs50.dia`)
    - [x] written, MODE=simple only; `DUMP=1` prints the 108
      links, identical to the diagram's (checked)
    - [ ] MODE=corpus (see Next steps)
    - [x] settings in `p2p/config.lua`, table `G`, no env
      (26/10/06)
    - [x] `BASE` derived in `config.lua`; tier sizes `_ns`,
      `_nm`, `_nl` in `topo.lua` (no hardcoded 45)
    - [x] abort on the first failed pull (none expected);
      no fails counter
    - [x] comments without `;`, one phrase per line
    - [x] shorter output: `.` lines, pulls per action,
      cur/tot secs; no setup line, `ok` or skips
    - [x] skips and secs per action, totals every 10 actions;
      `N_ACT` 20
    - [x] k rounds per action, no convergence per action
        - k = GAP/D = 10 (`D` 360): simulated forks 27% at
          k=8, 7% at k=12 -> ~15% (target 10-20%)
        - early stop on equal HEADs
        - final drain until HEADs agree (cap `RMAX`)
    - [x] simple test with k = 10, 20 actions (26/10/06): PASS
      in 128 s (~5 s per action)
        - 10 of 20 actions hit k without converging (e.g. act
          3: 12 pulls, act 4 catches up with 82)
        - early stops at 7-9 rounds (simulated median 11)
        - pulls 1,136 < 20 x 58: one pull can carry 2 actions
        - drain 2 rounds, same order and reps on all 59
        - forks not counted yet: needs the fork metric
        - rerun: identical actions, rounds, pulls (SEED
          reproducible); real 130 s, user 127 s, sys 176 s
          (~2.3 cores busy of 10)
        - steps 94 s; outside steps 35 s (HEAD checks, posts,
          END check)
        - sys > user: process spawning (~19k skip checks)
        - est. 5k slice ~7 h, full `adhd` ~2 days at 5 s/action
    - [x] same test without the skip check (26/10/06): too
      slow, reverted -> skip check stays
    - [x] loop rewritten as waves of 6 lanes (see Loop)
        - post and sync times, ff vs mg, min/avg/max
        - mock harness (fake freechains/git): 20 actions,
          constraints hold, drain 2 waves, PASS
    - [x] simple test with waves, 20 actions (26/10/06):
      FAIL (`p2p/logs/waves-1.log`)
        - 61 s (old loop 130 s); 10 waves every action
        - syncs 0.08-0.44 s, grow with chain size; posts
          0.06-0.13 s; 11 of 1,158 syncs are merges
        - all 59: same HEAD, all 20 posts
        - `list order` differs on 4 peers, only at posts
          17-20 (the merged ones)
        - fresh clones of p00, p12, p39 all agree, but 55
          live peers (p00 too) hold another order -> cached
          order depends on the sync path (freechains
          tree-trash), not on the scheduling
        - [x] same schedule, tasks one at a time (scratch
          copy): FAIL too, 3 peers differ -> NOT a race
            - same pulls (1,158), same merges (11), drain 2
            - 290 s vs 61 s in parallel (4.8x from lanes)
        - cause: freechains cached order depends on the sync
          path; a fresh clone recomputes another -> upstream
          bug, for the freechains repo (not here)
            - installed build: `state.lua` 89 lines = MAIN, not
              tree-trash (files dated 26/09/04)
            - merge bcec265 = 10ce90f + 7d6c85b (concurrent)
            - p12 snapshot of 7d6c85b: own lineage (ok)
            - p00 snapshot of 7d6c85b: includes 10ce90f and its
              author's -500 reps = the merge's state
            - `action.lua:373`: snapshot written once ("NEVER
              overwrite"), assumes the first write is the own
              lineage; false when the commit is first applied
              as a loser replayed on the winner's state
              (`CONSENSUS.replay` from `sync.lua`)
            - later forks read the bad snapshot as fork base
              -> other reps -> other winner -> other order
            - fix idea: no snapshots during loser replay, or
              snapshot from the commit's own parents
            - refined (26/10/06): winner reads the RUNNING
              replay state, not the state at the fork; minimal
              repro: same HEAD, 3 orders (merger, FF, clone),
              on main and tree-trash
            - plan: `/x/x/freechains/vcs/.claude/plans/
              261006-bug-winner.md`
            - [x] p2p runs blocked until the fix
            - fix: freechains branch `261006-bug-winner`
              (3befafa), installed 26/10/06 14:36
                - p2p 20 actions: PASS, 0 of 58 differ
                - all 59 peers = a fresh clone
                - repro 8 of 8 attempts agree
                - freechains `make tests`: all pass (user)
    - [x] fixed-width ff/mg fields (26/10/06)
            - reconfirmed on fresh `main` install (26/10/06):
              p2p 3 of 58 differ (`p2p/logs/waves-main.log`);
              repro 4 of 6 attempts diverge
        - old loop PASSed (k = 10): likely luck, same risk
        - user rerun: identical (same 4 peers): fixed repro
          for the upstream fix
        - sync growth: ff avg 0.10-0.13 s up to act 11, 0.25
          s at act 12 (first merges), 0.41 s at act 20
            - [ ] 100 actions: does it level off? (risk for
              the 33k corpus)
- [x] simple test (artificial posts): init 59 peers, a few
  actions, rounds until all HEADs agree, check `list order`
  and `reps` identical everywhere
    - [x] run 1 (26/10/05): PASS in 127 s (`p2p/logs/
      simple-1.log`)
        - 10 actions, all converged; rounds median 11, max 20
          (simulated: 11, p90 16)
        - exactly 58 pulls per action (one per other peer),
          12,998 skipped by the HEAD check, 0 fails
        - same `list order` on all 59 peers, same `reps` for
          all 9 authors
        - ~10 s per action (estimate was 15-25 s)
- [ ] 59 peers, 5k slice: calibrate d
- [ ] 59 peers, full `adhd`: chosen d
- [ ] partitions: 2-3 mids x 1 day | 8 days
    - 8 days: hard forks expected -> count them, not abort
- [ ] later, standalone: small-world, nebula, scale-free
  (larger, alone)

# How to run

- build: freechains 260914-tree-trash installed
    - `--version` says v0.21.0 for both builds: check
      `/usr/local/share/lua/5.4/freechains/chain/state.lua`
      has ~1181 lines (main: 89)
- ONE run at a time (CPU-bound; timings)
- simple test (artificial posts):
    - `cd p2p && lua5.4 p2p.lua > logs/simple-N.log 2>&1`
    - ~4 min for 20 actions; ends with `== PASS` or `== FAIL`
- knobs: edit `p2p/config.lua` (table `G`, no env), one
  comment per field
    - `MODE`, `N_ACT` (20), `GAP` (3600), `D` (360), `RMAX` (100),
      `LANES` (6), `SEED` (1), `DUMP`, `ALIAS`, `BASE`, `T0`
- `DUMP = true`: print the 108 links and exit
- output lines:
    - `. N Ts  <leaf>-><mid>  [W]  post=  pulls=  ff[n]=  mg[n]=
      idle=`
        - T: wall secs of this action
        - W: waves run for this action (< K: early stop)
        - post: post time (s)
        - pulls: syncs run in this action's waves
        - ff/mg: fast-forward / merge syncs, count and
          min/avg/max secs; none: `-.--/-.--/-.--`
        - counts padded: 2 digits (action), 4 (totals)
        - idle: lane slots left empty (no useful pull)
    - `== N Ts  post=min/avg/max  pulls=  ff[n]=  mg[n]=
      idle=`: totals every 10 actions
    - `== END drain waves=W`: waves after the last action
        - not converged after RMAX waves: abort
    - `== END ...`: waves median/max, pulls, waves, wave wall
      time, idle; peers whose `list order` differs; `reps`
      mismatches; PASS also needs N_ACT posts in the order
    - a failed task aborts: `wave : pull <to> <- <from> :
      rc= <err>` or `wave : post <leaf> : rc= <out>`
- files: settings `p2p/config.lua`, topology `p2p/topo.lua`,
  diagram `p2p/hubs50.dia`, peers
  `p2p/.freechains-p2p-<mode>/pNN` (ignored), logs
  `p2p/logs/` (ignored); BASE is wiped on start
- race test: `p2p/race.sh [senders] [posts] [hub-posts]`, env
  `TMP` (fresh dir), `ROUNDS` (3), `PORT` (18399)

# Next steps

- 1. fork metric in `p2p.lua`: per action, does the author
  hold every earlier action (no fork)? plus branches in
  `list dag` at the end
    - cheap now: the author lacks an active action -> fork
- 2. MODE=corpus in `p2p.lua`
    - input: a `lemmy-events.py` TSV (`SRC=`, as
      `lemmy-simple.lua`)
    - authors placed uniformly on the 45 leaves (sticky,
      `SEED`); moderators too
    - kinds as `lemmy-simple.lua`: post, remove (revoke
      `--why`), restore (unrevoke `--file`), delete (free
      self-revoke); ban/addmod counted only
    - final drain: waves after the last action until every
      peer holds every action, reported (convergence metric)
    - waves per action: K = (gap to next action) / D, early
      stop when nothing is missing
    - sweep every WINDOW actions on every peer (in waves)
- 3. smoke: `adhd` first 500 events, D = 300 (5 min)
- 4. 5k slice: calibrate D for ~10-20% forks (tpd-21:
  14-18%)
- 5. full `adhd` (~1-2 days est.)
- 6. partitions: cut M01, M05, M09 for 1 day, then 8 days
- 7. results: `p2p/RESULTS.md`

# Won't do

- reproducing rita-24 / tpd-21
- the 5-shape ring (cycle, random, star, complete, hubs):
  replaced by hubs-59; diagram `p2p/topology.dia` kept as a
  record
- random pairings in every tier (simulated: ~43 loops to
  spread, every action forks)
- flood per hop with a fixed delay (replaced by the loop)
- `p2p/topo.py` generator: topology is fixed; other knobs
  (partitions, d) added on demand
- real-time deadlines and time travel (no analogue here)
