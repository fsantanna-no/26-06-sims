# Summary of blocked.py output, for welcome sizes W.
# usage: sumb.py <blocked output>
# callers: ev.sh
import sys
from collections import Counter
rows = [l.split() for l in open(sys.argv[1]) if not l.startswith(("#", "cid "))]
known = [r for r in rows if r[4] != "unknown"]
first = [r for r in known if r[1] == "1"]
rest = [r for r in known if r[1] == "0"]
print(f"posts {len(rows)}  known {len(known)}  unknown {len(rows)-len(known)}  first (welcome) {len(first)}  others {len(rest)}")
for W in (0, 500, 1000):
    b = [r for r in rest if int(r[3]) + W < 500]
    print(f"W={W}: blocked {len(b)} of {len(rest)} = {100*len(b)/max(1,len(rest)):.2f}%")
print("reps of blocked (W=0):", Counter(int(r[3]) for r in rest if int(r[3]) < 500).most_common(6))
