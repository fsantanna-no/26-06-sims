# Chat simulation findings (freechains.vcs, 2026-08-28..31)

- Input: `wikimedia.chat`, 155,528 messages, 2010-08-25..2012-11-01
- Sims: `chat-02.lua` (gated chain, reps/likes/begs) and
  `chat-simple.lua` (open chain, signed posts only)
- Machine: 15 GB RAM, git 2.43.0, lua 5.4
- Logs: `chat-02-raw.log`, `chat-02-sweep-summary.txt`,
  `chat-simple-1k.txt`, `chat-simple-5k.txt`,
  `chat-simple-10k.log`, `chat-simple-50k.log`

# Reference run (open chain, sweep every 5k, 50k msgs)

| N   | post avg | loose before | sweep   | pack after | KB/msg |
|-----|----------|--------------|---------|------------|--------|
| 5k  | 0.18 s   | 1.0 GB       | 77 s    | 5 MB       | 1.0    |
| 10k | 0.38 s   | 3.0 GB       | 6 min   | 15 MB      | 1.5    |
| 15k | 0.65 s   | 5.0 GB       | 12 min  | 26 MB      | 1.7    |
| 20k | 0.85 s   | 7.0 GB       | 21 min  | 44 MB      | 2.2    |
| 25k | 3.01 s   | 9.1 GB       | 31 min  | 65 MB      | 2.6    |
| 30k | 2.84 s   | 11.1 GB      | 41 min  | 82 MB      | 2.7    |
| 35k | 1.70 s   | 13.2 GB      | 54 min  | 104 MB     | 3.0    |
| 40k | 2.73 s   | 15.4 GB      | 70 min  | 126 MB     | 3.2    |
| 45k | 3.70 s   | 17.5 GB      | 87 min  | 154 MB     | 3.4    |
| 50k | 4.98 s   | 19.6 GB      | 103 min | 183 MB     | 3.7    |

- growth: post = linear floor + activity spikes;
  loose and sweep = quadratic; pack = super-linear
- totals: 29.2 h posting, 7.1 h sweeping, final pack 183 MB
- runs are deterministic: same N gives identical bytes across runs

# Latency

- per-post cost measured at N=22.5k (11 MB state, 136 authors):
    - git read blob 0.04 s, hash-object + update-ref 0.03 s
    - lua parse snapshot 0.13 s          (O(N))
    - lua serialize + write 0.47 s       (O(N), worst fixed term)
    - `ordered()` sort, twice, 0.10 s    (O(N log N))
    - `advance()` discount scan 0..3.6 s (O(A*N), A = posts in 12h)
- git is NOT the bottleneck; the state model is
- write (serialize) is ~3.6x read (parse)
- latency is NOT monotone in N: windows 25k..50k swing
  1.7..5.0 s with chat activity (A), not with N
- sweeping does not affect post time (loose count irrelevant)

# Disk

- every action snapshots the full state -> O(N^2) raw bytes
    - raw run reached 134 GB at N=90k (old gated sim)
- packed floor is small but SUPER-linear (1.0 -> 3.7 KB/msg):
  `advance` rewrites old entries (maturity, times, reps) on every
  action, so consecutive snapshots differ in O(N) places and
  deltas widen with N
- state never shrinks: at 22.5k, 16.8k entries parked in `12-24`
  (consolidation pays one `earn` per author per day; queue grows)

# Sweep (git gc)

- reclaim works: 19.6 GB -> 0.23 GB at 50k (85..200x)
- per-sweep cost O(N) -> cumulative O(N^2); 103 min at 50k;
  overtakes posting time from ~35k on: not a viable policy
- OOM: default gc needs > 6.6 GB at N >= 10k (git pack window
  over thousands of MB-sized blobs); killed by the kernel
    - fix: `pack.windowMemory=512m`, `pack.threads=2`
    - `gc.bigPackThreshold` did NOT make gc incremental
    - extra caps cost ~40% sweep time; only value is memory safety
- never gc with a concurrent writer (post briefly unanchored)

# Gated chain economy (old chat-02, before open chains)

- single faucet: only the pioneer likes; 50 likes from the
  initial 50k reps + 3 earned = 53 likes, exhausted by N~5k
- like refund/earn go to the LIKED author, nothing returns to
  the liker; pioneer earn requires pioneer posting daily
- result: 15 users ever admitted; blocked rate climbs 32->58%
  (both never-admitted users and admitted users that burst)
- admitted users hover near 0 reps (450+500+1000/day drains fast)

# Fix plan (see .claude/plans/260829-otim.md)

- 1: `advance()` one pass (kills the O(A*N) spikes)
- 2: bound `G.actions` (evict consolidated/queued entries)
- 3: append effect-log instead of snapshots
    - `act`/`reps`/`mature` lines; state = fold of prefix
    - write O(1), disk O(N), no gc, checkpoints bound read
- 4: cheaper serializer (only if 3 is skipped)

# Tree store (freechains.vcs plan 260914-tree, 2026-09-14/15)

- State per commit as a git TREE at `refs/local/<cid>`: one Lua file
  per action (`actions/xx/<cid>.lua`) and per member, the order in
  chunks of 200 cids, the maturing entries in per-day `pending/`
  buckets, `meta.lua`. Unchanged files share blobs across snapshots;
  every commit keeps its own O(1) floor (no anchors, no replay).
- Per post: ~5 blobs (one `hash-object`), one `mktree --batch` (tree
  ids computed in Lua), one create-only `update-ref`; entries load
  lazily by path; `advance()` walks a 13h window of pending records
  and settles by per-member heads, never the backlog.
- Lua CPU per post ~30 ms (os.clock); the rest is process spawn and
  git I/O: 26 git processes per post, ~8 from the store.
- Same machine and input as above, shared with a browser (load ~1.5).
  Logs: `chat-simple-10k-tree-run1.log` (every chunk rewritten),
  `chat-simple-10k-tree-run2.log` (tail-only order, dirty buckets),
  `chat-simple-50k-tree.log` (final store; the lazy-order step landed
  after this run started and is not in it).

| N   | tree post | otim3 post | ref post | tree loose | tree sweep | tree pack | otim3 pack |
|-----|-----------|------------|----------|------------|------------|-----------|------------|
| 5k  | 0.187 s   | 0.128 s    | 0.18 s   | 349 MB     | 9.3 s      | 12.8 MB   | 2.4 MB     |
| 10k | 0.209 s   | 0.229 s    | 0.38 s   | 370 MB     | 13.5 s     | 32.1 MB   | 4.9 MB     |
| 15k | 0.226 s   | 0.331 s    | 0.65 s   | 374 MB     | 16.3 s     | 51.4 MB   | 7.3 MB     |
| 20k | 0.227 s   | 0.441 s    | 0.84 s   | 391 MB     | 19.1 s     | 73.3 MB   | 10.8 MB    |
| 25k | 0.319 s   | 0.563 s    | 3.00 s   | 572 MB     | 26.6 s     | 97.2 MB   | 14.7 MB    |
| 30k | 0.296 s   | 0.690 s    | 2.84 s   | 518 MB     | 25.8 s     | 121.0 MB  | 19.0 MB    |
| 35k | 0.255 s   | 0.805 s    | 1.70 s   | 469 MB     | 26.8 s     | 147.7 MB  | 23.7 MB    |
| 40k | 0.272 s   | 0.939 s    | 2.73 s   | 502 MB     | 29.7 s     | 174.6 MB  | 28.7 MB    |
| 45k | 0.291 s   | 1.150 s    | 3.70 s   | 518 MB     | 32.7 s     | 201.7 MB  | 34.1 MB    |
| 50k | 0.319 s   | 1.223 s    | 4.98 s   | 571 MB     | 35.7 s     | 230.1 MB  | 40.0 MB    |

- post latency: flat-ish (0.19 -> 0.32 s over 50k, the 25k burst
  window included) against otim3's linear climb to 1.22 s and the
  reference's 4.98 s; totals: 3.6 h posting + 3.9 min sweeping
  (otim3: 9.0 h + 4.1 min)
- the floor at 5k is HIGHER than otim3 (0.187 vs 0.128): ~36
  processes per post; uncontended single posts measure 0.15-0.17 s
  at 5k and at 10k alike
- disk: loose grows ~13 small objects per post (350-570 MB of 4 KB
  blocks per 5k window, vs otim3's ~50 MB); the pack is 5.7x otim3
  (230 vs 40 MB at 50k): every post rewrites the tail order chunk,
  one pending bucket, one member file and meta, and each snapshot
  adds ~6 tree objects; sweeps stay under 36 s
- 10k runs: run1 0.205/0.252 s (5k/10k), run2 0.184/0.210 s
- next levers: `git gc --auto` per snapshot to bound the loose pile;
  smaller pending buckets (hours) and a per-member queue to shrink
  the rewritten bytes; the pipeline's own ~18 processes (4x
  ssh-keygen, 4x cat-file commit)

# Tree store: FULL chat replay (2026-09-16)

- 155,528 messages, the whole `wikimedia.chat`; build = plan
  260914-tree with members sharded (same as the comp.compilers run);
  log `chat-simple-full-tree.log`
- `chat-simple.lua` now raises out-of-order timestamps to the running
  clock and counts them (`clamped=`), as the usenet sim did: the
  dataset has a misfiled day (~420 lines of 2012-05-31 after
  2012-06-01), which the `too old` rule refused at post 132,865
- wall: 10:11 -> 23:24 (13h13m) for 155k; the snapshot build needed
  39h for 100k and was then OOM-killed
- "snap 100k" = chat-simple-full-otim3.log (tip file + anchors);
  "old 50k" = chat-simple-50k.log (blob per commit)

| N | old 50k post | snap 100k post | tree 50k post | tree full post | snap sweep | tree sweep | snap after | tree after |
|---|---|---|---|---|---|---|---|---|
| 10k | 0.376 s | 0.174 s | 0.209 s | 0.226 s | 6 s | 14 s | 18 MB | 40 MB |
| 20k | 0.845 s | 0.395 s | 0.227 s | 0.238 s | 17 s | 20 s | 37 MB | 88 MB |
| 30k | 2.839 s | 0.626 s | 0.296 s | 0.301 s | 29 s | 25 s | 56 MB | 143 MB |
| 40k | 2.726 s | 0.914 s | 0.272 s | 0.268 s | 51 s | 30 s | 77 MB | 204 MB |
| 50k | 4.979 s | 1.201 s | 0.319 s | 0.310 s | 78 s | 38 s | 98 MB | 266 MB |
| 60k | - | 1.469 s | - | 0.258 s | 99 s | 48 s | 123 MB | 336 MB |
| 70k | - | 1.764 s | - | 0.272 s | 130 s | 53 s | 147 MB | 407 MB |
| 80k | - | 2.081 s | - | 0.300 s | 186 s | 55 s | 175 MB | 481 MB |
| 90k | - | 2.455 s | - | 0.319 s | 264 s | 68 s | 200 MB | 558 MB |
| 100k | - | 2.865 s | - | 0.307 s | - | 71 s | - | 636 MB |
| 110k | - | - | - | 0.308 s | - | 80 s | - | 715 MB |
| 120k | - | - | - | 0.336 s | - | 92 s | - | 794 MB |
| 130k | - | - | - | 0.299 s | - | 117 s | - | 877 MB |
| 140k | - | - | - | 0.312 s | - | 140 s | - | 962 MB |
| 150k | - | - | - | 0.305 s | - | 160 s | - | 1050 MB |

- post latency 0.20-0.37 s across the whole run; the snapshot build
  reached 2.87 s at 100k
- sweeps grow with the pack: 14 s at 10k -> 160 s at 150k; the
  snapshot build was at 264 s by 90k
- disk after sweep ~3.2x the snapshot build at 100k (636 vs 200 MB),
  1.05 GB at 150k: the per-post rewritten trees and bulk files

# Tree build (branch 260914-tree-trash, runs of 26/09/15-16)

- state as a git TREE per commit (per-entity files, shared
  blobs): reads independent of N, O(1) floors
- logs: chat/logs/chat-simple-{10k-tree-run1,10k-tree-run2,
  50k-tree,full-tree}.log (run from the working tree)

| N       | post avg (old -> tree) | sweep (old -> tree) | pack (old -> tree) |
|---------|------------------------|---------------------|--------------------|
| 5k      | 0.18 -> 0.19 s         | 77 s -> 9.6 s       | 5 -> 14 MB         |
| 20k     | 0.85 -> 0.24 s         | 21 min -> 20 s      | 44 -> 77 MB        |
| 50k     | 4.98 -> 0.31 s         | 103 min -> 38 s     | 183 -> 238 MB      |
| 100k    | (killed) -> 0.31 s     | -- -> 71 s          | -- -> 578 MB       |
| 155.5k  | -- -> 0.31 s           | -- -> 167 s         | -- -> 1005 MB      |

- FULL chat (155,528 msgs, 2.2 years) completes in 13h13m;
  the old build needed 36 h for 50k and died at 100k (OOM)
- latency FLAT (0.19 -> 0.31 s over 30x N; slight drift only)
- sweep LINEAR (~1 ms per action) instead of quadratic
- packed floor linear, ~6.5 KB/msg (trees cost ~1.5-2x the old
  blob floor, which was super-linear anyway)
- 378 ts clamps in the full run = the two known back-jumps in
  the dataset (lines 142k/144k), not a driver issue
- two 10k runs byte-for-byte reproducible (run1 == run2 windows)
