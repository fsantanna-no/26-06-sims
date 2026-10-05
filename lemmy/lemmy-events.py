#!/usr/bin/env python3
"""
Lemmy JSON (fetch-lemmy.py) -> sorted event stream for
lemmy-simple.lua.

Writes <out>.tsv with one event per line:
    ts  kind  id  user  target  reason
kinds:
    post     id = item key, target = parent key (post: itself)
    remove   mod removal; id = modlog seq, user = mod key,
             target = item key, reason
    restore  mod restore; as remove
    delete   author self-delete; user = author, target = item
             key (time = item's last update, else creation)
    ban      community ban; user = mod key, target = banned
             member key, reason ('unban' when lifted)
    addmod   moderator added; user = mod key, target = new mod
keys are global (from ActivityPub ids), so two instances' streams
of the same community line up: 'lemmy.dbzer0.com/post/123',
'feddit.org/u/alice'. Mod keys are instance-local
('mod/<instance>/<person id>'): some instances hide mod names.
Items known only from the modlog (hidden from listings) are
added as posts at their own creation time, with their content.
bodies go to <out>.bodies/<key with '/' -> '_'> (payload files):
post = title + '\n\n' + body (or url); comment = content;
'(deleted)' when the author deleted it.
usage: lemmy-events.py <dir> [out-prefix]
"""

import json
import os
import sys
from datetime import datetime


def ts (s):
    """
    ISO timestamp -> epoch seconds.
    Inputs:
     - s [str]: e.g. '2023-09-14T08:35:51.852675Z'
    Outputs:
     - [int]: seconds since epoch (UTC)
    Callers:
     - main [lemmy-events.py]
    """
    return int(datetime.fromisoformat(s.replace('Z', '+00:00'))
               .timestamp())


def key (ap_id):
    """
    ActivityPub id -> global key.
    Inputs:
     - ap_id [str]: e.g. 'https://feddit.org/u/alice'
    Outputs:
     - [str]: e.g. 'feddit.org/u/alice'
    Callers:
     - main [lemmy-events.py]
    """
    return ap_id.split('://', 1)[-1].rstrip('/')


def jsonl (path):
    """
    Records of a .jsonl file (empty when missing).
    Inputs:
     - path [str]: file
    Outputs:
     - [list]: decoded records
    Callers:
     - main [lemmy-events.py]
    """
    if not os.path.exists(path):
        return []
    return [json.loads(l) for l in open(path)]


def main ():
    src = sys.argv[1].rstrip('/')
    out = sys.argv[2] if len(sys.argv) > 2 else src
    inst = os.path.basename(src).split('-', 1)[0]
    bodies = out + '.bodies'
    os.makedirs(bodies, exist_ok=True)

    people = {}     # local person id -> key
    posts  = {}     # local post id -> key
    cmts   = {}     # local comment id -> key
    items  = {}     # key -> [ts, author, parent, body, deleted, upd]

    def person (p):
        if p:
            people[p['id']] = key(p['actor_id'])

    def add_post (p, author):
        k = key(p['ap_id'])
        posts[p['id']] = k
        body = p['name'] + '\n\n' + (p.get('body') or p.get('url') or '')
        old = items.get(k)
        if old is None or (body.strip() and not old[3].strip()):
            items[k] = [ts(p['published']), author, k, body,
                        p['deleted'], p.get('updated')]
        return k

    def add_cmt (c, author, post_k):
        k = key(c['ap_id'])
        cmts[c['id']] = k
        old = items.get(k)
        if old is None or (c['content'].strip() and not old[3].strip()):
            items[k] = [ts(c['published']), author, (c['path'], post_k),
                        c['content'], c['deleted'], c.get('updated')]
        return k

    PV = jsonl(os.path.join(src, 'posts.jsonl'))
    CV = jsonl(os.path.join(src, 'comments.jsonl'))
    ML = jsonl(os.path.join(src, 'modlog.jsonl'))

    # listings
    for v in PV:
        person(v['creator'])
        add_post(v['post'], key(v['creator']['actor_id']))
    for v in CV:
        person(v['creator'])
        add_cmt(v['comment'], key(v['creator']['actor_id']),
                key(v['post']['ap_id']))

    # people seen only in the modlog
    for e in ML:
        for f in ('commenter', 'banned_person', 'modded_person',
                  'moderator'):
            person(e.get(f))

    def who (pid):
        return people.get(pid, f'person/{inst}/{pid}')

    def mod (pid):
        return f'mod/{inst}/{pid}'

    # modlog: hidden items first, then actions
    ev, seq = [], 0
    nrem = nres = nban = nadd = nhid = 0
    for e in ML:
        t = e['type_']
        if t == 'ModRemovePost':
            p = e['post']
            if key(p['ap_id']) not in items:
                nhid += 1
            k = add_post(p, who(p['creator_id']))
            a = e['mod_remove_post']
        elif t == 'ModRemoveComment':
            c = e['comment']
            if key(c['ap_id']) not in items:
                nhid += 1
            k = add_cmt(c, key(e['commenter']['actor_id']),
                        key(e['post']['ap_id']))
            a = e['mod_remove_comment']
        elif t == 'ModBanFromCommunity':
            a = e['mod_ban_from_community']
            seq += 1
            ev.append((ts(a['when_']), seq, 'ban' if a['banned'] else 'unban',
                       str(a['id']), mod(a['mod_person_id']),
                       key(e['banned_person']['actor_id']),
                       a.get('reason') or ''))
            nban += 1
            continue
        elif t == 'ModAddCommunity':
            a = e['mod_add_community']
            if a['removed']:
                continue
            seq += 1
            ev.append((ts(a['when_']), seq, 'addmod', str(a['id']),
                       mod(a['mod_person_id']),
                       key(e['modded_person']['actor_id']), ''))
            nadd += 1
            continue
        else:
            continue
        seq += 1
        kind = 'remove' if a['removed'] else 'restore'
        if kind == 'remove':
            nrem += 1
        else:
            nres += 1
        reason = ' '.join((a.get('reason') or '').split())
        ev.append((ts(a['when_']), seq, kind, str(a['id']),
                   mod(a['mod_person_id']), k, reason))

    # items: posts (with parents) and self-deletes
    npost = ndel = 0
    for k, (t, author, parent, body, deleted, upd) in items.items():
        if isinstance(parent, tuple):           # comment: path, post
            path, post_k = parent
            ids = path.split('.')
            parent = post_k
            if len(ids) > 2:
                parent = cmts.get(int(ids[-2]), post_k)
        seq += 1
        ev.append((t, seq, 'post', k, author, parent, ''))
        npost += 1
        name = k.replace('/', '_')
        with open(os.path.join(bodies, name), 'w') as f:
            f.write('(deleted)' if deleted else (body or '(empty)'))
        if deleted:
            seq += 1
            ev.append((ts(upd) if upd else t, seq, 'delete', k, author,
                       k, ''))
            ndel += 1

    # same second: the item before any action on it
    ev.sort(key=lambda e: (e[0], e[2] != 'post', e[1]))
    with open(out + '.tsv', 'w') as f:
        for e in ev:
            f.write('\t'.join(str(x) for x in
                              (e[0], e[2], e[3], e[4], e[5], e[6])) + '\n')
    print(f'posts={npost} (hidden={nhid}) removes={nrem} restores={nres} '
          f'deletes={ndel} bans={nban} addmods={nadd} '
          f'events={len(ev)} -> {out}.tsv')


if __name__ == '__main__':
    main()
