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

# Loop (one action at a time)

- 1. action: a leaf acts (`--now=ts`); its mid pulls from it
- 2. leaves pull from their mid(s) (all at once, a dual-homed
  leaf one mid after the other; not from a mid being written)
  + random super pairs + random sibling pairs
- 3. random mid/super pairs (matching on M-S and S-S links)
- repeat 2-3 k times, then the next action
    - k = (gap to the next action) / d, d = chain time of one
      round (e.g. d = 5 min -> ~10 rounds per `adhd` gap)
    - stop early once every peer has the same HEAD
- within a step: parallel, ONE writer per peer, reads shared
  (safe: a pull only `git fetch`es the source); steps in
  sequence
- skip a pull when the receiver already has the source's HEAD
  commit (`git cat-file -e`, ms)
- simulated (no freechains, 1 action per loop):
    - an action reaches all 59 in ~11 rounds (p90 16)
    - fork share by k: 1 -> 100%, 4 -> 79%, 8 -> 27%,
      12 -> 7%, 16 -> 2.5%, 24 -> 0% (tpd-21: 14-18%)
- short partitions come free (random pairs skip peers for a
  few rounds); long ones are scheduled
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
- floor: every peer replays every action, 58 x ~0.1 s; with
  parallel steps on ~4-6 effective cores ~1-2 s per action
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
- [x] revisit Sizing after the lemmy P2P smoke
- [x] redraw `p2p/hubs50.dia` as hubs-59
- [ ] `p2p/topo.py`: hubs-59 edges + partition schedule
- [ ] `p2p/p2p.lua`: the loop above, parallel steps
- [ ] simple test (artificial posts): init 59 peers, a few
  actions, rounds until all HEADs agree, check `list order`
  and `reps` identical everywhere
- [ ] 59 peers, 5k slice: calibrate d
- [ ] 59 peers, full `adhd`: chosen d
- [ ] partitions: 2-3 mids x 1 day | 8 days
- [ ] later, standalone: small-world, nebula, scale-free
  (larger, alone)

# Won't do

- reproducing rita-24 / tpd-21
- the 5-shape ring (cycle, random, star, complete, hubs):
  replaced by hubs-59; diagram `p2p/topology.dia` kept as a
  record
- random pairings in every tier (simulated: ~43 loops to
  spread, every action forks)
- flood per hop with a fixed delay (replaced by the loop)
- real-time deadlines and time travel (no analogue here)
