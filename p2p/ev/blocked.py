# Blocked posts (old paper item d), post hoc on a COPY of a kept
# peer of an OPEN chain (moves its `main` and restores it).
# An open chain skips rule 4.a (afford the post) but still keeps
# reps; a post "would be blocked" if, at its parent (the posting
# peer's view) and at its own time, author reps + W < cost.
# The first post of each author is the welcome (not counted).
# usage: blocked.py <peer root> <keys dir> <n (0 = all)> <seed> <W>
#  - W: reps a welcome like would give the author (0 = none)
# callers: ev.sh
import sys, os, re, random, subprocess, time, tempfile
root, keys, n, seed, W = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
COST = 500
repo = root + "/chains/usenet"
git = lambda *a, i=None: subprocess.run(["git", "-C", repo, *a], input=i, capture_output=True, text=True, check=True).stdout

# snapshots: cid -> order_n; the fullest one maps actions -> member
snaps = git("for-each-ref", "--format=%(refname:lstrip=2)", "refs/local/").split()
out = git("cat-file", "--batch", i="".join(f"refs/local/{c}:meta.lua\n" for c in snaps))
ns = [int(x) for x in re.findall(r'\["order_n"\] = (\d+)', out)]
full = snaps[max(range(len(snaps)), key=lambda k: ns[k])]
snap = set(snaps)
files = git("ls-tree", "-r", "--name-only", f"refs/local/{full}", "actions").split()
out = git("cat-file", "--batch", i="".join(f"refs/local/{full}:{f}\n" for f in files))
member = {}
for f, body in zip(files, re.split(r'^\S+ blob \d+$', out, flags=re.M)[1:]):
    m = re.search(r'\["member"\] = "([^"]+)"', body)
    if m:
        member[f.rsplit("/", 1)[1][:-4]] = m.group(1)

# member -> public key file (for `reps member <file>`)
tmp = tempfile.mkdtemp()
pub = {}
for k in os.listdir(keys):
    if k.endswith(".pub"):
        continue
    p = subprocess.run(["ssh-keygen", "-y", "-f", f"{keys}/{k}"], capture_output=True, text=True).stdout.split()
    if p:
        key = " ".join(p[:2])
        open(f"{tmp}/{k}.pub", "w").write(key + "\n")
        pub[key] = f"{tmp}/{k}.pub"

# posts by declared time; first post per author = welcome
head = git("rev-parse", "HEAD").strip()
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
print(f"# actions {len(acts)} members {len(seen)} snapshot {full[:8]} W={W}")
print("cid author_first parent reps blocked")
for c, t, ps, m, first in sample:
    p = ps[0] if len(ps) == 1 else None
    if p is None or p not in snap or m not in pub:
        print(c[:8], int(first), "-", "-", "unknown", flush=True)
        continue
    r = reps(p, t, m)
    b = "unknown" if r is None else int(r + W < COST)
    print(c[:8], int(first), p[:8], r, b, flush=True)
git("update-ref", "refs/heads/main", head)
print(f"# secs {time.time()-t0:.0f}")
