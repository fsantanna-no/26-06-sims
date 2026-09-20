# use-simple: comp.compilers replay (26/09/04)

- input: yyy.mbox (tpd-21), 33,814 messages, 1988-2013
- one signed post per message, ~3 kB payloads, OPEN chain
- 13,890 distinct users (one ed25519 key each, lazy keygen)
- zero clamps: the sorted archive replays as-is
- freechains: 260902-snapshots build (tip file + K-anchors)

| N     | post avg | users  | packed | sweep |
|-------|----------|--------|--------|-------|
|  5000 | 0.137s   |  2,867 |  15 MB |  5.3s |
| 10000 | 0.246s   |  5,255 |  30 MB |  8.9s |
| 15000 | 0.361s   |  7,530 |  44 MB | 12.6s |
| 20000 | 0.482s   |  9,784 |  59 MB | 17.5s |
| 25000 | 0.610s   | 11,781 |  75 MB | 23.6s |
| 30000 | 0.748s   | 13,182 |  91 MB | 31.3s |

- total: 4h34m (16,472s); growth LINEAR (~0.12s per 5k)
- vs chat sim at 30k (0.63s): +19% -- the 14k-member ledger
  (vs 2k) outweighs the payload bytes, which ride hash-object
- tpd-21 checks: "5000 users" at 10k msgs -> measured 5,255;
  "3kB per message" holds (payload = full record)

# Tree store, members sharded (26/09/15): FULL replay

- freechains: plan 260914-tree build (git tree per commit, lazy
  per-entity files; members under `members/xx/`, `tot` in meta,
  due-heads index); log `use-simple-all-tree.log` (also
  `use-simple-5k-tree.log`, `use-simple-15k-tree.log`: identical
  prefixes, byte-for-byte deterministic)
- same machine, shared with a browser (load ~1.5)
- "before"/"after": whole repo around the sweep, payloads included;
  "snap": the 260902-snapshots build above

| N   | users | snap post | tree post | snap before | tree before | snap sweep | tree sweep | snap after | tree after |
|-----|-------|-----------|-----------|-------------|-------------|------------|------------|------------|------------|
| 5k | 2867 | 0.137 s | 0.186 s | 30 MB | 105 MB | 5.3 s | 15.0 s | 15 MB | 28 MB |
| 10k | 5255 | 0.246 s | 0.194 s | 80 MB | 161 MB | 8.9 s | 22.2 s | 30 MB | 62 MB |
| 15k | 7530 | 0.361 s | 0.192 s | 125 MB | 204 MB | 12.6 s | 23.4 s | 44 MB | 94 MB |
| 20k | 9784 | 0.482 s | 0.195 s | 166 MB | 253 MB | 17.5 s | 26.0 s | 59 MB | 126 MB |
| 25k | 11781 | 0.610 s | 0.200 s | 212 MB | 305 MB | 23.6 s | 28.9 s | 75 MB | 159 MB |
| 30k | 13182 | 0.748 s | 0.203 s | 257 MB | 369 MB | 31.3 s | 31.8 s | 91 MB | 193 MB |

- total: 1h54m (6,859s) vs 4h34m (16,472s): 2.4x faster
- post latency FLAT: 0.186 -> 0.203s while the ledger grows 2.9k ->
  13.9k users; the snapshot build grew linearly to 0.748s
- floor higher below ~7k posts (0.186 vs 0.137): ~36 processes per
  post (27 git), Lua CPU ~30ms
- disk: after-sweep ~2.1x the snapshot build (193 vs 91 MB at 30k),
  growing ~32 MB per 5k: every post rewrites its member and action
  shard trees, the tail order chunk, one pending bucket, meta;
  sweeps converge (31.8 vs 31.3s at 30k); loose 400-500 MB per
  window before the sweep (13 small objects per post)

## tree build (branch 260914-tree-trash, 26/09/15)

- log: usenet/logs/use-simple-all-tree.log (working-tree build)

| N     | post avg (old -> tree) | sweep (old -> tree) | pack (old -> tree) |
|-------|------------------------|---------------------|--------------------|
|  5000 | 0.137 -> 0.186 s       | 5.3 -> 15.0 s       |  15 -> 25 MB       |
| 20000 | 0.482 -> 0.195 s       | 17.5 -> 26.0 s      |  59 -> 114 MB      |
| 30000 | 0.748 -> 0.203 s       | 31.3 -> 31.8 s      |  91 -> 175 MB      |

- total 1h54m (was 4h34m); latency flat, no member-ledger drift
  (13,890 members no longer parsed per post)
- floor ~1.9x the old blobs (tree overhead), linear
