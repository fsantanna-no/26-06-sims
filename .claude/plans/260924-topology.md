# Goal

- run the replays on MANY peers, not a single root
- measure what only multiple peers can show:
  forks, convergence, hard forks, wire cost, churn recovery
- NOT a reproduction of earlier topologies; the harness takes
  ANY arrangement
- 40 peers: 5 shapes joined directly (decided 26/10/05)

# What freechains changes

- NO real-time deadline: network latency only moves wall
  clock, not chain semantics (no NetEm)
- the fork-generating knobs are in CHAIN time: how many events
  a peer posts before syncing, and how long a partition lasts
  against `time.fork` (7 days)
- virtual time stays dataset-driven (`--now=<ts>`), so peers
  share a monotone clock even while partitioned

# Harness (arrangement-agnostic)

- 40 peers, one `--root` each, full replica of the chain
- sync = pull from a neighbour's chain dir (`sync recv <dir>`),
  no daemons (as `lemmy/lemmy-p2p.lua`)
- SEQUENTIAL: one freechains process at a time (no races,
  stable timings)
- inputs (files), no topology built in:
    - edges: any graph, directed edges allowed (one-way links)
    - schedule: edges/peers down and up in chain time (churn,
      partitions)
    - placement: author -> peer
- sync policy: FLOOD in chain time with per-hop delay d
    - after an event at ts, its peer's neighbours pull at
      ts + d, theirs at ts + 2d, ... (discrete-event queue,
      interleaved with later events)
    - pull only from a neighbour that has something new (no
      empty syncs)
    - final rounds until all `list order` agree
- why not "every C events": `adhd` has ~27 events/day, so 10
  events ~ 9 h per hop, ~4-5 days across the ring: close to
  `time.fork` (7 days), forks on nearly every event
- `p2p/p2p.lua` reusing each corpus event stream; single-peer
  drivers untouched

# Arrangement: ring of 5 shapes, joined directly (26/10/05)

- order (ring, the last wraps to the first):
    - cycle, 6 peers: single ring; fixed
    - random, 6 peers: Erdos-Renyi, avg degree ~3, REDRAWN
      every epoch (e.g. 1 day of chain time); gateways kept;
      ~9 links per epoch: noisy, may split (= partition)
    - star, 7 peers: 1 hub + 6 leaves; hub = both gateways;
      fixed
    - complete, 6 peers: fully connected (multi-cycle); fixed
    - hubs, 15 peers: super-peers, 3 tiers; fixed
        - 4 supers fully connected (core); gateways = 2 supers
        - 3 mids, each on 2 supers
        - 8 leaves on the mids (3/3/2), one link each
        - inside worst path: leaf-mid-super-super-mid-leaf (5)
        - as Monero's core-periphery, Kazaa, Skype
- 40 peers; NO separators: OUT gateway of a shape linked
  directly to the IN gateway of the next (1 hop)
- gateways IN and OUT on one axis (no zig-zag); the cycle and
  complete put them opposite (3 hops apart in the cycle)
- worst path ~8-9 hops (half the ring); Bitcoin ~5,
  Ethereum 3-4
- partitions/churn: the ring survives one inter-shape link
  down; two links down split it in two
- dropped: rita (= cycle + complete + line), separators;
  small-world, nebula, scale-free (Barabasi-Albert): better
  as standalone, larger runs (a power law needs 100s of nodes)
- hubs holds 15 of 40 peers (38%): with uniform placement it
  weighs more in the overall results
- placement: authors UNIFORM over all 40 peers (sticky)
- diagram: `p2p/topology.dia` (40 peers, as above)
- generator: `p2p/topo.py` (sizes, seed) -> `edges.txt` +
  `schedule.txt` (random epochs)

# Parameters

- peers: 40 (smaller counts only for smoke)
- per-hop delay d: 1 s (Bitcoin-like) | 1 min | 1 h (laptops
  syncing hourly)
    - fork share ~ 1 - exp(-rate x d x hops), rate ~1.1/h:
      ~0.4% | ~20% | ~100% at 12 hops (tpd-21: 14-18%)
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
    - flood pulls only where something is new: no empty
      syncs
    - empty-sync cost may grow with chain size: to check
- 40 peers, flood (39 replays x ~0.65 s ~ 25 s per event):
    - 5k slice: ~1.5 days, ~2 GB disk
    - full `adhd`: ~9-10 days, ~13 GB disk
- ceiling: ~400 peers on full `adhd` (disk, 30 GB spare);
  more on smaller slices; time is not a constraint

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
- [ ] `p2p/topo.py`: ring of 5 shapes -> edges + schedule
- [ ] `p2p/p2p.lua` + edges/schedule/placement file formats
- [ ] smoke: 5 peers, 1k slice, complete graph, d = 1 min
- [ ] 40 peers, 5k slice: d = 1 s | 1 min | 1 h
- [ ] 40 peers, full `adhd`: chosen d
- [ ] later, standalone: small-world, nebula, scale-free
  (larger, alone)
- [ ] churn and partition runs last (they need reruns)

# Won't do

- reproducing rita-24 / tpd-21 (rita split into cycle,
  complete, line)
- all-to-all sync as the only arrangement (complete graph is
  one input among many)
- parallel peers (sequential is enough; time is not a limit)
- real-time deadlines and time travel (no analogue here)
