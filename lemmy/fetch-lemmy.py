#!/usr/bin/env python3
"""
Fetch one Lemmy community, as seen by one instance, via the public
REST API (`/api/v3`, anonymous) into
    sims/data/lemmy/<instance>-<name@home>/
        site.json         instance version and settings
        community.json    community view, moderators
        federated.json    instance blocklist (current snapshot)
        posts.jsonl       one post view per line, oldest first
        comments.jsonl    one comment view per line, per post
        modlog.jsonl      one entry per line, with its `type_`
Votes are NOT fetched (per-user votes are admin/mod only).
Removed posts/comments are hidden from listings; the modlog keeps
them with their content. Author-deleted items are lost.
Posts page by cursor (`page_cursor`); comments page per post;
modlog pages per `type_` (cap: 100 pages x 50).
Resumable: each phase writes `<file>.done`; comments keep the
index of the next post in `comments.jsonl.cursor`.
usage: fetch-lemmy.py <instance> <name@home>
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA    = 'freechains-sims/0.1 (academic research; one community)'
PACE  = float(os.environ.get('PACE', 0.5))     # seconds per request
LIMIT = 50                                     # API max page size
PAGES = 100                                    # API max page number

# modlog types tied to a community (admin types have none)
TYPES = ['ModRemovePost', 'ModRemoveComment', 'ModLockPost',
         'ModFeaturePost', 'ModBanFromCommunity', 'ModAddCommunity',
         'ModTransferCommunity']


def get (inst, path, **params):
    """
    One GET on the instance API, paced and retried.
    Inputs:
     - inst [str]: instance host, e.g. 'feddit.org'
     - path [str]: API path under /api/v3, e.g. 'post/list'
     - params [dict]: query parameters
    Outputs:
     - [dict]: decoded JSON response
    Errors:
     - "GET <url>: <error>" : still failing after 4 tries
    Callers:
     - main, posts, comments, modlog [fetch-lemmy.py]
    """
    q = urllib.parse.urlencode(params)
    url = f'https://{inst}/api/v3/{path}' + (f'?{q}' if q else '')
    err = None
    for i in range(4):
        time.sleep(PACE * (1 + 4 * i))
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, ValueError) as e:
            err = e
    raise RuntimeError(f'GET {url}: {err}')


def done (path):
    """
    Whether a phase output is complete.
    Inputs:
     - path [str]: output file
    Outputs:
     - [bool]: True when `<path>.done` exists
    Callers:
     - main [fetch-lemmy.py]
    """
    return os.path.exists(path + '.done')


def finish (path, n):
    """
    Mark a phase output complete and report it.
    Inputs:
     - path [str]: output file
     - n [int]: number of records written
    Outputs:
     - none
    Callers:
     - posts, comments, modlog [fetch-lemmy.py]
    """
    open(path + '.done', 'w').write(f'{n}\n')
    print(f'DONE {os.path.basename(path)} ({n})', flush=True)


def save (path, obj):
    """
    Write one JSON document.
    Inputs:
     - path [str]: output file
     - obj [dict]: document
    Outputs:
     - none
    Callers:
     - main [fetch-lemmy.py]
    """
    with open(path, 'w') as f:
        json.dump(obj, f, indent=1)


def line (f, obj):
    """
    Append one compact JSON line.
    Inputs:
     - f [file]: open output file
     - obj [dict]: record
    Outputs:
     - none
    Callers:
     - posts, comments, modlog [fetch-lemmy.py]
    """
    f.write(json.dumps(obj, separators=(',', ':')) + '\n')


def posts (inst, comm, out):
    """
    All listed posts of the community, oldest first, by cursor.
    Restarts from scratch when interrupted (small phase).
    Inputs:
     - inst [str]: instance host
     - comm [str]: community as 'name@home'
     - out [str]: output .jsonl
    Outputs:
     - [list]: post ids, in file order
    Callers:
     - main [fetch-lemmy.py]
    """
    ids, cur = [], None
    with open(out, 'w') as f:
        while True:
            p = {'community_name': comm, 'sort': 'Old', 'limit': LIMIT}
            if cur:
                p['page_cursor'] = cur
            d = get(inst, 'post/list', **p)
            for v in d['posts']:
                line(f, v)
                ids.append(v['post']['id'])
            print(f'posts {len(ids)}', flush=True)
            cur = d.get('next_page')
            if not d['posts'] or not cur:
                break
    finish(out, len(ids))
    return ids


def comments (inst, ids, out):
    """
    All listed comments, post by post, resumable by post index.
    Inputs:
     - inst [str]: instance host
     - ids [list]: post ids (instance-local), from `posts`
     - out [str]: output .jsonl
    Outputs:
     - none
    Callers:
     - main [fetch-lemmy.py]
    """
    cur = out + '.cursor'
    k = int(open(cur).read()) if os.path.exists(cur) else 0
    n = sum(1 for _ in open(out)) if k and os.path.exists(out) else 0
    with open(out, 'a' if k else 'w') as f:
        for i in range(k, len(ids)):
            for page in range(1, PAGES + 1):
                d = get(inst, 'comment/list', post_id=ids[i], sort='Old',
                        type_='All', limit=LIMIT, page=page)
                for v in d['comments']:
                    line(f, v)
                n += len(d['comments'])
                if len(d['comments']) < LIMIT:
                    break
            else:
                print(f'CAP comments of post {ids[i]}', flush=True)
            f.flush()
            open(cur, 'w').write(str(i + 1))
            if (i + 1) % 50 == 0:
                print(f'comments {n}  posts {i+1}/{len(ids)}', flush=True)
    finish(out, n)


def modlog (inst, cid, out):
    """
    Community modlog, per action type, newest first.
    Restarts from scratch when interrupted (small phase).
    Inputs:
     - inst [str]: instance host
     - cid [int]: community id (instance-local)
     - out [str]: output .jsonl
    Outputs:
     - none
    Callers:
     - main [fetch-lemmy.py]
    """
    n = 0
    with open(out, 'w') as f:
        for t in TYPES:
            for page in range(1, PAGES + 1):
                d = get(inst, 'modlog', community_id=cid, type_=t,
                        limit=LIMIT, page=page)
                es = [e for v in d.values() for e in v]
                for e in es:
                    line(f, {'type_': t, **e})
                n += len(es)
                if len(es) < LIMIT:
                    break
            else:
                print(f'CAP modlog {t}: older entries lost', flush=True)
            print(f'modlog {t} -> {n}', flush=True)
    finish(out, n)


def main ():
    if len(sys.argv) != 3 or '@' not in sys.argv[2]:
        sys.exit('usage: fetch-lemmy.py <instance> <name@home>')
    inst, comm = sys.argv[1], sys.argv[2]
    here = os.path.dirname(os.path.abspath(__file__))
    base = os.path.join(here, '..', 'data', 'lemmy', f'{inst}-{comm}')
    os.makedirs(base, exist_ok=True)
    P = lambda f: os.path.join(base, f)

    save(P('site.json'), get(inst, 'site'))
    view = get(inst, 'community', name=comm)
    save(P('community.json'), view)
    save(P('federated.json'), get(inst, 'federated_instances'))
    cid = view['community_view']['community']['id']

    if done(P('posts.jsonl')):
        ids = [json.loads(l)['post']['id'] for l in open(P('posts.jsonl'))]
    else:
        ids = posts(inst, comm, P('posts.jsonl'))
    if not done(P('comments.jsonl')):
        comments(inst, ids, P('comments.jsonl'))
    if not done(P('modlog.jsonl')):
        modlog(inst, cid, P('modlog.jsonl'))
    open(P('.done'), 'w').write(time.strftime('%Y-%m-%dT%H:%M:%SZ\n',
                                              time.gmtime()))
    print(f"DONE {base}", flush=True)


if __name__ == '__main__':
    main()
