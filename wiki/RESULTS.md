# wiki-simple: Wikipedia article replays (26/09/11)

- driver: `wiki-simple.lua` -- revisions as signed posts
  (payload = full wikitext via FILE), sha1-reverts as REVOKES
  of the intermediate revisions, signed by the reverter
- freechains: installed snapshots build; dictator supported

## Abortion, OPEN chain (full history)

- input: 13,973 revisions fetched (14 batches, 2001->2026);
  13,909 replayed (batch-boundary dedup) + 7,371 revokes
  = 21,280 events; 2,134 editors (IPs share `anon`)
- 53% of revisions eventually revoked -- pre-moderation
  vandalism visible (SE showed only post-moderation 3-12%)
- total: 3h43m; zero ts clamps
- ledger: 968 of 2,134 members negative (reverters pay
  1000/revoke; open chain lets them run into debt)

| N     | ev avg | revokes | packed  | sweep |
|-------|--------|---------|---------|-------|
|  5000 | 0.201s |   1,189 |  5.8 MB |  114s |
| 10000 | 0.339s |   4,410 | 12.7 MB |  569s |
| 15000 | 0.481s |   5,900 | 24.7 MB | 1278s |
| 20000 | 0.626s |   7,129 | 44.6 MB | 2227s |
| END   |        |   7,371 | 47.8 MB | 2387s |

- revoke path verified: `get payload` on a revoked cid errors
  ("revoked payload"), the action stays in `list order`
- loose per window is HUGE (9 GB at 20k): payloads are full
  ~100 KB wikitexts; sweep delta-compresses near-identical
  revisions ~200x -- the packed floor (48 MB / 25y) is close
  to MediaWiki's own storage efficiency
- vandalism peak 2005-2007: window 5k-10k alone had 3,221
  revokes (44% of its events)

## Abortion, GATED (dictator) -- full history (fixed run)

- `--dictator` chain: editors gated, dictator = platform
- per-IP keys (3,518 identities vs open's 2,134 shared-anon)
- beg + dictator welcome; a revoke must OUTWEIGH the likes on
  its target (welcomed post: 2,000); reverter pays it if he
  affords it, else the dictator revokes
- same 21,280 events as open; all 7,371 revokes effective
  (a first run revoked with 1,000 = tie with the welcome like
  -> 3,590 effective only; kept as `*-BUGGY.log`, figures void)
- total: 7h28m (2.0x open: reps query + welcome per beg)

| N     | ev avg | births | res_i | res_v | comm | dict |
|-------|--------|--------|-------|-------|------|------|
|  5000 | 0.385s |  1,010 |   360 |   348 |  456 |  733 |
| 10000 | 0.684s |  1,370 |   453 | 1,074 |  641 | 3769 |
| 15000 | 1.098s |  2,502 |   694 | 1,938 |  998 | 4902 |
| 20000 | 1.299s |  3,247 |   874 | 2,352 | 1489 | 5640 |
| END   |        |  3,518 |   955 | 2,449 | 1597 | 5774 |

- resurrections 3,404: 2,449 vandal vs 955 innocent
    - PRECISION 72%: re-admissions mostly re-tax formerly
      revoked identities
- recidivists 844 (34% of resurrected vandals revoked again)
- community self-funds 22% of revokes (1,597 / 7,371); 15%
  during the 2005-07 storm: outweighing a welcome costs 2,000
- packed floor 72 MB @20k (1.6x open: begs + welcomes)
- every identity's FIRST post begs (births = users)

## Gated economy: growth and consistency (fixed run)

- editors' positive mass along `list order`: 1.1 M @2.5k ->
  2.35 M @7.5k -> 1.48 M @10k (storm: revokes bite) -> 2.0 M
  @17.5k -> 3.3 M @22.5k -> 5.56 M END; members 486 -> 3,518
- debtors: 14 -> 112 (storm) -> 213 END; worst -275k
  (459 edits, 418 revoked), -122k (an IP, 327 revoked)
- platform subsidy: dictator ~ -17 M (6,922 welcomes + 5,774
  revokes at 2,000); editors hold 5.56 M net of 0.9 M debt
- cap 50000 hit by 6 members only (veterans): whale bound
- reps vs edits: Spearman 0.23; by edit count: 1 edit 829,
  2-5 1,568, 6-20 3,512, 21-100 7,012, 101+ MEAN -3,042
  (the 101+ bucket is edit-warriors: heavy AND revoked)
- reps vs revoked: Spearman -0.49 -- revocation now shows:
  never-revoked mean 2,827 vs revoked mean 509
- one-shot vandal nets ~+50: welcome 450 + refund 500 - 900
  (half of the 2,000 revoke); earn withheld (rule 1.b);
  the 12h refund still pays -> upstream question
- admission blindness: 99.4% of revoked identities had their
  FIRST edit revoked (3,288 / 3,307); no policy screens them
- revert latency (offline): 34.6% within 12h; intervening
  edits: 42.4% zero (patrolled), 41% > 5 (sha1 cascade tail
  + disputes) -> activity is the sharper classifier

## A/B takeaways (open vs gated, same input)

- identical revert stream (revokes match window by window)
- gated costs 2.0x wall time and 1.6x disk floor
- what gating buys: resurrection precision (72%), recidivism
  (34%), self-funding ratio (22%), a consistent ledger
  (reps~revoked -0.49) -- none exist on the open chain
- dictator did 78% of moderation: at cost 500 / welcome 1000
  / revoke 2000 the community cannot self-police a vandal
  storm; the input for 260911-consts
