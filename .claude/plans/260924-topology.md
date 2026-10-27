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
    - extended to all years (26/10/08): usenet 5k forks
      jumped at 1989-90 (2 -> 120 at 500-1000), runs of
      authors ~1 min apart; comp.compilers is moderated
      throughout -> 1,921 batches, 12,588 msgs; first 5k
      gaps <= 60 s: 158 -> 0, <= 5 min: 409 -> 6
        - `data/usenet.tsv` replaced after the running
          usenet 5k (raw pre-2000 batches baseline)
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
- kept: M ring (backup)
- fewer leaf backups (26/10/07): per fan, the middle third
  (rounded down) single-homed; the rest split left / right
  (odd one left)
    - M1 15: 5 / 5 / 5; M2 8: 2 / 3 / 3; M3 6: 2 / 2 / 2;
      M4 5: 1 / 2 / 2; M5 4: 1 / 2 / 1; M6 3: 1 / 1 / 1;
      M7 2: 0 / 1 / 1; M8, M9 1: 0 / 1 / 0 (single / left /
      right)
    - 12 single-homed, 33 dual-homed (was 5 / 40)
    - with M 80%: ~3.7 of 45 leaves cut off on average (was
      ~2.6)
- links: 7 + 18 + 9 + 45 + 33 = 112 (primary 70)
- paths: primary only diameter 6, mean 3.40; all links
  diameter 5, mean 2.91 (symmetric: 5 / 3.59 and 5 / 2.98)
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

- next (26/10/08): optim and new topology
    - [ ] new sync optim build: post and sync time against
      the current chat 5k run (fix 2 + fix 1)
    - [ ] decide which freechains build to keep
    - [ ] rerun the runs on the asymmetric topology (needs
      `topo.lua`)
    - [x] END check `reps` at chain time (`--now` = last
      action + relay): wall clock took 22 s per call (590
      calls, ~3.4 h), folding 16 years of daily slots
      (4,295 of 5,000 chat posts still queued)
    - [ ] tick build (freechains 26/10/08, tree-trash port):
      global chain clock replaces the per-member settle queue
        - rerun chat 5k: reps no longer queue (4,295 of 5,000
          before), far `--now` cheap
        - install only after usenet 5k ends
        - [x] chat 5k tick: PASS, 23,210 s (old 51,585 s),
          forks 57 (same), post 0.09 s (old 0.20), pull 0.36 s
          (old 0.64), max pull 0.91 s (old 3.30), peer 11 MB
          (old 13), END check 30 s (old ~3.4 h)
            - kept S01/L58: same head a2a5a727, 5058 commits,
              57 merges; reps a1 24000, a2 18000 on both
            - `reps` at wall clock: 0.03 s (old 22 s)
        - [x] usenet 5k tick (batch spread all years): PASS,
          36,454 s (old 53,063 s), forks 0 (old 174), post
          0.09 s (old 0.19), pull 0.45 s (old 0.67), max pull
          1.84 s (old 3.63), peer 20 MB (old 22), sweep 51 s
          (old 56; slower mid-run)
            - kept S01/L58: same head a248adb1e, 5001 commits,
              0 merges, 5000 in order; reps a1 50000, a2 2000
        - speedup shrinks with chain size (1.9x -> 1.3x per
          500): pull cost still grows ~0.03 s per 500 actions
        - done (26/10/09 15:24): chat 5k then usenet 5k
          (new `usenet.tsv`); old logs `*-5k-fix12.log`
        - evidence: two peers (p00 = S01, p58 = L58) kept in
          `p2p/.freechains-keep/<corpus>-<build>/` (+ keys);
          usenet-fix12 kept; chat-fix12 already wiped;
          chat-tick, usenet-tick copied at each PASS/FAIL
    - [ ] usenet: regenerate `data/usenet.tsv` (batch spread
      all years) after the running 5k; rerun usenet 5k
    - [x] usenet 5k (fix 2 + fix 1, pre-2000 batches raw):
      PASS, 53,063 s, forks 174 (3.5%, mostly 1989-90
      batches), post 0.19 s, pull 0.67 s (medians); END
      check 91 s (short reps queues)
    - [x] chat 5k (fix 2 + fix 1): PASS, 51,585 s, forks 57
      (1.1%), post 0.20 s, pull 0.64 s (medians)

- next (26/10/07): churn
    - [x] `topo.lua`: asymmetric topology (A, B, C; 112
      links), names S1-S5, M1-M9, L01-L45 (26/10/09)
        - generated from asym.py: 70 primary (7 SS, 18 SM,
          45 LM) push; 42 backup in `_bk` (9 MM, 33 LX), kept
          in `BKUP`, unused until churn
        - `p2p.lua`: names, BKUP, DUMP lists `MM*`/`LX*`;
          primary graph connected (59 of 59)
        - [x] simple test: PASS, 45% forks (old topo 25-31%:
          diameter 6 vs 5)
        - [x] chat 5k relay 0: stopped at 1284 (26/10/09),
          same as old topology (forks 15 at 1280, both; time
          per 500 within 4%); log `chat-5k-asym-r0-stopped.log`
        - relay as U(min, max) (26/10/09): chat 1-2 s
          (latency), usenet 1-60 s; tick = max(1, max // 10)
        - chat 5k 1-2 s: stopped at 578 for a 2k limit;
          at 500: forks 6.4% (relay 0: 1.2%), merges 44,
          waves/act 12.6 (11.9), pulls/act 55 (57)
        - [x] chat 2k 1-5 s: PASS, 7,553 s (relay 0: 6,677 s
          at 2k, +13%), forks 480 (24%), merges in DAG 492,
          merge pulls 589 (0.43 s), drain 26 waves (11),
          pulls/act 51 (58), peer 4.4 MB (4.0); kept S1/L45:
          head cd04ec18, 2493 commits, 492 merges
        - [ ] chat 2k 1-2 s: killed at 1992 (26/10/10, low
          memory: browser ~6 GB); at 1500: forks 139 (9.3%),
          merges 171 (0.38 s), +9% time vs relay 0; no END;
          log `chat-2k-r12-killed-1992.log`; rerun
        - [x] chat 2k 1-2 s rerun: PASS, 7,135 s (+6% vs
          relay 0), forks 198 (9.9%), merges in DAG 199, merge
          pulls 237 (0.39 s), drain 23 waves, pulls/act 56;
          same numbers as the killed run (seeded); kept S1/L45:
          head 29b31e67, 2200 commits, 199 merges
        - fork curve, chat 2k: relay 0 1.1%, 1-2 s 9.9%, 1-5 s
          24.0%; time +0 / +6 / +13%
        - [x] usenet 5k 1-60 s: PASS, 34,900 s (old topo
          0-60 s: 36,454 s, -4%), forks 0 (same), post 0.08 s,
          pull 0.42 s (0.45), max pull 1.12 s (1.84), drain 15
          waves (18), peer 19 MB (20); kept S1/L45: head
          fb89d58c5, 5001 commits, 0 merges
        - [ ] local first (26/10/10): open chain (no reps
          budget); `G.SYNC` per link kind: SM 6 h, LM 24 h,
          SS always; seeded phases per mid/leaf; posts on the
          leaf anytime; deferred pulls at sessions; new END
          metric: visibility (post -> all peers)
            - simple: off = old (9 forks, PASS); on: 19/20
              forks, visibility median 44 h, max 54 h, PASS
            - usenet 5k stopped at 843 (26/10/10): pulls grew
              0.5 s -> 35 s (merges 103 s) after ~800; forks
              68%; DAG 1540 commits, 699 merges; log
              `usenet-5k-lf-stopped-843.log`
            - profile (one pull, 852 s under hooks): git 2 s;
              `ACTION.backs` (action.lua:188) 848 s, inner
              `rec` 24.7M calls / 39 calls: visited set only
              marks actions, so sync merges are re-walked per
              path (exponential in merge depth)
            - fix (checked on a patched copy): mark every
              visited node; pull 115 s -> 2.75 s; same head,
              order, refs, reps
            - [x] fix upstream (freechains, plan 261010-backs),
              installed 26/10/11 00:22
            - [ ] rerun usenet 5k local first (running since
              26/10/11): log `usenet-5k-lf`
                - @1000: fix holds; max pull 3.9 s (was 21 s
                  @840); 72% forks; 8836 s per 500 (growing)
                - @1500: 80% forks, 1930 merges; max pull 4.0 s;
                  10811 s per 500; ff median 0.57 s
                - stopped @1885 (log `-backs-stopped-1885`):
                  1 pull per wave (random phases), pulls 1-2 s
                  (~60% git process start-ups, freechains plan
                  ia-optim `261011-git-batch`)
            - [x] `SLOT` (config): phases on whole hours, so
              sessions share waves (lanes)
            - [x] rerun usenet 5k local first with `SLOT`
              (26/10/11 09:00 - 22:40): PASS; log
              `usenet-5k-lf-slot`, kept S1/L45 (72 MB)
              @10 26 s (was 73 s)
                - git-batch build (031c070) installed 10:12, at
                  ~action 400: same results, pulls 10-30% faster
                - @500: 2953 s (was 6258 s, 2.1x); 58% forks;
                  2.06 pulls/wave (was 1.03)
                - vs always-on @500 (1.7x): sim, not freechains;
                  pull work ~5.6k s vs ~5.8k s, run at once 1.9
                  vs 3.2
                - @1000: 6802 s (was 15094 s, 2.2x); 71% forks;
                  work ~13.3k s (always-on ~12.8k), par 1.95
                  (always-on 3.27, no slots 1.0)
                - @1500: 11443 s (was 25905 s, 2.3x); 79% forks;
                  work ~22.6k s (always-on ~21.0k), par 1.97;
                  ff avg 0.49 s, max 7.0 s (growing)
                - @2000: 15723 s (always-on 9124 s, 1.7x); 82%
                  forks; 2883 merges; work ~31.2k s (always-on
                  ~30.3k), par 1.99; 4280 s per 500 (was 4641);
                  max pull still 7.0 s; peer 8.7 MB (7.1)
                - @2500: 20490 s (always-on 12263 s, 1.7x); 85%
                  forks; 3780 merges; work ~41.2k s (always-on
                  ~40.8k), par 2.01; 4767 s per 500; peer 12 MB
                  (9.0)
                - @3000: 25168 s (always-on 15814 s, 1.6x); 87%
                  forks; 4670 merges; work ~51.0k s (always-on
                  ~52.4k, now lower); par 2.02; 4678 s per 500
                  (always-on 3551); peer 14 MB (11)
                - @3500: 30439 s (always-on 19805 s, 1.5x); 88%
                  forks; 5606 merges; work ~62.1k s (always-on
                  ~67.3k, -8%); par 2.04; 5271 s per 500
                  (always-on 3991); peer 17 MB (13)
                - @4000: 35643 s (always-on 24372 s, 1.46x); 90%
                  forks; 6542 merges; work ~72.9k s (always-on
                  ~83.8k, -13%); par 2.05; 5204 s per 500
                  (always-on 4567); peer 19 MB (15)
                - @4500: 40865 s (always-on 29372 s, 1.39x); 90%
                  forks; 7474 merges; work ~84.3k s (always-on
                  ~102.1k, -17%); par 2.06; 5222 s per 500
                  (always-on 5000); peer 22 MB (17)
                - END: PASS (0 of 58 peers differ, 0 reps
                  mismatches); 46915 s (always-on 34900 s,
                  1.34x); 91% forks; 6492 merges in DAG; work
                  ~97.0k s (always-on ~122.2k, -21%); par 2.07
                  (3.50); peer 24 MB (19); visibility median
                  43.5 h, p90 51.7 h, max 58 h
                - fix: run-lf.sh restore sed (`*` in pattern)
            - evidence, post hoc on kept S1/L45 copies (scratch
              `ev/`; keep dirs untouched):
                - same `list order` on S1 and L45 (md5 d30f3a6c)
                - declared times = corpus times (5000)
                - clamps (P_i > S_i): 2738 of 5000 (54.8%); P-S
                  median 11.6 h, p90 29.5 h, max 51.5 h; 523 >
                  24 h, 3 > 48 h, 0 > 7 d; always-on r160: 0
                - all queries: `p2p/ev/ev.sh <run> <now>`
                - reorders per merge (`p2p/ev/reorders.py`): order at
                  M vs each parent, moved = outside the common
                  prefix; only merges with snapshots at M, p1, p2
                  (2385 of 6492 on S1; 1460 of 6492 on L45; same
                  final DAG, head 4897248d; first S1 query ran on
                  a stale head after a crash: redone, scripts now
                  restore `main` at exit)
                    - parent 1 never moves (winner first); the
                      loser moves in 99.3% of merges
                    - moved per merge: mean 3.4, median 2, p90 8,
                      max 21 (same on S1 and L45)
                    - 29% of merges also reorder inside the loser
                      (nested forks re-sorted)
                    - bias: only merges with stored snapshots
                - blocked (old paper d), counterfactual rule 4.a
                  on the open chain (`p2p/ev/blocked.py`): author
                  reps at the post's parent, at post time
                    - 5000 posts: 2617 first posts (welcome), 261
                      unknown (parent without snapshot)
                    - others 2122: blocked 10 (0.47%) with no
                      welcome reps; 8 (0.38%) with W=500; 0 with
                      W=1000 (old paper: 3.5%)
            - [x] report line: `work` (summed post + pull times)
              and `par` (work / elapsed); next runs only
        - [ ] full usenet run (26/10/12): 33814 actions, lf-slot,
          build ia-optim 175f19e; log `usenet-full-lf-slot`
            - [x] env KEEP=<run>: copies S1/L45 every 5k to
              `.freechains-keep/<run>-<a>k`; ev.sh every 10k
              (log `ev-<run>-<a>k.log`; mid-run orders differ)
            - [x] END: commits and bytes per pull, pulls per
              peer by tier (received, served)
            - [x] smoke test 30 actions: PASS
            - [x] stopped (26/10/13) at 8796: ~9.3 d predicted,
              pulls 0.8 -> 2.1 s; keep `usenet-full-lf-slot`
            - cause: merge replay grows with DAG width (80-120
              nearest actions per merge); 98% merges are real
            - git ranges wrong (merge dates 0): false `voided`
            - fixes: freechains `261013-merge-cost.md` (main)
            - [x] byte counter: `--topo-order` in `p2p.lua`
              (30-action smoke: PASS)
            - [x] config: SYNC restore dropped the comma; fixed,
              run scripts now match `{...}` only
            - [x] freechains fixes A-D in ia-optim: tests pass;
              1 merge at 8k 1.1 -> 0.65 s; big pulls -30%
            - [ ] rerun full after the fix is installed
        - [ ] usenet 2k x 3 policies (26/10/13, build 5ebae95):
          always on (ao), sync/post/re-sync (ps), local first (lf)
            - [x] PRESYNC: leaf pulls its primary mid before a post,
              the mid pulls the post after (env PRESYNC=1)
            - [x] env overrides: LIMIT, SM, LM, PRESYNC
            - [x] END: time per pull, per received commit and
              action; actions per pull; commits per action
            - [x] smoke 30: ps 20% forks (lf 66%), PASS
            - expected forks ~ posts with another author's post in
              the staleness window: 1 h 12%, 6 h 48%, 24 h 81%
            - [x] ao: 0% forks, 116k pulls, 0.265 s per commit and
              per action, total pull time 30.7 ks, PASS
            - [x] ps: 42% forks, 0.43 merges per post, 59k pulls,
              0.113 s per commit, 0.163 s per action, 18.9 ks
              (-38% vs ao), PASS
            - [ ] lf: HARD FORK at action 405 (pull L04 <- M1,
              1989-04-12); all peers kept in
              `usenet-2k-lf-hardfork` (2 GB)
                - same action set on both sides; L04 has only extra
                  merges; orders differ at 401 of 405 (e4e3f4a4
                  vs 7647da91, posted 03-30 / 03-31)
                - order depends on merge structure, not only on the
                  action set; settle age is chain time, and sparse
                  posting (8 days, 4 posts) makes the 4th-last
                  action 182.9 h old > 168 h
                - old build (175f19e) also hard-forks on this state;
                  its own 5k run took a different DAG and passed
                - decision pending: settle age from receipt time, or
                  order invariant to merge structure
                - `useful` (`p2p.lua:274`) skips merge-only pulls:
                  divergent orders never reconcile in the sims
                - plan: freechains `261014-merge-order.md` (main);
                  failing test `tst/hardfork-merges.lua` (ia-optim)
                - [x] `MERGES=1` (26/10/14): `useful` also pulls an
                  unseen source HEAD; END counts merge-only pulls
                - [x] smoke lf 30: PASS with and without, same
                  1085 pulls (merge-only 0: no drift in 30)
                - [x] lf 2k with `MERGES=1` (`usenet-2k-lf-mg`):
                  PASS; 82% forks, 2240 merges, 437 merge-only
                  pulls; 56.7k pulls, 0.48 s mean; 0.111 s per
                  commit, 0.236 s per action, 2.14 commits per
                  action; 27.4 ks; 83.8 MB; 4 h 01 min
        - [ ] mixed classes for the full run (26/10/14, `MIX=1`):
          each mid and its leaves share one class
            - on: M1 M3 M9 (22 leaves), mids and leaves always on
            - ps: M2 M6 M8 (12), 6 h / 24 h + sync around posts
            - lf: M4 M5 M7 (11), 6 h / 24 h sessions only
            - M4, M6 swapped (M1 had only lf ring neighbours)
            - figure: `p2p/hubs50.dia` fills green/yellow/red,
              legend line; paper `2606-vcs/imgs/topo.{dia,pdf}`
              recolored, caption updated (`main.tex:1226`)
        - [ ] churn (26/10/14, `CHURN=1`), before the full run
            - seeded outages per peer, own RNG (xorshift)
            - up: supers 99%, always-on mids/leaves 95%, session
              mids 90%; session leaves none (sessions = uptime)
            - downtime Pareto, median 1 h, shape 1.5, cap 3 days
            - pull with an end down: leaf -> backup mid; mid with
              all supers down -> ring mid; else deferred
            - reconnect: pull from every primary neighbour
            - END: downtime per tier, deferred, backup, ring,
              reconnect pulls and commits caught up
            - [x] code; [x] smoke 30 (+MIX, MERGES): PASS; down
              S 1.1%, M 8.5%, L 5.6%; 204 deferred, 76 backup,
              13 ring, 101 reconnect pulls; [ ] full run
            - [x] 2k (+MIX, MERGES) crashed at 1001: freechains
              bug, `winner` peeks a deferred floor snapshot
              ("no snapshot"); fixed in ia-optim (`flush()` in
              `sync.lua`), test `tst/bug-floor-snapshot.lua`,
              47/47 suites + guide.sh pass
            - [x] reinstalled (= ia-optim + fix), crash pull rc=0
            - [x] rerun 2k (26/10/14, 3 h 56 min): PASS, forks
              44%, merges 728, 82.9k pulls, 0.168 s per commit,
              0.231 s per action, 1.37 commits per action, 67 MB
                - on 32%, ps 43%, lf 67% forks; visibility median
                  100 / 107 / 133 ks
                - down S 1.1%, M 8.2%, L 5.0%; 9091 deferred, 3327
                  backup (4.0%), 131 ring (0.2%), 4415 reconnect
                  pulls (commits median 1, max 33)
                - merge-only pulls 767
            - [ ] full run `usenet-full-mix-churn` (started
              26/10/15 00:20; keeps every 5k, ev every 10k)
                - stopped at 3431 (26/10/15): forks 51%; restart
                  on the new build (canonical merge + fetch fix)
                - old log `logs/usenet-full-mix-churn-stopped-3431.log`
                - [ ] restarted 26/10/15 on ia-optim + hideRefs +
                  negotiation tip; `logs/usenet-full-mix-churn.log`
                - killed at 20896 (26/10/17, 39 h): low memory,
                  reaped by Claude Code; forks 70%, ff median 0.39;
                  kept 5k-20k; plan 261017-resume, then restart
                - [x] r2 started 26/10/17 (user terminal, EV_N=0,
                  ckpt every 5k): `logs/usenet-full-mix-churn-r2.log`
                - r2 done 26/10/21 01:15 (88.5 h): PASS, 0 of 58
                  peers differ, reps 0 mismatches
                    - forks 66% (on 55%, ps 67%, lf 89%)
                    - visibility median 29 h, p90 44 h, max 8.4 d
                      (on 27.7 h, ps 29.8 h, lf 36.8 h)
                    - pull median 0.47 s, p90 1.14, max 10.3;
                      per commit 0.23 s; 1.18 GB in total
                    - down S 1.0%, M 8.3%, L 5.0%; deferred
                      106603, backup 30098, ring 991
                    - s/action 5.5 (0-5k) -> 18.5 (33k)
                    - kept 5k-30k + `r2-final` (copied after end)
                - [ ] ev.sh on r2-final, 30k..5k (sequential,
                  detached, started 26/10/21 08:42):
                  `logs/ev-usenet-full-mix-churn-r2-*.log`
                    - final: same order, clamps 31.0%
                    - reboot (26/10/21-22) killed it in reorders.py
                      (p00, 5.9 GB): reorders/blocked lost
                - [ ] bytes per pull count commits only (`p2p.lua`
                  240, objects of `ht..hn`): payloads go through
                  `refs/payloads`, not counted; a post commit is
                  510 B (empty tree), body median ~1.4 KB
                    - fix: add the payload objects fetched per pull
                    - r2 (no rerun): estimate from the corpus,
                      bodies of each pull's commits
                - blocked at 10k (killed run's copy, 379 s): W=0
                  1.53%, W=500 1.45%, W=1000 0.10% (old paper
                  3.5%); `ev/usenet-full-mix-churn-10k.blocked`
                - blocked on r2-final (paper number, 1312 s): later
                  posts 20547, W=0 1.24%, W=500 1.15%, W=1000
                  0.08%; blocked reps -500 for 220 of 255; unknown
                  1012 (3%, merge parent); file
                  `ev/usenet-full-mix-churn-r2-final.blocked`
                - half reward (+500, replay estimate at 10k, ref
                  only): W=0 ~2.3%, W=500 ~1.7%
            - [ ] usenet authors are addresses, not people (26/10/22):
              12,539 addresses; merge rules agreed:
                - always: lower-case, strip `.uucp` (12,334)
                - full name (2+ words, `From:`) + same domain
                - domain: uucp path -> host before the user;
                  else label before the TLD; `xx.ac.uk`-like +1;
                  `*.oz.au`, `*.xx.us` one deeper
                - 1-word names never merge ("john", "chris")
                - free-mail and role addresses merge by the rule
                - result: 11,348 authors (use-events.py)
                - paper: "33,814 posts from 11,348 authors"; r2
                  kept as is (addresses = authors in the run)
                - [x] apply in `usenet/use-events.py` (`author`,
                  `domain`); dry run: same ts/ids, only users
                - [x] regenerate `data/usenet.tsv` (keep the r2
                  input as `data/usenet-r2.tsv`): same ts/ids
                - 1255 posts stop being an author's first post
                - blocked, merged authors (replay x measured, no
                  rerun): W=0 ~1.0%, W=500 ~0.94%, W=1000 ~0.07%
                  (replay r2 tick starts: addresses 1.39%, merged
                  1.14% at W=500)
                - [ ] optional: 5k run with merged authors (~8 h)
                  to check forks unchanged
            - r2 report for the paper (26/10/22): build ia-optim
              ab304a9 (installed 15/10 16:08:55, files = worktree)
                - storage S1: gc'd 154 MB; snapshots 96 MB, payloads
                  ~35, commits 14, idx/refs ~26; no payloads
                  115-119 MB (S/M/L); mbox 85 MB raw, 30 MB gzip
                - paper: storage goes to the synthetic subsection
                - [x] reorders: sample 400 of 6517 usable merges
                  (full set ~7 d), seed 1, 8782 s, scratch copy
                    - loser moves in 397 (99.3%), winner never
                    - moved per merge: mean 2.5, median 1, p90 6,
                      max 18 (1013 total)
                    - 10.5% also reorder inside the loser
                - [ ] reorders over all 6517 (paper request):
                  running (26/10/26, PID 387168, ~40 h), scratch
                  `tmp.0d3XDgzgwI/p00.reorders-all`
                    - L45 won't do: same DAG, same answer; only 41
                      extra merges
                    - slow: 125 merges in 3.9 h (newest first,
                      shares the machine with the chat run): 2-4 d
                - [x] storage breakdown (paper request, 26/10/26):
                  sent; r2 S1 as kept: disk 142 MB, payloads 32,
                  commits 14, snapshots 96 (68%), 4.4x; gc'd L45:
                  122 MB objects, du 157 MB (= paper's 154: du of
                  gc'd repo, incl. idx 14 + packed-refs 7); chat
                  5k: 6.4 MB, 21x; chat 20k: 28 MB, 28x
                    - script `scratchpad/storage.sh`
                - [x] common rows (paper request, 26/10/26): sent
                    - post time r2 0.09/0.13/0.42, chat 5k
                      0.08/0.11/0.20 (median/p90/max)
                    - r2 per 5k: ff mean 0.26 -> 1.04 s, max 1.9
                      -> 10.3 s (exact mean/max; no per-slice
                      median, commits, bytes in the r2 log)
                    - gc'd chat = as kept (swept every 500)
                    - voided per merge: not counted by the driver
                - [ ] gc'd storage per r2 keep (5k..30k, final):
                  after the reorders run
                - [ ] r2 had the backup bug too (30,098 backup
                  routes): rerun (~88 h)?
                - [x] merges (paper request): 16,276, all with 2
                  parents; commits per side since merge base:
                  long 4/16/90, short 1/2/11, both 5/17/91
                  (median/p90/max)
                - [ ] check: ps and lf share per-commit/per-action
                  costs (0.128/0.191 s): per-class accounting bug?
                - [ ] check: visibility max 8.4 d > 7-day window,
                  no hard fork: which post/peer
                - deliveries 1,961,292 vs 33,814 x 58 (+80): minor
                - always-on baseline: no full run on this build
                - reps at the end (S1 head snapshot, 26/10/23):
                  12,539 members, total 28.8M; min 500 (pending
                  refund), median 1000, mean 2294, p90 4000, max
                  50,000 (cap)
                    - post-only open chain: reps = 1000 per tick
                      with a post; 94% of authors: 1000 per post
                    - cap binds for 39 authors (52-355 posts);
                      top 1% hold 16% of reps vs 26% of posts,
                      top 10% 48% vs 55%
                    - nobody starves: every author >= 500 (one
                      post); blocked posts = bursts in one tick
                - `p2p/ev/reps-authors.tsv` (26/10/23, for the
                  paper session's §4.1 figure): address, posts,
                  posting_days, reps; 12,539 rows
                    - posting_days: replay of the tick rules over
                      the final order (scratch `reps_replay.py`);
                      matches the run: 0 credit, 0 reps mismatches
                    - reps = 1000 x days for all uncapped but one
                      (genew@telus.net, 500: open tick)
                    - Lorenz (by reps; ties in file order) top
                      1/5/10/25/50%: reps 16.0/36.2/47.5/64.5/78.2,
                      posts 25.4/44.1/54.3/69.3/81.2
                    - merged (11,348, estimate on the same ticks):
                      reps 15.9/37.5/49.3/66.3/80.0, posts
                      26.3/46.1/56.4/71.2/82.9; 43 at cap
            - chat run (26/10/22): all on, CHURN=1, MERGES=1
                - `config.lua`: CORPUS = 'chat'
                - `p2p.lua`: bytes per pull + payloads; final
                  keep `<KEEP>-final` (S1, L45, keys) at END
                - [x] smoke 30 (26/10/22): PASS 86 s; forks 11
                  of 30 (burst at the log start, 46 h); final
                  keep ok; bytes median 533 (with payloads)
                - visibility = slowest peer: under churn some
                  peer is down (median 13 h in the smoke)
                - posts ignore the author's leaf outage (posted
                  offline, pushed at reconnect)
                - [x] chat 5k on churn: PASS (26/10/23 01:39),
                  16,423 s (4.6 h), 08/2010-09/2010; keeps
                  `chat-5k-on-churn-{5k,final}`
                    - forks 2307 (46%), merges 750; visibility
                      median 3.3 h, p90 2.8 d, max 3.0 d
                    - pull median 0.22 s, p90 0.31, max 42 s;
                      commits max 1458 (reconnect); bytes median
                      560, total 173 MB (with payloads)
                    - churn down S 1.0 / M 5.4 / L 5.4%; deferred
                      16,243; backup 370; reconnect 460
                    - served per pull: S 8.2k, M 18.3k, L 5
                    - forks: one run of 1049 consecutive forks,
                      miss 8-9 (925 posts): posts held by a down
                      peer for days fork every later post
                    - cause: L45 down 72 h (the cap) from
                      09-23 15:23; its authors posted 9 times
                      (3215-3237, 3519); reconnect falls in a
                      chat gap (09-25 21:20 - 09-27 18:54), seen
                      at 4264 (58 s, pull 42 s)
                - [x] decided (26/10/23): defer a down leaf's
                  posts to its reconnect (DEFER=1)
                    - `config.lua`: DEFER env; `p2p.lua` ~817:
                      authors placed up front (own RNG), posts
                      moved to reconnect + 1 tick, stable re-sort;
                      END `churn posts: deferred, delay`
                    - smoke 30: PASS, forks 0 (was 11), 6 posts
                      deferred (median 43 min, max 3.7 h)
                - why 3 days: Pareto xm 38 min, shape 1.5; per
                  leaf ~24 outages in 36 d; over 45 leaves expect
                  ~37 > 6 h, ~5 > 1 d, ~1 at the 72 h cap
                - stopped at 207 (26/10/23): chat 5k DEFER=1,
                  `logs/chat-5k-on-churn-defer-stopped.log`
                - [x] bug: `rng()` close seeds gave equal first
                  draws (0.000059): every peer's first outage at
                  t0 + 7 s (r2 too: first hours only); fix:
                  splitmix64 seed scramble (`p2p.lua` rng)
                - fixed schedule, chat 5k leaves: alpha 1.5: 8 >
                  1 d, 3 at the 72 h cap, worst leaf 12.4%; alpha
                  2.5: 0 > 1 d, longest 19 h, worst leaf 7.3%
                - [x] decide alpha: 2.5 (user), restarted
                - [x] chat 5k DEFER=1, alpha 2.5: PASS (26/10/23
                  ~11:40), 15,106 s, log
                  `chat-5k-on-churn-defer.log`, keep
                  `chat-5k-on-churn-defer-final`
                    - forks 993 (19%, was 46%), merges 568 (was 750)
                    - visibility median 1.3 h, p90 7.4 h, max 15 h
                      (was 3.3 h / 2.8 d / 3.0 d)
                    - 272 posts deferred: delay median 54 min, p90
                      5.8 h, max 15 h
                    - down S 1.0 / M 5.6 / L 5.4%; 0 order diffs
                    - leftover forks: leaf up but its mid down, no
                      backup (L27 at 1014-1084: 71 forks)
                - [x] decided (user): DEFER also when the leaf is
                  alone (its primary and backup mids down); a mid
                  cut from supers still serves its leaves: no defer
                    - `p2p.lua` `alone()`, DEFER loop
                    - smoke 30: PASS, forks 0, 3 posts deferred
                - [x] rerun chat 5k DEFER=1 (alone): PASS
                  (26/10/23 ~18:00), 15,103 s, log
                  `chat-5k-on-churn-defer2.log`, keep
                  `chat-5k-on-churn-defer2-{5k,final}`
                    - forks 601 (12%, was 19% / 46%), merges 562
                    - visibility median 1.2 h, p90 7.4 h, max 15 h
                      (unchanged: readers' outages)
                    - 404 posts deferred (was 272): delay median
                      52 min, p90 7.2 h, max 15 h
                    - 0 order diffs; pulls, bytes as before
            - full chat run (155,528 posts, ~3-4 weeks est.):
              stoppable anytime
                - [x] `report()`: END summary also every KEEP_N
                  (`== <a> report ...`), no order check mid-run
                - [x] `config.lua`: KEEP_N env (default 5000)
                - [x] smoke 30, KEEP_N=10: PASS, END unchanged
                - [x] 1st full run stopped at 24,643 (26/10/26):
                  log `logs/chat-full-on-churn-defer-stopped.log`,
                  keeps `chat-full-on-churn-defer-{5..20}k`
                    - forks 13% to 20k, then 241 and 370 per 1000
                      (busy 2011-02-08, 1860 posts in ~11 h)
                    - bug: M2 down, L18 on backup M7: its posts
                      went up, nothing came down (backup mid
                      relayed to primary links only); L18 miss
                      0 -> 266, one fork per post; reset when M2
                      back; 5k runs had it too (backup=307)
                - [x] fix: a backup mid also relays to its leaves
                  whose primary mid is down (`p2p.lua` due, BKOF)
                    - smoke 30: PASS, forks 0, backup 7 -> 29
                - [ ] running (26/10/26 20:30, PID 1286227):
                  KEEP=chat-full-bk LIMIT=155528 MERGES=1
                  CHURN=1 DEFER=1 EV_N=0, log
                  `logs/chat-full-bk.log`
                - [ ] the 5k runs had the bug: rerun 5k? (or use
                  the 5k report of the new full run)
            - scaling test: clone fails past ~1100 posts (fetch
              refspecs past the 128 KB `sh -c` cap); freechains
              plan `261015-fetch-argmax` (main)
            - [ ] scaling test rerun on ia-optim 41a90a6 (canonical
              merge + fetch fix), started 26/10/15; old partial
              log `logs/scale-5ebae95.log`
            - pulls grow with the chain: git's connectivity check
              loads all ~100k refs per fetch; fix `fetch.hideRefs`
              (freechains plan `261015-pull-scale`, both branches)
            - [x] `scale.sh`: warm B up with one pull before timing
              (a never-pulled copy pays a one-off full payload pass)
            - before (41a90a6, cold B): `logs/scale-41a90a6.log`,
              1k-34k (stopped at 57k by the reinstall)
            - [ ] rerun `scale.sh` on the fixed build (hideRefs),
              started 26/10/15 10:16; 34k at 11:50, 100k ETA ~15:00
            - 34k before -> after: noop 1.36 -> 0.13, ff 4.73 ->
              0.50, merge 3.07 -> 0.59 s; clone 703 -> 712 s
              (linear, ~21 ms/post); post 0.08 -> 0.13 s (why?)
            - [x] rerun done 16:02, `logs/scale.log`; 100k: post
              0.135, noop 0.27, ff 1.40, merge 1.49 s, clone 2809 s
              (28 ms/post), repo 271 MB
            - [ ] ff still linear 34k -> 100k (0.50 -> 1.40 s,
              ~14 us/post): profile at 100k
                - [x] profiled: 2 fetches x ~0.5 s = 90% of 1.2 s;
                  each scans all 200k local refs (refs/local +
                  refs/payloads) despite hideRefs: load 80 ms,
                  mark_complete 165 ms, negotiator 150 ms
                - `--negotiation-tip=refs/heads/main`: 0.54 -> 0.39
                - root fix: fewer refs (freechains design)
            - [ ] clone writes snapshots loose: 536k objects,
              3.4 GB mid-clone (A packed: 219 MB)
            - pull time grows (0.22 -> 0.5 s, 0-3k), post flat
              (0.08 s): size or bigger pulls? viability worry
            - [ ] scaling test `p2p/scale.sh` (26/10/15 07:04):
              one chain, posts only, at 1k 5k 10k 34k 100k: post,
              noop / ff / merge pull, clone; `logs/scale.log`
            - [ ] rerun scaling on the post-only DAG build
            - supers always on; chat stays always on
            - END per class: forks, visibility, time per pull,
              per commit, per action
            - [x] code; [x] smoke 30 (before swap): PASS, forks
              on 16%, ps 23%, lf 54%; [ ] full run
        - asymmetric topology: no cost vs old at these rates;
          its effect is in forks under delay (simple 45% vs
          25-31%)
        - (was) running (26/10/09 20:05): chat 2k 1-2 s, chat 2k
          1-5 s, usenet 5k 1-60 s; logs `chat-2k-r12`,
          `chat-2k-r15`, `usenet-5k-r160`; peers kept per run
          (installed: ia-optim d995b64, tick merged)
    - [x] redraw `hubs50.dia` (26/10/07): asymmetric (112
      links, fewer leaf backups), names S1-S5, M1-M9, leaves
      01-45 (code: L01-L45)
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
