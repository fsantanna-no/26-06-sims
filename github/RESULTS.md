# gh-simple: GitHub issues replay (yt-dlp/yt-dlp)

- corpus: 12,077 issues (all, 2021-2026), 67,428 posts (issues
  + comments), 21,032 up / 2,097 down reactions (9.1% down),
  3,449 minimized comments (5.1% of posts), 18,377 logins
- first corpus with LIKE and REVOKE on the same events
- mapping: post = signed by login; 👍/👎 = like/dislike 1000
  action by the reacting login; minimized = revoke by the
  `maintainer` key at comment ts + 1h (minimize time is not
  exposed), amount = 1000 + likes on the target
- freechains: branch 260914-tree-trash (state as git tree),
  v0.21.0, installed 26/09/17

## OPEN chain, full corpus (26/09/18)

- 94,006 events in 6h47m; zero skips, zero clamps
- the same replay on the Sep-9 blob build died at 36k after
  12 h (1.17 s/ev, 2 h sweeps): see logs/*-forkage-36k.log

| N     | ev avg | likes  | dislikes | revokes | packed |
|-------|--------|--------|----------|---------|--------|
| 10000 | 0.211s |  1,075 |       58 |     311 |  44 MB |
| 30000 | 0.231s |  4,154 |      159 |   1,559 | 169 MB |
| 50000 | 0.243s |  8,425 |      298 |   2,453 | 316 MB |
| 70000 | 0.260s | 13,061 |      522 |   2,853 | 484 MB |
| 90000 | 0.262s | 19,758 |    1,999 |   3,366 | 658 MB |
| END   |        | 21,032 |    2,097 |   3,449 | 713 MB |

- latency FLAT (0.21 -> 0.26 s over 9x N); sweeps seconds;
  floor linear ~7.6 KB/event
- dislikes are bursty: 723 -> 1,999 in the 80k-90k window (the
  2025 controversies), 9.1% overall vs SE's 7-8%
- revoke reasons: resolved 1,092, off-topic 1,112, outdated
  415, duplicate 388, spam 298, abuse 130, low-quality 14
- TUG-OF-WAR: 3,449 revokes issued, 3,216 still revoked at END
  -> 233 minimized comments (6.8%) were UN-revoked by later
  community likes (a like on a revoked post re-supplies the
  payload and counts on the revoke axis)
    - by reason: pending (gated run logs revoke/un-revoke
      events per cid)

## GATED (dictator = maintainer), full corpus (26/09/18)

- 94,006 events in 9h06m (1.3x open); flat 0.31-0.37 s/ev;
  packed 688 MB; all 3,449 revokes issued and effective
- 18,377 logins: 11,504 posted (all begged at first post =
  births); 6,873 only reacted

| N     | ev avg | likes | dislikes | votes skipped | res_i | res_v |
|-------|--------|-------|----------|---------------|-------|-------|
| 10000 | 0.316s |   544 |       47 |   542 (48%)   |   604 |    54 |
| 30000 | 0.324s | 1,855 |      101 | 2,357 (55%)   | 1,505 |   293 |
| 50000 | 0.341s | 3,436 |      145 | 5,142 (59%)   | 2,450 |   458 |
| 70000 | 0.366s | 4,793 |      202 | 8,588 (63%)   | 3,464 |   574 |
| 90000 | 0.220s | 6,283 |      327 | 15,147 (70%)  | 4,275 |   725 |
| END   |        | 6,576 |      348 | 16,205 (70%)  | 4,434 |   751 |

- VOTES MOSTLY UNAFFORDABLE: 16,205 of 23,129 (70%) skipped
  because the reactor held < 1000 reps; in the 2025 controversy
  window 83% -- the dislike storm (open: 1,999) shrinks to 348
  when votes cost 1000: reactors are not posters
- resurrections 5,185: 751 vandal vs 4,434 innocent ->
  PRECISION 14% (wiki: 72%): GitHub commenters die by post
  cost, not by revocation; recidivists 504
- un-revoked by later likes: 101 of 3,449 (2.9%; open 6.8%,
  fewer affordable likes)
    - spam 2/298 (0.7%), abuse 1/130 (0.8%) vs resolved 39/1,092
      (3.6%), duplicate 16/388 (4.1%), off-topic 30/1,112 (2.7%)
    - the community overturns HOUSEKEEPING minimizes, almost
      never abuse/spam: the like-vs-revoke tug-of-war
      discriminates by reason without being told the reason

## A/B takeaways (open vs gated, same 94,006 events)

- both flat on the tree build (0.26 vs 0.37 s at END)
- gating removes 70% of the votes and 83% of the dislike
  storm: at vote = 1000 the vote signal is what dies first --
  the constants question is vote cost, before revoke cost
- precision 14% vs wiki 72%: two regimes (drained commenters
  vs revoked vandals); the innocent-resurrection rate is the
  friction metric the paper should report per corpus
- un-revoke by reason: abuse/spam < 1%, housekeeping 3-4%
