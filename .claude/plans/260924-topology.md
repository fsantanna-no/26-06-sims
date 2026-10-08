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
    - no sibling links (removed 26/10/06): under push at
      N = 60 s they changed forks by <= 0.5 pt and spread by
      <= 3 s (adhd, github, wiki); none in measured
      super-peer networks
    - 90 links: 10 S-S, 18 M-S, 45 leaf-own-mid, 17
      leaf-neighbour-mid
- as Monero's core-periphery, Kazaa, Skype; Lemmy-like
  (instances = mids, users = leaves)
- placement: authors UNIFORM over the 45 leaves (sticky)
- all 45 leaves always online (decided 26/10/06; REPLACED by
  Churn, 26/10/07): no offline simulation
    - wikimedia chat, speakers at once (log has no joins or
      parts, so lurkers are unseen): 10 min max 18 (median 2),
      1 h max 28 (median 3), 1 day max 48 (median 12); 677
      speakers in all
    - 45 leaves ~ 18 writers + ~30 silent readers at the
      peak: not unrealistic
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

# Sync policy (26/10/06, superseded by push below)

- concern: a target fork share (15-20%, 0%) is arbitrary;
  the fork share is an OUTCOME of how often peers sync
- tpd-21 gives no reason for its numbers (verbatim):
    - "For the newsgroup, we use N=15 and M=5, which
      represents a larger number of peers with few
      interconnections to stress the local-first nature of
      the protocol."
    - "For the chat, we use N=5 and M=3, which represents a
      smaller number of peers with more interconnections."
    - "We found a ratio of 18% for the chat and 14% for the
      newsgroup, which confirms that the simulation achieves
      a reasonable level of asynchrony."
    - its model has no time: after each message, sync with
      M random peers; forks come from M < N
- real gaps between actions (p10 / median / p90 / mean):
    - chat, wikimedia FULL: 166k msgs, 2.2 y:
      2 s / 13 s / 99 s / 6.9 min
        - 10k slice: 3 s / 12 s / 117 s / 12 min
    - usenet, comp FULL (`yyy.mbox`): 25k dated, 25.9 y:
      20 s / 43 min / 21 h / 9.0 h
        - 25,068 of 35,196 `Date:` lines parse (71%)
        - 10k slice: 5.9 min / 2.7 h / 19 h / 9.1 h
    - SE vegetarianism (`data/se`, fetched 26/10/06), 7.1 y:
        - posts: 2,257: 4.5 min / 4.2 h / 79 h / 28 h
        - posts + comments: 5,413: 97 s / 47 min / 30 h /
          12 h
        - votes: dates are DAY-only -> no gaps from votes
    - lemmy adhd: mean ~53 min (33k events, 3.3 y)
    - github yt-dlp: mean ~28 min (94k events, ~5 y)
    - wiki Abortion: mean ~16 h (21k events, 25 y)
    - [ ] medians for lemmy/github/wiki: refetch (`data/`
      not on disk; lemmy live API ~30 min)
- forks depend on a ratio: spread time vs gap to the next
  action, not on K itself
- proposal: a sync RULE a reader accepts, per app class
    - only two quantities:
        - T.action: time between two consecutive actions
          (from the corpus)
        - T.sync: each peer syncs with an up-link every
          T.sync (the app rule)
    - chat: T.sync = 5-10 s; forum / usenet: ~30 min
    - syncs per peer per action = T.action / T.sync
    - syncs per action = 59 x T.action / T.sync
    - waves per action = 59 x T.action / T.sync / 6 lanes
    - e.g. chat: 13 s / 5 s = 2.6 syncs per peer, ~26 waves;
      usenet: 43 min / 30 min = 1.4 syncs per peer, ~14
    - fork share = the RESULT at that rule; also sweep T.sync
      and plot forks vs T.sync / T.action (curves collapse?)
- current waves model: OK, with two changes
    - quota: each peer syncs T.action / T.sync times per
      action, random order (back-to-back waves allowed)
    - blind pick: at its turn, a peer pulls a random up-link;
      a no-op pull still counts as its sync, but is not run
    - today: picks only pulls with news; no per-peer quota
- percentiles: p10 = 10% of gaps are at most that value;
  p90 = 10% of gaps are at least that value
- [x] implemented (26/10/06): `G.T = {action, sync}` in
  `config.lua` (replaces GAP, D); `syncs()` builds the blind
  quota, `play()` packs it in waves, in order
    - a task waits if an earlier waiting task touches its
      peers; a no-op sync counts (`noop`) but takes no lane
    - the post's upload to its own mid stays (outside quota)
    - drain: syncs of one T.action, repeated (`RMAX` = 20)
- mock sweep (200 actions, seeds 1-3), forks by
  T.action / T.sync:
    - 1: 99%, 2: 95%, 5: 66%, 10: 21%, 20: 0.2%, 30+: 0%
    - waves per action saturate at ~17 (no-ops are free)
    - blind pull from a random neighbour is slow: ~20 syncs
      per peer per action needed for no forks
    - chat 13 s / 5 s = 2.6 -> ~90% forks; usenet 43 / 30 min
      = 1.4 -> ~97%: "reasonable" polling forks almost always
    - the previous oracle (sync only with news) ~ push /
      event-driven designs; blind = polling: two real designs
- real run, ratio 2 (`p2p/logs/tsync-1.log`): sync time
  explodes with forks (act 14: ff avg 7 s, mg max 28 s;
  oracle run: ~0.3 s) -> freechains cost with many forks
- open: T.sync per app class; cite real systems (IRC/Matrix,
  ActivityPub push, NNTP feeds, UUCP batches)


# Sync rule: push with relay delay (26/10/06, decided)

- push: a peer that gets something new arms a timer U(0, N)
  chain secs; when it fires, every neighbour lacking something
  pulls from it
    - keep: a pending timer is not restarted (it carries what
      arrived meanwhile); restart starves under bursts (const
      3600 s gaps, N = 3600: 86% vs 71% forks)
- realistic: ActivityPub delivers on change (send queues);
  Bitcoin relays after random Poisson delays (trickling);
  Gnutella flooded at once; N is the one relaxation for forks
- confirmed blind model (re-implemented, 26/10/06): constant
  ratio 1: 99.5%, 2: 97.5%, 5: 70%, 10: 20%, 11: 16%,
  12: 11%, 20: 0% -> 15% at ~11.2
- real gaps (this machine, p10 / median / p90 / mean):
    - chat 166,277: 2 s / 13 s / 99 s / 7 min
    - adhd 33,027: 44 s / 9 min / 84 min / 53 min
    - github 94,006: 45 s / 10 min / 83 min / 32 min
    - wiki 13,973: 49 s / 18 min / 29 h / 15.6 h
    - usenet 25,066: 20 s / 42 min / 21.7 h / 9.0 h
    - se-veg 5,565 (posts + comments): 83 s / 43 min /
      28.7 h / 11.3 h
- blind polling on real gaps (2,000-gap middle slices):
    - forks at T.sync 30 min: adhd 97%, github 98%, wiki 81%,
      usenet 90%, se-veg 63%; chat at 5 / 10 s: 79 / 89%
    - 15% needs T.sync: chat 0.4 s, adhd 13 s, github 16 s,
      wiki 6 s, usenet 3 s, se-veg 47 s: unrealistic
      (short gaps dominate; one random neighbour per sync)
- push, N for 15% forks (U(1, N), keep; same slices):
    - adhd 52 s, github 65 s, wiki 20 s, usenet 11 s,
      se-veg 3.2 min; spread to all 59 in 0.5-7 min
    - chat: even N = 1 gives 23%; chat stays INSTANTANEOUS
      (N = 0): forks only at same-second messages (~3%)
- the paper: chat instantaneous (natural ~3%); the others
  at N tuned to 15%, a chosen stress level for async apps
- [x] `p2p.lua`: push with timers (heap, keep), `G.T.relay`
  replaces `G.T.sync`; drain = the pending timers; `G.T.tick`
  packs waves
- usenet dates 2000-2007 are MODERATION BATCHES (26/10/06)
    - every author dated US Eastern (-0400/-0500): stamped by
      the moderator's server at release, not at posting
    - 2000-06: 66-72% of gaps < 60 s (e.g. 2002-07-31
      00:54:57-00:59:46 EDT, 7 msgs, 5 authors); 2007: 24%
    - 1987-95: GMT dates, gaps < 60 s 0-9%; 2008-13: the
      authors' own zones, 0-4%; 1996-99: missing (1 msg)
    - gaps 2000-07 are bimodal: 75% < 2 min, then hours;
      batches (gaps < 10, 30 or 60 min) ~2,000, size median
      2-3, p90 15-17
    - the mbox keeps only From/Subject/Date: real posting
      times are lost
    - fix (decided): spread each batch (gaps < 10 min,
      2000-2007) evenly over the gap before it, order kept,
      last message keeps its stamp -> 1,163 batches, 10,610
      msgs; 2000-07 gaps < 60 s: 65% -> 0.2%, median 1 ->
      214 min
    - forks at N = 60 s, slices 10/30/50/70/90%: raw 2 / 7 /
      71 / 69 / 3% -> spread 1.4 / 6.7 / 6.8 / 3.5 / 2.8%
    - [ ] apply the spread in the usenet event stream for P2P
      (single-peer usenet runs used raw dates)
- corpus rule (decided 26/10/06): chat N = 0 (instant),
  all others N = 60 s; forks are the OUTCOME per corpus (60 s:
  adhd 15-22%, github 12-15%, wiki 10-30%, se-veg 4-26%,
  usenet 1-7% spread); supersedes per-corpus 15% tuning
    - posts see only pushes STRICTLY before them: same-second
      messages fork (chat ~3%)
- ticks (26/10/06): chain time in ticks of `T.tick` (= N/10;
  chat 1 s); pulls due in one tick share waves, the post too
    - exact only for one instant; error < one tick per event
    - simple test (`p2p/logs/push-2.log`, tick 180): PASS in
      97 s (push-1: 109 s); waves 362 -> 294, idle slots
      1,019 -> 642 (47% -> 36%); forks 25%, 5 merges
    - without sibling links (`p2p/logs/push-3.log`): PASS in
      111 s; waves 293, idle 604; forks 7 of 20 (35%, noise
      at 20 actions: model 25-31%), 7 merges
- expected per corpus (26/10/06; push, hubs-59 with 90 links,
  posts see only earlier pushes; mock on 2,000-gap slices at
  10/30/50/70/90%; run time at ~5.5 s per action, a lower
  bound)
    - chat: 166,277 actions; N 0, tick 1 s; forks 1.7 / 2.6 /
      3.5 / 2.8 / 3.3%, mean 2.8%; spread 0 s; ~10 days
    - adhd: 33,027; N 60 s, tick 6 s; forks 22.4 / 21.0 /
      15.3 / 21.9 / 15.4%, mean 19.2%; spread 140 s; ~2 days
    - github: 94,006; N 60 s; forks 13.1 / 14.4 / 13.5 /
      12.3 / 14.9%, mean 13.7%; spread 141 s; ~6 days
    - wiki: 13,973; N 60 s; forks 16.4 / 23.5 / 31.2 / 13.8 /
      10.7%, mean 19.1%; spread 139 s; ~21 h
    - se-veg: 5,565; N 60 s; forks 25.6 / 9.8 / 5.3 / 4.2 /
      4.0%, mean 9.8%; spread 142 s; ~9 h
    - usenet (batches spread): 23,745; N 60 s; forks 1.4 /
      7.1 / 7.4 / 3.5 / 2.6%, mean 4.4%; spread 142 s;
      ~1.5 days
    - event streams for corpus mode:
        - adhd: ready (`lemmy-events.py` TSV)
        - github: TSV ready; likes/dislikes not yet supported
        - wiki, chat, se-veg: TSV conversion needed (se-veg
          votes dated by day only)
        - usenet: TSV conversion with the batch spread
- corpus mode, posts only (26/10/06)
    - converters: `chat/chat-events.py` -> `data/chat.tsv`
      (155,528 `<nick>` messages, 645 nicks, UTC, sorted);
      `usenet/use-events.py` -> `data/usenet.tsv` (33,814
      records, 12,539 senders)
    - usenet: 10,077 records (1995-2000) are DATE-ONLY
      (`YYYY/MM/DD`): spread evenly over their day (1,014
      days); plus the 2000-2007 batch spread (1,163 batches)
        - correction: 1996-99 are not missing, only date-only
    - `p2p.lua`: `MODE='corpus'`, `SRC`, `LIMIT`; authors
      placed uniformly and sticky on leaves, one key per
      author; posts from body files (`postf`); `T0` = first
      event - 3600; reps checked for the first 10 authors
    - `config.lua`: `CORPUS` picks relay (chat 0, usenet 60)
      and tick (relay / 10, min 1)
    - usenet, 500 events (1987-88; `p2p/logs/usenet-500.log`):
      PASS in 41 min (~4.9 s per action)
        - forks 2 of 500 (0.4%), 2 merges; expected for that
          period (long gaps)
        - 28,786 pulls (~57.6 per action); waves 7,881, idle
          38%; drain 16 waves
        - ff syncs avg 0.18 -> 0.29 s (grow with the chain),
          max 0.53 s; posts ~0.13 s
        - same `list order` on all 59; `reps` match (10)
    - chat, 500 events (2010-08; `p2p/logs/chat-500.log`):
      PASS in 32 min (~3.8 s per action)
        - forks 6 of 500 (1.2%), 6 merges; the first 500
          have 9 same-second pairs (a fork needs the next
          author on another leaf): instant push works
        - 28,782 pulls (~57.6 per action); waves 5,947, idle
          18% (1 s ticks pack better); drain 11 waves
        - ff avg 0.19 -> 0.30 s, max 0.51; mg 0.38-0.52 s
        - same `list order` on all 59; `reps` match (10)
    - [x] chat 5k (26/10/06-07): STOPPED at 1,992 of 5,000
      (`p2p/logs/chat-5k.log`); usenet 5k not started
        - SYNC BLOWUP: s per action ~3.8 (1-500), ~6.5
          (760-1,010), ~24.6 (1,260-1,510), ~37.7
          (1,760-1,980); ff pull avg 0.18 -> 1.29 s, max 9.25
        - posts stay fast: avg 0.12 -> 0.17 s, max 0.34
        - forks 22 of 1,980 (1.1%), as expected for chat
        - per peer: ~5,900 loose objects, 192 MB, nothing
          packed (~207 MB): ~32 KB per object, full state
          blobs per action in this build (`261006-bug-winner`,
          main layout); the P2P driver never sweeps or packs
        - probable cause (not verified): state blobs grow with
          the chain, read/written on every pull (~58 per
          action); single-peer main build grew too (0.17 ->
          1.15 s/ev over 33k)
        - peers kept: `p2p/.freechains-p2p-chat/` (for tests)
    - [ ] fix the sync blowup before longer runs
        - [x] test on copies of the kept peers (26/10/07)
            - `sweep`: 208 MB (5,903 loose) -> 5.1 MB (one
              pack), ~9.5 s per peer
            - pull of 1 new action: raw 2.31 / 0.73 / 0.72 s,
              swept 0.35 / 0.38 / 0.39 s
            - likely cause: 59 x ~207 MB ~ 12 GB > ~4 GB free
              RAM: parallel pulls waited on disk; swept peers
              total ~300 MB (fit in the page cache)
        - [x] periodic sweep in the driver: `G.SWEEP` (500),
          all peers in lanes, between actions; logs `== <a>
          sweep <s>  peer <size>`; ~95 s per sweep (~0.2 s
          per action)
        - [x] rerun chat 5k with sweeps on `261006-bug-winner`
          (26/10/07): STOPPED at 712 to switch build
          (`p2p/logs/chat-5k-sweep-main-stopped.log`)
            - sweep at 500: 18 s, peer 1.2 MB (was ~200 MB)
            - s per action ~3.8 (1-500), ~3.9 (500-700): flat
              (no-sweep run: ~5 and rising); ff avg 0.30 s,
              max 0.51; forks 8 of 700 (1.1%)
        - [x] reinstall (user, 26/10/07 08:25): tree-trash
          (3752b78) + the bug-winner fix STAGED, uncommitted
          (`state.lua` 1,182 lines; installed = freechains
          working tree)
        - [ ] chat 5k, then usenet 5k, on that build (started
          26/10/07; `p2p/logs/chat-5k.log`, `usenet-5k.log`)
            - posts flat (~0.19-0.20 s); fast-forward pull avg
              per 250 actions 0.36 -> 1.01 s by 1,950 (~+0.4 s
              per 1,000): s per action ~5 (500) -> ~14 (2,200)
            - profile of one pull (26/10/07, scratch copy of
              `sync.lua`, ~2,372 actions): 1.25-1.33 s, of which
              `STATE.read`+`STATE.all` 0.42-0.51 s and payload
              fetch 0.21-0.27 s (whole chain, even with nothing
              new: 0.98 s), `hardfork` 0.18-0.20 s (walks the
              last 7 days = the whole chat chain); fetch 0.18,
              apply new commit 0.11-0.16; a post 0.21 s
            - upstream plan: `/x/x/freechains/vcs/.claude/plans/
              261007-sync-optim.md` (tree branch only;
              affected set only; `hardfork` from the tips):
              ~-70% per pull
            - fix 2 (f271bee): `hardfork` 0.18-0.20 -> 0.03-0.04
              s; pull 0.73-0.76 s at 2,950 actions
            - fix 1 (staged, installed 17:04): pull 0.49-0.51 s,
              nothing new 0.17 s; post 0.22 s
            - chat 5k died at 2,951 (reinstall mid-run, `logs/
              chat-5k-tree-died-2951.log`); usenet 5k stopped at 7
              (`logs/usenet-5k-fix2-stopped.log`)
        - [ ] chat 5k, then usenet 5k, with fix 1 + fix 2
          (started 26/10/07 ~17:10)
            - post / sync (ff pull) avg per 250 actions, fixed
              vs unfixed tree run:
                - 250: 0.168 / 0.34 vs 0.176 / 0.36
                - 500: 0.198 / 0.47 vs 0.189 / 0.51
                - 1,000: 0.189 / 0.51 vs 0.190 / 0.76
                - 1,500: 0.203 / 0.60 vs 0.204 / 0.89
                - 2,000: 0.205 / 0.64 vs 0.195 / 1.01
                - 2,500: 0.197 / 0.59 vs ~0.196 / 1.09
            - posts flat ~0.20 s; sync ~0.5-0.6 s, about half
              the unfixed (sync ~2.4-3x a post)
            - elapsed at 2,500: 15,394 s (unfixed ~22,500);
              ~7.3 s per action at 2,400; forks 24 (1.0%)
            - sweeps per peer: 18 s (500), 3 s (1,000), 23 s
              (1,500), 27 s (2,000), 18 s (2,500); peer 1.4 ->
              6.3 MB
        - [ ] compare with tree-trash (state as git tree), but
          it may lack the order fix of `261006-bug-winner`
- [ ] per-tier N (supers fast, leaves slow): only if asked
- [x] recalibrated with U(0, N) (26/10/06): adhd 59 s,
  github 68 s, wiki 22 s, usenet 13 s, se-veg 3.1 min (chat
  1.6 s, but chat stays N = 0); spread 0.5-7 min
- [x] simple test with push (`T.relay` 1800, 3600 gaps):
  PASS in 109 s (`p2p/logs/push-1.log`)
    - forks 6 of 20 (30%; model 25-31%), 6 merges in DAG
    - pulls 1,133 for 20 actions (~57 each: no wasted pulls)
    - syncs ff 0.11-0.33 s, mg 0.32-0.44 s; posts ~0.12 s
    - same `list order` on all 59, `reps` match (18 authors)
    - build `261006-bug-winner`: no order divergence here

# Partitions (scheduled)

- cut 2-3 mids from their supers: each mid + its
  single-homed leaves is an island (e.g. M1, M5, M9);
  dual-homed leaves fall back to their other mid; without
  sibling links each single-homed leaf is cut off alone
- durations: 1 day (< `time.fork`) | 8 days (> `time.fork`:
  hard forks and recovery cost on reconnect)
- contrast: one super down partitions nothing (every mid has
  a second super)
- plus one case: two neighbouring supers down (cuts the mids
  that depend only on them)
- metrics (eval item 14): hard forks; voided actions on merge;
  reps changes on merge; stalled welcomes (gated); revokes
  delayed across the cut; merge cost on reconnection

# Churn: peers going on and off (26/10/07, decided)

- REPLACES "all leaves always online"; earlier runs stay as
  always-online baselines
- sources: P2P sessions and downtimes are heavy-tailed, median
  sessions minutes to ~1 h (Stutzbach, Rejaie: Gnutella,
  BitTorrent, Kad); fediverse servers 94-100% uptime (best
  Mastodon 97.6%, Pleroma 99.1%); Bitcoin daily retention
  > 90%
- per tier (heavy-tailed draws, seeded):
    - S: 90% online; outages ~2 h (up ~18 h between); NO
      limit on how many are down at once (26/10/07; the
      earlier "at most 2, never neighbours" rule dropped)
    - M: 80% online (a stress test, below measured servers);
      outages ~2 h (up ~8 h between)
    - L: sessions median ~1 h, offline median ~8 h (~10-20%
      online)
- backup links (26/10/07): used ONLY while the primary uplink
  is down, and then in both directions
    - a leaf: uplink = its own M; uses its second M only while
      its own M is offline (that M also pushes to it)
    - an M: uplinks = its 2 S; uses its 2 ring neighbours only
      while BOTH its S are offline
    - S-S always on
    - normal operation: 73 primary links (mean path 3.6,
      diameter 5); all 122: mean 3.0, diameter 5
- why the core stays connected (checked offline, 26/10/07):
    - any 2 or any 3 S down (M, L up): 10/10 and 10/10
      combinations fully connected, via the M ring backups
    - random S 90% (no limit) + M 80%, 20k samples: an M or S
      cut off 0.3% of the time (a M's 2 S and both ring
      neighbours down at once)
    - leaves cut off only while their M(s) are down: a
      single-homed leaf (5 odd-fan middles) 67% of the time
      some is cut off, a dual-homed leaf 27% (L always up;
      L are online only ~10-20%, so less in practice)
- rules:
    - offline peers neither send nor receive (pushes skip
      them; their timers wait)
    - on reconnect: pull at once from online neighbours
    - a posting author's leaf comes online, catches up, then
      posts (no stale posts)
    - no hard forks: outages last hours, far below
      `time.fork` (7 days); cut-off leaves catch up when their
      M returns
- metrics: staleness of returning leaves; catch-up cost;
  forks from reconnects; skipped pushes; catch-up load on mids

# Topology changes for churn (26/10/07, decided)

- M-M ring: each M also links to its two angular neighbours
  (M01 M06 M02 M07 M03 M08 M04 M09 M05, back to M01): +9 links
- leaves: in each fan, HALF also link to the LEFT neighbour M,
  the other half to the RIGHT one; odd fans (M01, M03, M05,
  M07, M09): the middle leaf links only to its own M
    - today: only the 2 edge leaves of each fan (17 cross
      links); 28 leaves single-homed
    - new: 40 dual-homed, 5 single-homed (middles of odd fans)
- links: 10 S-S + 18 S-M + 9 M-M + 45 L-own M + 40 L-other M =
  122 (was 90)
- an M down: its dual-homed leaves fall back to the other
  M; the middle leaf of an odd fan is cut off while it is down;
  two neighbouring M down: their shared leaves are cut off for
  the outage (hours)

# Asymmetric topology (26/10/07, decided: A, B, C)

- A. fan sizes heavy-tailed: M1 15, M2 8, M3 6, M4 5, M5 4,
  M6 3, M7 2, M8 1, M9 1 (45); around the ring (M1 M6 M2 M7 M3
  M8 M4 M9 M5): 15 3 8 2 6 1 5 1 4, big and small alternate
- B. supers per mid uneven (18 in all): M1-M3 on their 3
  nearest S, M4-M6 on 2, M7-M9 on 1
    - M1: S1 S2 S5; M2: S2 S3 S1; M3: S3 S4 S2; M4: S5 S4;
      M5: S1 S5; M6: S2 S1; M7: S3; M8: S4; M9: S5
- C. core: S ring + chords S1-S3, S1-S4 (7 links, was 10)
- kept: M ring (backup), leaf backups half left / half right,
  odd-fan middles single (5 single-homed, 40 dual-homed)
- links: 7 + 18 + 9 + 45 + 40 = 119 (primary 70)
- paths: primary only diameter 6, mean 3.40; all links
  diameter 5, mean 2.88 (symmetric: 5 / 3.59 and 5 / 2.98)
- checked offline (26/10/07):
    - any 1, 2 or 3 S down (M, L up): all combinations fully
      connected (mids on 3 S bridge the thinner core)
    - random S 90% / M 80%: an S or M cut off 1.3% of the
      time (symmetric: 0.3%); outages last hours: short
      partitions, no hard forks
- diagram: `p2p/hubs50.dia` (leaves 01-45; two rows for M1's
  15); M3-S2 is drawn over the S2-S3 core link
- supersedes the 1..9 fans, the even M-S wiring and the full
  core in Topology / Topology changes for churn (122 links)

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
    - [x] fork metric: `miss` = earlier actions the author
      lacks when posting (> 0: fork); forks every 10 and at
      END, plus merge commits in the final DAG
        - schedule-only (holders), so mock = real: K = 10,
          20 actions, SEED 1 -> 5 forks (25%)
        - [x] calibrate K (mock, 200 actions, seeds 1-3):
            - K=6 97%, 8 83%, 9 60%, 10 16%, 11 4%, 12+ 0%
            - threshold: 6K lane slots vs 58 pulls per action;
              K < 10 backlog grows, K >= 12 always converges
            - K = 10 (16%): NOT comparable to tpd-21 (no
              time there, no sync rule here yet)
        - [x] real run, K = 10, 20 actions: 5 forks (25%) =
          mock; 5 merges in DAG; PASS
          (`p2p/logs/waves-fork.log`)
        - corpus: K varies with the gap -> bursts fork, quiet
          spells do not; calibrate D on the 5k slice
            - reconfirmed on fresh `main` install (26/10/06):
              p2p 3 of 58 differ (`p2p/logs/waves-main.log`);
              repro 4 of 6 attempts diverge
        - old loop PASSed (k = 10): likely luck, same risk
        - user rerun: identical (same 4 peers): fixed repro
          for the upstream fix
        - sync growth: ff avg 0.10-0.13 s up to act 11, 0.25
          s at act 12 (first merges), 0.41 s at act 20
            - [ ] superseded: see Next steps 2 (sync
              slowdown with many forks)
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
- [ ] 59 peers, 5k slice (Next steps 7)
- [ ] 59 peers, full `adhd` (Next steps 8)
- [ ] partitions: 2-3 mids x 1 day | 8 days (Next steps 9)
    - 8 days: hard forks expected -> count them, not abort
- [ ] later, standalone: small-world, nebula, scale-free
  (larger, alone)

# How to run

- build: freechains tree-trash (3752b78) + bug-winner fix
  (staged, uncommitted) installed 26/10/07 08:25 (`state.lua`
  1,182 lines); before: `261006-bug-winner` (main layout, 89)
    - `--version` says v0.21.0 for every build: check the
      installed `state.lua` (tree-trash: ~1181 lines)
    - lemmy single-peer runs used tree-trash: timings not
      comparable
- ONE run at a time (CPU-bound; timings)
- simple test (artificial posts):
    - `cd p2p && lua5.4 p2p.lua > logs/simple-N.log 2>&1`
    - ~4 min for 20 actions; ends with `== PASS` or `== FAIL`
- knobs: edit `p2p/config.lua` (table `G`, no env), one
  comment per field
    - `MODE`, `N_ACT` (20), `T.action` (3600), `T.relay`
      (1800), `LANES` (6), `SEED` (1), `DUMP`, `ALIAS`,
      `BASE`, `T0`
- `DUMP = true`: print the 108 links and exit
- output lines:
    - `. N Ts  <leaf>-><mid>  [W]  miss=  post=  pulls=  ff[n]=
      mg[n]=  idle=`
        - miss: earlier actions the author lacks (> 0: fork)
        - T: wall secs of this action
        - W: waves of pushes due before this action
        - post: post time (s)
        - pulls: syncs run in this action's waves
        - ff/mg: fast-forward / merge syncs, count and
          min/avg/max secs; none: `-.--/-.--/-.--`
        - counts padded: 2 digits (action), 4 (totals)
        - idle: lane slots left empty (no useful pull)
    - `== N Ts  forks=n (p%)  post=min/avg/max  pulls=  ff[n]=
      mg[n]=  idle=`: totals every 10 actions, blank lines
      around
    - `== END forks=n of N actions (p%)  merges in DAG=m`
    - `== END drain waves=W`: waves of the pending timers
      after the last action; actions not everywhere: abort
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

- 1. [x] fork metric (`miss`, forks, merges in DAG)
- 2. [ ] BLOCKER: sync slowdown with many forks
    - seen: `p2p/logs/tsync-1.log` (ratio 2, ~90% forks):
      act 11 ff avg 1.8 s; act 19 ff avg 72 s, max 136 s;
      act 19 took 693 s
    - oracle runs (few forks): ~0.1-0.4 s per sync
    - [ ] log syncs per action against forks in the DAG
    - [ ] minimal repro: N concurrent posts, merged, time
      one `sync recv` as N grows
    - [ ] same repro on `main` vs `261006-bug-winner`: did
      the fix add the cost (state reads per inner fork)?
    - [ ] if confirmed: plan in the freechains repo
- 3. [x] sync rule: push with relay delay N (see Sync rule)
    - [x] `p2p.lua` rewritten: timers in chain time, keep
    - [x] simple test with push: PASS (see Sync rule)
    - [ ] polling (blind) only as a contrast, if asked
- 4. [x] corpus gaps: all six measured on this machine (see
  Sync rule)
- 5. [ ] MODE=corpus in `p2p.lua`
    - input: a `lemmy-events.py` TSV (`SRC`, as
      `lemmy-simple.lua`)
    - T.action per action = real gap to the next event;
      `T.relay` = N per corpus (chat 0)
    - authors placed uniformly on the 45 leaves (sticky,
      `SEED`); moderators too
    - kinds as `lemmy-simple.lua`: post, remove (revoke
      `--why`), restore (unrevoke `--file`), delete (free
      self-revoke); ban/addmod counted only
    - final drain until every peer holds every action
    - sweep every WINDOW actions on every peer (in waves)
- 6. [ ] smoke: `adhd` first 500 events, mock first (forks),
  then real
- 7. [ ] 5k slice: forks at N (expect ~15%), plus an N
  sweep (mock)
- 8. [ ] full `adhd` (time depends on step 2)
- 9. [ ] partitions: cut M01, M05, M09 for 1 day, then 8
  days; hard forks counted, not aborted
- 10. [ ] results: `p2p/RESULTS.md` (forks by N per corpus;
  chat instantaneous)

- next (26/10/07): churn
    - [ ] `topo.lua`: asymmetric topology (A, B, C; 119
      links), names S1-S5, M1-M9, L01-L45
    - [x] redraw `hubs50.dia` (26/10/07): asymmetric (119
      links), names S1-S5, M1-M9, leaves 01-45 (code: L01-L45)
    - [ ] `p2p.lua`: on/off schedule per tier (seeded), skip
      offline peers, catch-up pulls on reconnect, author's leaf
      online + catch-up before posting; backup links only while
      the primary uplink is down (both directions)
    - [ ] simple test with churn; then corpus runs

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
- offline leaves from the data's sessions (churn uses tier
  numbers instead, see Churn)
- sibling (leaf-leaf) links: no measurable effect under push
