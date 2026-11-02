# Begs per author, as a distribution over the authors: for k = 0,
# 1, 2, ... the % of returning authors (2+ posts: the first one is
# the welcome) whose other posts needed exactly k begs, per W.
# Input: begs.py output (needs its `author` column; the old
# blocked.py outputs `*.blocked` have none).
# usage: begs-authors.py <begs output> > <tsv>
#  - tsv: k, then per W in (0, 500, 1000): authors and % with
#    exactly k begs, and % with k or more (tail)
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
back = set(r[5] for r in rest)          # returning authors
n = len(back)

dist = {}
for W in WS:
    per = Counter(r[5] for r in rest if int(r[3]) + W < COST)
    dist[W] = Counter(per.get(a, 0) for a in back)
top = max(max(d) for d in dist.values()) if n else 0

print(f"# returning authors {n}  posts {len(rest)}  (of {len(rows)} rows)")
print("k\t" + "\t".join(f"n_w{W}\tpct_w{W}\tge_w{W}" for W in WS))
for k in range(top + 1):
    cols = []
    for W in WS:
        d = dist[W]
        ge = sum(v for j, v in d.items() if j >= k)
        cols += [str(d.get(k, 0)), f"{100*d.get(k, 0)/n:.3f}", f"{100*ge/n:.3f}"]
    print(f"{k}\t" + "\t".join(cols))
