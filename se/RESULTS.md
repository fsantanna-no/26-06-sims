# se-simple: Stack Exchange replays (26/09/04)

- driver: `se-simple.lua` -- posts (PostTypeId 1|2) signed by
  per-user keys; votes (VoteTypeId 2|3) as like/dislike 1000
  action <cid> by ONE shared anonymous `voter` key
- OPEN chain (no gates); voter runs into debt by design
- freechains: 260902-snapshots build (tip file + K-anchors)

## vegetarianism.stackexchange (full)

- input: 2,257 posts + 13,805 votes = 16,062 events, 2017-2024
- downvote share 7.6% (contentious mid-size site)
- 568 users; zero ts clamps, zero skips
- total: 64 min (3,834s)

| N     | ev avg | packed | sweep |
|-------|--------|--------|-------|
|  5000 | 0.130s | 2.1 MB |  2.3s |
| 10000 | 0.233s | 4.3 MB |  3.5s |
| 15000 | 0.318s | 6.3 MB |  6.8s |

- growth LINEAR (~0.09s per 5k), same regime as chat/usenet
- final repo 40 MB unswept (last sweep 21.8 MB total)
- ledger check: voter reps = -13,805,000 = votes * 1000 exactly;
  11 authors negative (net-downvoted) -- open-chain debt works
- vs usenet at 15k (0.361s): -12% -- 568-member ledger is small;
  votes are cheaper than 3 kB payloads

## pending

- retro (262k events): needs vote AGGREGATION cut (~5x fewer)
- politics (760k): needs TIME-SLICE cut
- casual control site full run: coffee or sports

## coffee.stackexchange (full)

- input: 4,373 posts + 18,485 votes = 22,858 events, 2015-2024
- downvote share 8.1% (1,578/19,594 in dump) -- NOT lower than
  veg's 7.6%: "casual" does not mean fewer downvotes
- 1,706 users; zero ts clamps, zero skips
- total: 1h55m (6,899s)

| N     | ev avg | packed | sweep |
|-------|--------|--------|-------|
|  5000 | 0.123s | 2.1 MB |  2.1s |
| 10000 | 0.216s | 4.3 MB |  3.9s |
| 15000 | 0.316s | 6.6 MB |  7.6s |
| 20000 | 0.421s | 9.8 MB | 12.4s |

- growth LINEAR (~0.10s per 5k); tracks veg per-window within 5%
  despite 3x the users (1,706 vs 568): member-ledger cost is
  negligible at this scale (contrast usenet's 14k)
- ledger check: voter reps = -18,485,000 = votes * 1000 exactly;
  4 authors negative
