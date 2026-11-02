# Begs per % of authors: for k = 1, 2, ... the % of all authors
# who needed exactly k begs (and k or more), per W. The welcome
# (each author's first post) counts as one beg, so every author
# has k >= 1; one-post authors have only the welcome.
# Input: begs.py output (needs its `author` column; the old
# blocked.py outputs `*.blocked` have none).
# usage: begs-authors.py <begs output> > <tsv>
#  - tsv: k, then per W in (0, 500, 1000): authors and % with
#    exactly k begs, and % with k or more (plot: x = ge_w<W>,
#    y = k, a step from 100% at k = 1)
# callers: by hand (paper plot)
import sys
from collections import Counter
COST = 500
WS = (0, 500, 1000)

rows = [l.split() for l in open(sys.argv[1]) if not l.startswith(("#", "cid "))]
if rows and len(rows[0]) < 6:
    sys.exit("no author column: run begs.py (not blocked.py)")
known = [r for r in rows if r[4] != "unknown"]
rest = [r for r in known if r[1] == "0"]
authors = set(r[5] for r in rows if r[1] == "1" and r[5] != "-")
n = len(authors)

dist = {}
for W in WS:
    per = Counter(r[5] for r in rest if int(r[3]) + W < COST)
    dist[W] = Counter(1 + per.get(a, 0) for a in authors)
top = max(max(d) for d in dist.values()) if n else 0

print(f"# authors {n}  posts {len(rows)}  (welcomes {n}, others known {len(rest)})")
print("k\t" + "\t".join(f"n_w{W}\tpct_w{W}\tge_w{W}" for W in WS))
for k in range(1, top + 1):
    cols = []
    for W in WS:
        d = dist[W]
        ge = sum(v for j, v in d.items() if j >= k)
        cols += [str(d.get(k, 0)), f"{100*d.get(k, 0)/n:.3f}", f"{100*ge/n:.3f}"]
    print(f"{k}\t" + "\t".join(cols))
