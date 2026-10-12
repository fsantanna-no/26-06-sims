# Chain-time clamps from a final order (paper 3.7).
# P_i = max(P_{i-1}, S_i); a clamp is P_i > S_i (S_i: declared).
# usage: clamps.py <order file> <times file ("cid unix-time")>
# callers: ev.sh
import sys, statistics as st
T = dict(l.split() for l in open(sys.argv[2]))
P, d = 0, []
for c in open(sys.argv[1]).read().split():
    s = int(T[c]); P = max(P, s); d.append(P - s)
c = [x for x in d if x > 0]
q = lambda xs, p: sorted(xs)[int(p*(len(xs)-1))]
print(f"actions {len(d)}  clamped {len(c)} ({100*len(c)/len(d):.1f}%)")
if c:
    h = lambda x: f"{x/3600:.1f} h"
    print(f"P-S over clamped: median {h(q(c,.5))}  p90 {h(q(c,.9))}  max {h(max(c))}  mean {h(st.mean(c))}")
    for b in (60, 3600, 6*3600, 24*3600, 48*3600, 7*86400):
        print(f"  > {b//3600 if b>=3600 else b} {'h' if b>=3600 else 's'}: {sum(x > b for x in c)}")
