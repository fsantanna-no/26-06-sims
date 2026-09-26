# Goal

- run the replays in a P2P topology, not a single root
- measure what only multiple peers can show:
  forks, convergence, hard forks, wire cost, churn recovery
- mirrors the methodology of `/x/papers/p2p-tml-paper`
  (rita-24: 21 peers, 5 hops, churn, 40 h of runs)

# Source to mirror (rita-24)

- 21 peers: line (0-3), cycle (3-8), line (8-11), full
  cycle (12-17), line (17-20); average 5 hops
- one process per peer on ONE machine; merged logs give a
  single comparable timeline
- NetEm for latency (normal distribution, 5-500 ms)
- 108 parameter combinations, 3 runs each, 5 min each
- metrics: time travels, real-time pace, churn recovery

# What differs here

- freechains has NO real-time deadline: network latency only
  moves wall clock, not chain semantics
    - so NetEm is NOT our main knob (keep one latency value
      for realism of the wire measurements)
- the fork-generating knob is SYNC CADENCE in chain time:
  how many events a peer posts before syncing, and how long
  a partition lasts against `time.fork` (7 days)
- virtual time stays dataset-driven (`--now=<ts>`), so peers
  share a monotone clock even while partitioned

# Topology and transport

- reuse the rita-24 graph (21 peers, lines + cycles, 5 hops)
    - smaller variants for cost: 5 peers (tpd-21 chat-03) and
      12 peers (use-03) as the cheap points
- one `--root` dir and one port per peer
- `daemon start --hub --port=P` per peer (accepts push+fetch)
- `chain <alias> sync send|recv localhost:P` between
  neighbours only (never all-to-all)
- `peers.sh`: start/stop, add/rem peer, neighbour sync,
  convergence probe (supersedes the old `peers.sh` item)

# Driver

- `p2p/<corpus>-p2p.lua`, reusing each corpus event stream
    - author -> fixed peer (sticky), as in tpd-21
    - after each event: with probability/cadence, sync with
      K random neighbours (bidirectional)
    - churn: schedule peer down/up windows
    - final convergence sweep: sync along the graph twice
- keep the single-peer drivers untouched

# Parameters

- peers: 5 | 12 | 21
- sync cadence: every 1 | 10 | 100 events per peer
- sync fanout K: 1 | 2 | all neighbours
- partition: none | 1 day | 8 days (crosses `time.fork`)
- latency: 0 | 50 ms (NetEm, realism of wire numbers only)
- corpus slice: 5k events (chat) for the grid; one 20k run
  for the chosen configuration

# Metrics

- fork ratio: branches in `list dag` over total actions
  (tpd-21 item c: 18% chat, 14% news)
- convergence: identical `list order` across peers, and the
  number of syncs needed after the last event
- hard forks: syncs refused as `hard fork`, and the repost
  cost to recover
- wire cost: bytes per `sync send|recv` (git pack sizes) and
  per event; states are local so they never travel
- churn recovery: syncs and wall time for a returning peer
  to match the others' order
- reps divergence: max spread of a member's reps across
  peers before convergence

# Order

- `peers.sh` first: start/stop N peers, clone, sync, probe
- smoke: 5 peers, chat 1k, cadence 10, no churn
- grid on chat 5k; pick one configuration
- repeat the chosen configuration on wiki (revokes) and
  github (likes) slices
- churn and partition runs last (they need reruns)

# Won't do

- all-to-all sync (not a P2P topology)
- full corpora in P2P (21 peers x 94k events is days of CPU)
- real-time deadlines and time travel (no analogue here)
