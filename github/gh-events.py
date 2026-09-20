#!/usr/bin/env python3
"""
JSONL (fetch-gh.sh) -> sorted event stream for gh-simple.lua.

Writes <out>.tsv with one event per line:
    ts  kind  id  user  target  reason
kinds:
    post      id = issue#|comment-id, target = issue# (parent)
    like      id = reaction seq, target = post id
    dislike   idem (THUMBS_DOWN)
    minimize  id = comment id, target = comment id, reason
bodies go to <out>.bodies/<post id> (payload files).
Minimize time is NOT exposed by GitHub: it is placed at the
comment's own time + MIN_DELAY (env, default 1h), i.e. right
after the comment, which is what a fast moderator does.
usage: gh-events.py <jsonl> <out-prefix>
"""

import json
import os
import sys
from datetime import datetime, timezone

MIN_DELAY = int(os.environ.get('MIN_DELAY', 3600))


def ts (s):
    return int(datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ')
               .replace(tzinfo=timezone.utc).timestamp())


def main ():
    src, out = sys.argv[1], sys.argv[2]
    bodies = out + '.bodies'
    os.makedirs(bodies, exist_ok=True)
    ev = []
    seq = 0
    nposts = nlike = ndis = nmin = 0

    def reactions (nodes, target):
        nonlocal seq, nlike, ndis
        for r in nodes:
            if r['content'] not in ('THUMBS_UP', 'THUMBS_DOWN'):
                continue
            seq += 1
            kind = 'like' if r['content'] == 'THUMBS_UP' else 'dislike'
            if kind == 'like':
                nlike += 1
            else:
                ndis += 1
            u = (r.get('user') or {}).get('login') or 'ghost'
            ev.append((ts(r['createdAt']), seq, kind, str(seq), u, target, ''))

    for line in open(src):
        i = json.loads(line)
        num = str(i['number'])
        u = (i.get('author') or {}).get('login') or 'ghost'
        seq += 1
        ev.append((ts(i['createdAt']), seq, 'post', num, u, num, ''))
        nposts += 1
        with open(os.path.join(bodies, num), 'w') as f:
            f.write((i.get('title') or '') + '\n\n' + (i.get('body') or ''))
        reactions(i['reactions']['nodes'], num)
        for c in i['comments']['nodes']:
            cid = c['id']
            cu = (c.get('author') or {}).get('login') or 'ghost'
            seq += 1
            ct = ts(c['createdAt'])
            ev.append((ct, seq, 'post', cid, cu, num, ''))
            nposts += 1
            with open(os.path.join(bodies, cid), 'w') as f:
                f.write(c.get('body') or '')
            reactions(c['reactions']['nodes'], cid)
            if c['isMinimized']:
                seq += 1
                reason = (c.get('minimizedReason') or '?').lower()
                ev.append((ct + MIN_DELAY, seq, 'minimize', cid, 'maintainer',
                           cid, reason))
                nmin += 1

    ev.sort(key=lambda e: (e[0], e[1]))
    with open(out + '.tsv', 'w') as f:
        for e in ev:
            f.write('\t'.join(str(x) for x in (e[0], e[2], e[3], e[4], e[5], e[6])) + '\n')
    print(f'posts={nposts} likes={nlike} dislikes={ndis} minimized={nmin} '
          f'events={len(ev)} -> {out}.tsv')


if __name__ == '__main__':
    main()
