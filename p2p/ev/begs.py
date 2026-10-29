# Begs (paper: posts that need extra begs), post hoc on a COPY of
# a kept peer of an OPEN chain (moves its `main` and restores it):
# blocked.py for the snapshot index (refs/local:a/b/c/d/<cid>).
# A post "needs a beg" if, at its parent and at its own time,
# author reps + W < cost; the first post of each author is the
# welcome (not counted).
# usage: begs.py <peer root> <keys dir> <n (0 = all)> <seed>
#        begs.py sum <output>
# sum: per W in (0, 500, 1000): posts, authors affected (of the
# returning authors), begs per affected author
# callers: by hand (r4)
import sys, os, re, random, subprocess, time, tempfile
from collections import Counter
COST = 500

def summary (path):
    rows = [l.split() for l in open(path) if not l.startswith(("#", "cid "))]
    known = [r for r in rows if r[4] != "unknown"]
    rest = [r for r in known if r[1] == "0"]
    back = set(r[5] for r in rest)      # returning authors
    q = lambda xs, p: sorted(xs)[int(p*(len(xs)-1))] if xs else 0
    print(f"posts {len(rows)}  known {len(known)}  unknown {len(rows)-len(known)}  others {len(rest)}  returning authors {len(back)}")
    for W in (0, 500, 1000):
        b = [r for r in rest if int(r[3]) + W < COST]
        per = Counter(r[5] for r in b)
        n = list(per.values())
        print(f"W={W}: begs {len(b)} of {len(rest)} = {100*len(b)/max(1,len(rest)):.2f}%  authors {len(per)} of {len(back)} = {100*len(per)/max(1,len(back)):.2f}%  per author median {q(n,.5)} p90 {q(n,.9)} max {max(n, default=0)}")

if sys.argv[1] == "sum":
    sys.exit(summary(sys.argv[2]))

root, keys, n, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
repo = root + "/chains/usenet"
git = lambda *a, i=None: subprocess.run(["git", "-C", repo, *a], input=i, capture_output=True, text=True, check=True).stdout
idx = lambda c: f"refs/local:{c[0]}/{c[1]}/{c[2]}/{c[3]}/{c}"

# snapshots: walk the 4 fanout levels of the index
ps = [""]
for _ in range(5):
    ps = git("ls-tree", "--name-only", "refs/local", *[p + "/" for p in ps if p]).split()
snap = set(p.rsplit("/", 1)[1] for p in ps)

# actions -> member, from the HEAD snapshot (the fullest)
head = git("rev-parse", "HEAD").strip()
files = git("ls-tree", "-r", "--name-only", idx(head) + "/actions").split()
out = git("cat-file", "--batch", i="".join(f"{idx(head)}/actions/{f}\n" for f in files))
member = {}
for f, body in zip(files, re.split(r'^\S+ blob \d+$', out, flags=re.M)[1:]):
    m = re.search(r'\["member"\] = "([^"]+)"', body)
    if m:
        member[f.rsplit("/", 1)[1][:-4]] = m.group(1)

# member -> public key file (for `reps member <file>`)
tmp = tempfile.mkdtemp()
pub, short = {}, {}
for k in os.listdir(keys):
    if k.endswith(".pub"):
        continue
    p = subprocess.run(["ssh-keygen", "-y", "-f", f"{keys}/{k}"], capture_output=True, text=True).stdout.split()
    if p:
        key = " ".join(p[:2])
        open(f"{tmp}/{k}.pub", "w").write(key + "\n")
        pub[key], short[key] = f"{tmp}/{k}.pub", k

# posts by declared time; first post per author = welcome
import atexit
atexit.register(lambda: git("update-ref", "refs/heads/main", head))
acts = [l.split() for l in git("log", "--no-merges", "--reverse", "--format=%H %at %P", "HEAD").splitlines()]
acts = [a for a in acts if a[0] in member]
acts.sort(key=lambda a: (int(a[1]), a[0]))
seen, rows = set(), []
for a in acts:
    c, t, ps = a[0], a[1], a[2:]
    m = member[c]
    first = m not in seen
    seen.add(m)
    rows.append((c, int(t), ps, m, first))
random.seed(seed)
sample = rows if n <= 0 else random.sample(rows, min(n, len(rows)))

def reps (parent, now, m):
    git("update-ref", "refs/heads/main", parent)
    r = subprocess.run(["freechains", "--root=" + root, "--now=" + str(now), "chain", "/usenet", "reps", "member", pub[m]], capture_output=True, text=True)
    return int(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip().lstrip("-").isdigit() else None

t0 = time.time()
print(f"# actions {len(acts)} members {len(seen)} snapshot {head[:8]}")
print("cid author_first parent reps blocked author")
for c, t, ps, m, first in sample:
    p = ps[0] if len(ps) == 1 else None
    a = short.get(m, "-")
    if p is None or p not in snap or m not in pub:
        print(c[:8], int(first), "-", "-", "unknown", a, flush=True)
        continue
    r = reps(p, t, m)
    b = "unknown" if r is None else int(r < COST)
    print(c[:8], int(first), p[:8], r, b, a, flush=True)
git("update-ref", "refs/heads/main", head)
print(f"# secs {time.time()-t0:.0f}")
