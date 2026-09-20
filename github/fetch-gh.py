#!/usr/bin/env python3
"""
Fetch a repo's issues + comments + reactions + minimized flags
via GraphQL (through `gh api graphql`) into
    sims/data/github/<owner>-<repo>.jsonl   (one issue per line)

GraphQL charges by REQUESTED nodes (n * c * r / 100 points, 5,000
points/h), so pages are kept small: 10 issues x 30 comments x 5
reactions ~ 18 points. totalCounts are recorded so a second pass
can top up the few nodes with more comments/reactions.
Paced by the rateLimit field; a failing page shrinks down to one
issue; a still-failing issue is logged as SKIPPED.
Resumable via the .cursor file.
usage: fetch-gh.py <owner/repo> [max-issues]
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

Q = '''query($owner:String!, $name:String!, $after:String, $n:Int!, $c:Int!, $r:Int!) {
  rateLimit { cost remaining resetAt }
  repository(owner:$owner, name:$name) {
    issues(first:$n, after:$after, orderBy:{field:CREATED_AT, direction:DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number title createdAt author { login } body
        reactions(first:$r) { totalCount
          nodes { content createdAt user { login } } }
        comments(first:$c) { totalCount
          nodes { id createdAt author { login } body
                  isMinimized minimizedReason
                  reactions(first:$r) { totalCount
                    nodes { content createdAt user { login } } } } }
      } } } }'''


def gql (owner, name, after, n, c, r):
    """One page; returns (nodes, pageInfo, rateLimit) or None."""
    cmd = ['gh', 'api', 'graphql', '-F', f'owner={owner}', '-F', f'name={name}',
           '-F', f'n={n}', '-F', f'c={c}', '-F', f'r={r}', '-f', f'query={Q}']
    if after:
        cmd += ['-F', f'after={after}']
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.strip()[:200] + '\n')
        return None
    d = json.loads(p.stdout)['data']
    iss = d['repository']['issues']
    return iss['nodes'], iss['pageInfo'], d['rateLimit']


def pace (rl):
    """Sleep until reset when the hourly budget is nearly gone."""
    if rl['remaining'] < 3 * max(rl['cost'], 1):
        reset = datetime.strptime(rl['resetAt'], '%Y-%m-%dT%H:%M:%SZ')
        reset = reset.replace(tzinfo=timezone.utc).timestamp()
        wait = max(0, reset - time.time()) + 5
        print(f'rate limit: sleeping {int(wait)}s', flush=True)
        time.sleep(wait)


def main ():
    repo = sys.argv[1]
    maxi = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    owner, name = repo.split('/')
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, '..', 'data', 'github', f'{owner}-{name}.jsonl')
    cur = out + '.cursor'
    os.makedirs(os.path.dirname(out), exist_ok=True)
    after = open(cur).read().strip() if os.path.exists(cur) else ''
    if after == 'END':
        print('already complete'); return
    count = sum(1 for _ in open(out)) if os.path.exists(out) else 0
    ladder = [(10, 30, 5), (3, 30, 5), (1, 30, 5), (1, 10, 3)]
    with open(out, 'a') as f:
        while True:
            got = None
            for (n, c, r) in ladder:
                for attempt in range(2):
                    got = gql(owner, name, after or None, n, c, r)
                    if got:
                        break
                    time.sleep(15)
                if got:
                    break
                print(f'shrinking page at {after[:20]}', flush=True)
            if not got:
                print(f'SKIPPED one issue at cursor {after[:30]}', flush=True)
                got = gql(owner, name, after or None, 1, 1, 1)
                if not got:
                    print('cannot advance; stopping', flush=True); break
                nodes, info, rl = got
                nodes = []
            else:
                nodes, info, rl = got
            for i in nodes:
                f.write(json.dumps(i, separators=(',', ':')) + '\n')
            f.flush()
            count += len(nodes)
            after = info['endCursor'] if info['hasNextPage'] else 'END'
            open(cur, 'w').write(after)
            print(f'issues {count}  cost {rl["cost"]}  left {rl["remaining"]}', flush=True)
            if after == 'END' or (maxi and count >= maxi):
                break
            pace(rl)
    print(f'DONE {out} ({count} issues)', flush=True)


if __name__ == '__main__':
    main()
