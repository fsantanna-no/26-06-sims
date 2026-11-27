# Snapshot layout: linear storage, flat op time

- for: freechains implementation (refs/local snapshots)
- from: sims (2606-sims), chat r3 and usenet r5 END keeps
- keep SHA-1 in Lua (C only changes the constant)
- reviewed by freechains-ia (261007-ia-optim), 24/11: OK
    - done: 86e601f (parent 0f43041), branch 261007-ia-optim
    - installed; 49/49 suites, guide.sh pass
    - old repos: error "snapshot layout", rebuild from scratch

# Problem (measured)

- each op rewrites trees that grow with the chain
    - `actions/xx`: N/256 entries (587 at 155k, 45 kB raw)
    - `order`: one tree of N/200 files (778 at 155k)
- `meta.lua` carries the open tick's `posts` list
    - chat: 355 of 830 MB on disk, 38.5% stored whole
    - up to 20 kB raw per snapshot (316 cids at 120k)
- last `order` chunk (200 cids, 8 kB) rewritten per op
- raw bytes per snapshot, chat: 24 kB (10k) -> 106 kB (155k)
- pure-Lua sha1 is 82-88% of Lua work per op
    - post: 2.5M -> 10.7M instr; sync ff: 7.3M -> 48.2M
- so: op time O(N), storage O(N^2)

# Changes

- actions: 2-level shards
    - `apath`: `actions/xx/yy/<cid>.lua` (cid[1:2], cid[3:4])
    - `state.lua` shard code assumes 1 level in ~6 places:
      `shards_all`, `all`, `members_all`, `^(%a+)/%x%x$`
      (858, 1060), 935
    - same depth for members (`members/xx/yy`): one code path
- order: smaller chunks, 2-level dirs
    - `ORDER_K` 200 -> 50
    - `opath`: `order/NNN/NNNNN.txt` (i // 100, i)
    - `sync.lua` hardfork: `ls-tree -r <ref> order/` (42),
      pattern with the extra dir (45)
    - read path: check `state.lua` 1333, 1383
- tick: no cid list in `meta.lua`
    - `tick.posts` (cids) -> `tick.charged` (pub -> count)
    - `close`: bump each pub by count * cost (same reps:
      `bump` has no cap; members are independent)
    - `needs`: no fetch of the tick's posts (pubs only)
    - `advance`: empty-tick test uses `charged`
    - initial tick (`chains.lua` 240): `charged = {}`
    - `needs` still returns the `posted` cids
    - `tick_post`: count instead of append (also for
      admitted begs)
    - keep `posted` (first cid per pub, for credit)
    - keep `acting`
- keep SHA-1 and loose-object writer as they are

# Compatibility

- snapshots are local (`refs/local`), not synced
- old repos: no rebuild (sims rerun from scratch)
    - layout field in `meta.lua`: clear error on old repos
- consensus, wire and refs/payloads unchanged

# Validation

- same order and reps, old vs new layout, same base
  commit (tick-beg-like changes reps by itself)
    - usenet r5 final: 33,814 actions
    - chat r3 final: 155,528 actions
- existing freechains tests pass, `tst/cli-tick` included

# Expected (sims layout test, chat END, same packing)

- packed total: 29% of today's layout (1,335 -> 382 MB)
- per snapshot packed: 1.80 -> 2.26 kB (10k -> 155k)
- raw per snapshot ~flat: about 14 -> 28 kB
- sha1 work per op ~flat, about 3.5x less at 155k
- test used `posts` as a count and 8-hex author keys
    - plan keeps full keys and per-pub counts: a bit more

# After the change (sims side)

- [x] replays, old 0f43041 vs new 86e601f (copies), 24/11
    - `/x/tmp/sims-7a/replay` (replay.sh, atstep.sh)
    - order and reps identical at every step, both corpora
    - raw kB/snapshot chat: old 24 -> 106, new 15 -> 31
    - post Lua instr chat: old 2.7M -> 10.6M, new 2.2M -> 4.0M
    - post wall chat: old 134 -> 195 ms, new 123 -> 159 ms
    - usenet new: post 137 -> 139 ms, ff 309 -> 311 ms
    - disk (one gc at the end): chat old 2,187, new 1,450 MB
        - top trees `actions`, `members` ~5.6 kB whole each
        - sims gc every 5k (real old chat: 830 MB)
- [x] replay with gc every 5k (as sims), 25/11
    - `/x/tmp/sims-7a/replay` (replay2.sh, full2.sh)
    - order and reps identical at end, both corpora
    - chat disk: old 1,304, new 815 MB (63%)
    - chat MB per 5k: old 20 -> 58, new 17 -> 34
    - chat recv s per 5k: old 157 -> 231, new 140 -> 139
    - usenet disk: old 228, new 238 MB (+4%)
    - usenet MB per 5k: ~41 flat, both
    - replay > real sims (chat 830, usenet 151 MB)
- new layout: chat time flat, disk not yet linear
    - top tree `actions` (256 entries, 7.4 kB raw)
    - packed kB/snapshot: 1.7 (10k) -> 5.1 (155k)
    - 80% of new chat per snapshot at 155k
    - usenet: `actions` 2.3 + `members` 1.1 kB
- 16-way shards: freechains 99e83e9 (layout=3), 25/11
    - `actions/a/b/c/d/<cid>`, `members/a/b/c/d/<enc>`
    - installed; 49/49 suites, guide.sh pass
- [x] replay 99e83e9, gc every 5k, chat and usenet, 25/11
    - order and reps identical at end, both corpora
    - chat disk: 0f43041 1,304, 86e601f 815, 99e83e9 435 MB
    - chat MB per 5k: 99e83e9 13.1 -> 15.0 (~linear)
    - chat recv s per 5k: ~140 flat
    - chat packed kB/snapshot: 1.45 (10k) -> 2.30 (155k)
    - usenet disk: 228, 238, 179 MB; ~31 MB per 5k flat
    - usenet packed kB/snapshot: ~2.9 flat
- [x] send 99e83e9 results to freechains-paper, 25/11
    - uerj-paper not listed (offline)
- [x] delete replay copies (`gc-*/src`, `gc-*/peer`)
- [x] p2p smoke on 99e83e9: chat `LIMIT=100`, PASS, 25/11
    - 58 peers same order; reps 0 mismatches; 4m17
    - `N_ACT` env is not read (MODE fixed to corpus)
- [ ] usenet r6 on 99e83e9: running (25/11 10:30)
    - r5 command, KEEP=usenet-full-mix-churn-r6
    - log `p2p/logs/usenet-full-mix-churn-r6.log`
    - ETA ~27/11 12:00 (r5: ~50 h)
    - per 5k: compare with r5 (time, forks, storage)
    - 5k: disk r5 21.5, r6 26.0 MB (+21%); time -3%
    - 10k: disk r5 46.9, r6 55.5 MB (+18%); time -5%
        - 5k -> 10k: r5 +25.4, r6 +29.5 MB
        - trees: 2x objects (245k vs 115k), raw 3.4x less
        - forks, pulls identical to r5
    - replay predicted a gain (30 vs 36 MB at 5k): wrong
      for real peers (small syncs, not 5k per sync)
- [x] usenet r6 END (27/11 ~17:40): PASS, 33,814 actions
    - order 0 of 58 differ; reps 0 mismatches
    - disk one peer: r5 161.2, r6 180.1 MB (+11.7%)
    - 20k +16%, 25k +14%, 30k +13% (r6 vs r5)
    - time at 33.8k: r5 194,263, r6 197,361 s (+1.6%)
    - forks 63% (= r5)
    - usenet: no gain from the new layout
    - keep `usenet-full-mix-churn-r6-final`
- [ ] chat r4 on 99e83e9: running (27/11 17:52)
    - r3 command, KEEP=chat-full-r4
    - log `p2p/logs/chat-full-r4.log`; ETA ~06/12
    - first 20 posts: pulls, forks = r3
    - per 5k: disk, time vs r3 (r3 superlinear disk)
- [ ] explain replay > real disk (old chat 1,304 vs 830)

- storage: replay each END chain on one peer
- op time: post/ff bench on copies at 10k..155k
- p2p reruns only if the paper needs new op times
    - usenet r5 ~50 h, chat r3 ~200 h
