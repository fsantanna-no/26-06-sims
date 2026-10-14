# Summary of reorders.py output: loser side moves per merge.
# usage: sumr.py <reorders output>
# callers: ev.sh
import sys
rows = [l.split() for l in open(sys.argv[1]) if l[0] not in '#m' and len(l.split()) == 8]
r1 = [int(r[5]) for r in rows]; r2 = [int(r[6]) for r in rows]
lo = [max(a, b) for a, b in zip(r1, r2)]
both = sum(a > 0 and b > 0 for a, b in zip(r1, r2))
q = lambda xs, p: sorted(xs)[int(p*(len(xs)-1))]
if not rows:
    sys.exit(print("merges 0 (none with snapshots)"))
print(f"merges {len(rows)}  p1 moved>0: {sum(x>0 for x in r1)}  p2 moved>0: {sum(x>0 for x in r2)}  both: {both}  none: {sum(x==0 for x in lo)}")
print(f"moved per merge (loser side): mean {sum(lo)/len(lo):.2f}  median {q(lo,.5)}  p90 {q(lo,.9)}  max {max(lo)}  total {sum(lo)}")
print(f"unstable (loser's own order changed): {sum(r[7]=='0' for r in rows)}")
from collections import Counter
c = Counter(min(x, 21) for x in lo)
print("hist:", " ".join(f"{k if k<21 else '21+'}:{v}" for k, v in sorted(c.items())))
