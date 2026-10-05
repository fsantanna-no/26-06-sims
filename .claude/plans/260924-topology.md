# Goal

- run the replays on MANY peers, not a single root
- measure what only multiple peers can show:
  forks, convergence, hard forks, wire cost, churn recovery
- NOT a reproduction of earlier topologies: rita-21 is one
  cluster among five; the harness takes ANY arrangement
- 100 peers (decided 26/10/05)

# What freechains changes

- NO real-time deadline: network latency only moves wall
  clock, not chain semantics (no NetEm)
- the fork-generating knobs are in CHAIN time: how many events
  a peer posts before syncing, and how long a partition lasts
  against `time.fork` (7 days)
- virtual time stays dataset-driven (`--now=<ts>`), so peers
  share a monotone clock even while partitioned

# Harness (arrangement-agnostic)

- 100 peers, one `--root` each, full replica of the chain
- sync = pull from a neighbour's chain dir (`sync recv <dir>`),
  no daemons (as `lemmy/lemmy-p2p.lua`)
- SEQUENTIAL: one freechains process at a time (no races,
  stable timings)
- inputs (files), no topology built in:
    - edges: any graph, directed edges allowed (one-way links)
    - schedule: edges/peers down and up in chain time (churn,
      partitions)
    - placement: author -> peer
- sync policy: every C events of a peer, pull from its
  in-neighbours; final rounds until all `list order` agree
- `p2p/p2p.lua` reusing each corpus event stream; single-peer
  drivers untouched

# Arrangement: ring of 5 clusters (decided 26/10/05)

- 5 clusters joined in a RING by 3-node straight lines
  (5 lines x 3 = 15 line peers)
- 100 peers: 21 + 16 + 16 + 16 + 16 + 15
    - rita-21: line 0-3, cycle 3-8, line 8-11, complete
      12-17, line 17-20 (as rita-24), fixed
    - small-world 16: Watts-Strogatz k=4, beta=0.1, fixed
    - star 16: 1 hub + 15 leaves, lines attach at the hub,
      fixed
    - random 16: Erdos-Renyi, avg degree ~3, REDRAWN every
      epoch (e.g. 1 day of chain time); gateways kept
    - scale-free 16: Barabasi-Albert m=2, fixed
- gateways: one fixed node per cluster side joins each line
  (the star's hub; a chosen node elsewhere)
- ring, not chain: ~half the worst-case distance (~35 hops
  end to end as a chain)
- sizes and line length are parameters: grow any cluster
  (ceiling ~400 peers on full `adhd`)
- placement: authors UNIFORM over all 100 peers (sticky)
- sketch:
    - `[rita-21]-L1-[small-world]-L2-[star]-L3-[random]`
      `-L4-[scale-free]-L5-(back to rita-21)`
- generator: `p2p/topo.py` (sizes, seed) -> `edges.txt`
  (fixed clusters, lines, gateways) + `schedule.txt`
  (random cluster epochs)

# Parameters

- peers: 100 (smaller counts only for smoke)
- sync cadence: every 1 | 10 | 100 events per peer
- partition: none | 1 day | 8 days (crosses `time.fork`)
- corpus slice: 5k events for sweeps; full `adhd` (33k) for
  the chosen arrangements

# Metrics

- fork ratio: branches in `list dag` over total actions
  (tpd-21 item c: 18% chat, 14% news)
- convergence: identical `list order` across peers, and the
  number of sync rounds needed after the last event
- hard forks: syncs refused as `hard fork`, and the repost
  cost to recover
- wire cost: bytes per sync (git pack sizes) and per event;
  states are local so they never travel
- churn recovery: syncs and wall time for a returning peer
  to match the others' order
- reps divergence: max spread of a member's reps across
  peers before convergence

# Sizing (26/10/05, estimates)

- machine: i7-1355U (2P + 8E cores, 15 W, throttles), 15 GB
  RAM (~4 GB free), 171 GB disk free
- tree-trash single peer (lemmy open): 0.22 s/ev flat
- per peer, full `adhd`: 278 MB chain at END + ~50 MB loose
  (sweep every 500 events) = ~0.33 GB; keys shared (59 MB)
- RAM: ~100 MB peak (`list order` on the full chain), constant
  in the number of peers (sequential, no daemons)
- cost model: every action runs at its author and is replayed
  at every other peer -> CPU ~ events x peers x replay cost
    - MEASURED (lemmy P2P smoke, 2k-action chain): replayed
      action ~0.15 s; empty sync 0.5 s, 28 MB
    - empty-sync cost dominates at 100 peers: a round where
      every peer pulls from ~3 neighbours = ~150 s
    - full `adhd`, 100 peers, a round every 10 events:
      ~3.3k rounds x 150 s ~ 6 days + replays 33k x 100 x
      0.1 s ~ 4 days -> ~10 days (time is not a limit)
    - empty-sync cost may grow with chain size: to check
- 100 peers:
    - full `adhd`: ~33 GB disk, ~8 days (upper bound)
    - 5k slice: ~5 GB disk, ~1.2 days
- ceiling: ~400 peers on full `adhd` (disk, 30 GB spare);
  more on smaller slices; time is not a constraint

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

- [ ] `p2p/race.sh`: hub + concurrent senders + local posts;
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
- [ ] revisit Sizing after the lemmy P2P smoke (replay cost,
  empty-sync cost)
- [ ] `p2p/topo.py`: ring of 5 clusters -> edges + schedule
- [ ] `p2p/p2p.lua` + edges/schedule/placement file formats
- [ ] smoke: 5 peers, 1k slice, complete graph, cadence 10
- [ ] 100 peers, 5k slice: arrangements x cadence
- [ ] 100 peers, full `adhd`: chosen arrangements
- [ ] churn and partition runs last (they need reruns)

# Won't do

- reproducing rita-24 / tpd-21 alone (rita-21 is ONE cluster)
- all-to-all sync as the only arrangement (complete graph is
  one input among many)
- parallel peers (sequential is enough; time is not a limit)
- real-time deadlines and time travel (no analogue here)
