# lemmy-simple: Lemmy community replay (adhd@lemmy.dbzer0.com)

- corpus: `adhd@lemmy.dbzer0.com` as seen by its home instance,
  2023-06-12 to 2026-10-03; 1,357 posts + 30,007 comments
  listed, 58 hidden items recovered from the modlog; 33,027
  events; 7,447 keys (members + moderators)
- first corpus with revoke REASONS by named (id) moderators,
  author self-deletes, and a second instance (feddit.org)
  holding the same community
- mapping: post = signed by actor id; modlog removal = revoke
  by the moderator's own key, `--why=<reason>`, amount = 1000
  + likes; restore = unrevoke `--file`; author delete = free
  self-revoke; no votes (not public)
- freechains: v0.21.0 (`--version` does not tell builds apart)
    - `main` 5e04aa4 (26/10/03): first open run
    - 260914-tree-trash (installed 26/10/05 11:56): reruns

## OPEN chain, home stream, `main` build (26/10/05)

- log: `logs/open-main.log`
- 33,027 events in 14h50m; zero skip_t, 11 skip_r (revoke of
  an already revoked item), zero clamps
- 31,422 posts, 170 revokes, 2 restores, 1,277 self-revokes,
  138 bans/unbans (counted only)

| N     | ev avg | revokes | deletes | sweep  | packed |
|-------|--------|---------|---------|--------|--------|
|  2000 | 0.169s |       1 |      47 |    16s |   2 MB |
|  8000 | 0.345s |      65 |     278 |   333s |  15 MB |
| 16000 | 0.596s |     104 |     605 |  1407s |  39 MB |
| 24000 | 0.861s |     135 |     874 |  3097s |  81 MB |
| 32000 | 1.146s |     157 |   1,197 |  5454s | 135 MB |
| END   |        |     170 |   1,277 |        | 167 MB |

- LATENCY GROWS LINEARLY: 0.17 -> 1.15 s/ev over 16x N,
  unlike GitHub (flat 0.21 -> 0.26 s over 94k); sweeps grow
  ~quadratically and take 31,865 s = 60% of the run
    - same shape as GitHub on the old blob build (1.17 s/ev
      at 36k, 2 h sweeps); `main` lacks the 260914-tree-trash
      state (checked): rerun on tree-trash pending
- revokes: 0.54% of posts (GitHub 5.1%); all 172 revokes +
  unrevokes signed by the moderators' own keys, in debt
  (open chain)
- self-revokes: 1,277 (4.1% of posts), 7.5x the moderator
  revokes: forgetting dominates moderation
- revoke reasons: "Rule 1" (No Party Pooping) and variants
  82, "Community rule 1" 34, slurs/ableism 9, wrong or
  off-topic community 8, rude 4, spam 3, none 8
- restores: 2 (1.2% of removals)

## OPEN chain, home stream, tree-trash build (26/10/05)

- log: `logs/open.log`
- 33,027 events in 2h07m (main: 14h50m, 7.0x slower); same
  counts as main: 31,422 posts, 170 revokes, 2 restores, 1,277
  self-revokes, 11 skip_r, zero skip_t

| N     | ev avg | sweep | packed | main ev avg | main sweep |
|-------|--------|-------|--------|-------------|------------|
|  2000 | 0.215s |    4s |   6 MB |      0.169s |        16s |
|  8000 | 0.214s |    9s |  32 MB |      0.345s |       333s |
| 16000 | 0.211s |   12s |  68 MB |      0.596s |      1407s |
| 24000 | 0.242s |   18s | 110 MB |      0.861s |      3097s |
| 32000 | 0.222s |   22s | 153 MB |      1.146s |      5454s |

- LATENCY FLAT: 0.21 -> 0.24 s/ev over 16x N (GitHub on the
  same build: 0.21 -> 0.26 s); sweeps linear, 212 s in total
  (main: 31,865 s); packed ~4.8 KB/event
- the main build's linear latency and quadratic sweeps are the
  build, not the corpus: main lacks the tree-trash state

## GATED (dictator), home stream, tree-trash build (26/10/05)

- log: `logs/gated.log`
- 33,027 events in 3h28m (1.6x open); 0.35-0.40 s/ev, flat;
  sweeps 292 s in total; packed 203 MB at 32k
- same revokes, restores and self-revokes as open (no votes,
  so nothing is skipped as unaffordable)

| N     | ev avg | births | res_i | res_v | dict revokes |
|-------|--------|--------|-------|-------|--------------|
|  2000 | 0.403s |  1,000 |   216 |     1 |            1 |
|  8000 | 0.368s |  2,825 |   641 |     9 |           65 |
| 16000 | 0.350s |  4,722 | 1,044 |    20 |          105 |
| 24000 | 0.397s |  6,207 | 1,323 |    30 |          137 |
| 32000 | 0.355s |  7,307 | 1,529 |    32 |          159 |
| END   |        |  7,439 | 1,550 |    32 |          172 |

- EVERY POSTER BEGS FIRST: 7,439 births = all posting keys
  (as GitHub); 1,550 innocent re-welcomes (members back under
  500 reps), 32 re-welcomes after a revoke, 38 recidivists
- MODERATORS NEVER AFFORD A REVOKE: all 172 revokes and
  unrevokes signed by the dictator (`MODS=own` fallback),
  zero by the moderators' own keys (wiki: community 22%)
    - moderators post little; a revoke costs 1000 + likes

## OPEN chain, feddit.org stream, tree-trash build (26/10/05)

- log: `logs/feddit-open.log`
- the same community as kept by feddit.org: 24,562 events in
  1h35m; 0.20-0.24 s/ev flat; sweeps 139 s; packed 116 MB at 24k
- 23,568 posts, 74 revokes, 1 restore, 854 self-revokes,
  63 bans/unbans; 5,391 keys; zero skip_t, 1 skip_r
- vs home: 25% fewer posts, 57% fewer revokes, 33% fewer
  self-revokes: the copy misses many actions; whether its
  `mod/feddit.org/*` revokes are local or federated is open

## P2P smoke: two peers, home + feddit.org (26/10/05)

- log: `logs/p2p-smoke.log`; `lemmy-p2p.lua`, `LIMIT=2000`,
  `SYNC=10`
- merged stream: 36,990 events (20,390 duplicates dropped)
- first 2,000 events all on H (feddit.org users start later)
- 1,999 actions on both peers, identical `list order`; zero
  sync failures, zero skips
- cost: 0.21 s/ev on the author; 402 syncs in 403 s
    - empty sync (nothing new), measured apart: 0.5 s, 28 MB
    - so a replayed action costs ~0.15 s incl. its share of
      sync overhead (vs 0.21 s for a fresh action)
