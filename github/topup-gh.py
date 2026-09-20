#!/usr/bin/env python3
"""
Top-up pass after fetch-gh.py: complete the comments of issues
whose comments.totalCount exceeds what was fetched, and the
reactions of every node (issue or comment) whose
reactions.totalCount exceeds what was fetched. GraphQL only
(REST has no minimized flags); ~1 point per 100 nodes.
Reads  sims/data/github/<owner>-<repo>.jsonl
Writes sims/data/github/<owner>-<repo>.full.jsonl
usage: topup-gh.py <owner/repo>
"""

import json
import os
import subprocess
import sys
import time

QC = '''query($owner:String!, $name:String!, $num:Int!, $after:String) {
  rateLimit { remaining }
  repository(owner:$owner, name:$name) { issue(number:$num) {
    comments(first:100, after:$after) {
      pageInfo { hasNextPage endCursor }
      nodes { id createdAt author { login } body
              isMinimized minimizedReason
              reactions(first:5) { totalCount
                nodes { content createdAt user { login } } } } } } } }'''

QRI = '''query($owner:String!, $name:String!, $num:Int!, $after:String) {
  rateLimit { remaining }
  repository(owner:$owner, name:$name) { issue(number:$num) {
    reactions(first:100, after:$after) {
      pageInfo { hasNextPage endCursor }
      nodes { content createdAt user { login } } } } } }'''

QRC = '''query($id:ID!, $after:String) {
  rateLimit { remaining }
  node(id:$id) { ... on IssueComment {
    reactions(first:100, after:$after) {
      pageInfo { hasNextPage endCursor }
      nodes { content createdAt user { login } } } } } }'''


def gql (q, **vars):
    cmd = ['gh', 'api', 'graphql', '-f', f'query={q}']
    for k, v in vars.items():
        if v is not None:
            cmd += ['-F', f'{k}={v}']
    for attempt in range(4):
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode == 0:
            d = json.loads(p.stdout)['data']
            if d['rateLimit']['remaining'] < 50:
                print('rate limit low: sleeping 10 min', flush=True)
                time.sleep(600)
            return d
        sys.stderr.write(p.stderr.strip()[:200] + '\n')
        time.sleep(15 * (attempt + 1))
    return None


def paginate (q, path, **vars):
    """All nodes of a connection reached by `path` in the reply."""
    out, after = [], None
    while True:
        d = gql(q, after=after, **vars)
        if not d:
            print(f'FAILED {vars}', flush=True)
            return out
        conn = d
        for k in path:
            conn = conn[k]
        out += conn['nodes']
        if not conn['pageInfo']['hasNextPage']:
            return out
        after = conn['pageInfo']['endCursor']


def more (conn, cap=50):
    """Does this connection have more nodes than fetched?"""
    t = conn.get('totalCount')
    return (t is not None and t > len(conn['nodes'])) or \
           (t is None and len(conn['nodes']) >= cap)


def main ():
    owner, name = sys.argv[1].split('/')
    here = os.path.dirname(os.path.abspath(__file__))
    src = os.path.join(here, '..', 'data', 'github', f'{owner}-{name}.jsonl')
    dst = src.replace('.jsonl', '.full.jsonl')
    nc = nr = 0
    with open(dst, 'w') as f:
        for line in open(src):
            i = json.loads(line)
            num = i['number']
            if more(i['comments'], 100):
                i['comments']['nodes'] = paginate(
                    QC, ['repository', 'issue', 'comments'],
                    owner=owner, name=name, num=num)
                nc += 1
            if more(i['reactions']):
                i['reactions']['nodes'] = paginate(
                    QRI, ['repository', 'issue', 'reactions'],
                    owner=owner, name=name, num=num)
                nr += 1
            for c in i['comments']['nodes']:
                if more(c['reactions']):
                    c['reactions']['nodes'] = paginate(
                        QRC, ['node', 'reactions'], id=c['id'])
                    nr += 1
            f.write(json.dumps(i, separators=(',', ':')) + '\n')
    print(f'DONE {dst}: comments topped {nc}, reactions topped {nr}', flush=True)


if __name__ == '__main__':
    main()
