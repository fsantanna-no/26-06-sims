# Reorders per merge (paper 3.6), post hoc on a COPY of a kept peer
# (moves its `main` and restores it).
# usage: reorders.py <peer root> <n (0 = all)> <seed> <now>
# callers: ev.sh
# for merge M with parents p1, p2: list order at M, p1, p2;
# reorders(p) = actions of order(p) outside its longest common
# prefix with order(M) (moved by the merge); only merges with
# stored snapshots at M, p1, p2 (others cannot be listed)
import sys, random, subprocess, time
root, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
now = sys.argv[4]
repo = root + "/chains/usenet"
git = lambda *a: subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, check=True).stdout
snap = set(r.rsplit("/", 1)[1] for r in git("for-each-ref", "--format=%(refname)", "refs/local/").split())
allm = git("rev-list", "--merges", "--parents", "HEAD").splitlines()
merges = [l.split()[0] for l in allm if all(c in snap for c in l.split())]
print(f"# merges {len(allm)} with snapshots at M, p1, p2: {len(merges)}")
head = git("rev-parse", "HEAD").strip()
import atexit
atexit.register(lambda: git("update-ref", "refs/heads/main", head))
random.seed(seed)
sample = merges if n <= 0 else random.sample(merges, min(n, len(merges)))
cache = {}
def order (c):
    if c not in cache:
        git("update-ref", "refs/heads/main", c)
        out = subprocess.run(["freechains", "--root=" + root, "--now=" + now, "chain", "/usenet", "list", "order"], capture_output=True, text=True, check=True).stdout
        cache[c] = out.split()
    return cache[c]
def pushed (om, op):
    # actions of op outside its longest common prefix with om:
    # moved by the merge (0 when om only appends after op)
    k = 0
    while k < len(op) and k < len(om) and op[k] == om[k]:
        k += 1
    stable = [a for a in om if a in set(op)] == op
    return len(op) - k, stable
t0 = time.time()
print("merge p1 p2 n1 n2 r1 r2 stable")
for m in sample:
    p1, p2 = git("rev-parse", m + "^1", m + "^2").split()
    om, o1, o2 = order(m), order(p1), order(p2)
    r1, s1 = pushed(om, o1)
    r2, s2 = pushed(om, o2)
    print(m[:8], p1[:8], p2[:8], len(o1), len(o2), r1, r2, int(s1 and s2), flush=True)
git("update-ref", "refs/heads/main", head)
print(f"# usable {len(merges)} sampled {len(sample)} secs {time.time()-t0:.0f}", flush=True)
