#!/usr/bin/env python3
"""
Wikimedia IRC log -> sorted event stream for p2p.lua (corpus mode).

Writes <out>.tsv with one event per line (as lemmy-events.py):
    ts  kind  id  user  target  reason
kinds:
    post   id = c<n> (log order), user = nick, target = id
bodies go to <out>.bodies/<id> (the message text).
Only `<nick>` lines are messages (as chat-simple.lua); `*nick`
actions are skipped. Times are UTC (the log has no zone).
The log has a misfiled day: events are sorted by time (stable).
usage: chat-events.py [log] [out-prefix]
"""

import calendar
import os
import re
import sys

LINE = re.compile(r'^(\d{4})(\d\d)(\d\d) \[(\d\d):(\d\d):(\d\d)\] <([\w\-]+)>\t(.*)$')


def main ():
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'data', 'wikimedia.chat')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'data', 'chat')
    bodies = out + '.bodies'
    os.makedirs(bodies, exist_ok=True)
    ev = []
    for line in open(src, errors='ignore'):
        m = LINE.match(line.rstrip('\n'))
        if not m:
            continue
        y, mo, d, hh, mm, ss, nick, msg = m.groups()
        ts = calendar.timegm((int(y), int(mo), int(d), int(hh), int(mm), int(ss)))
        cid = 'c%d' % (len(ev) + 1)
        ev.append((ts, len(ev), cid, nick))
        with open(os.path.join(bodies, cid), 'w') as f:
            f.write(msg if msg.strip() else '(empty)')
    ev.sort()
    with open(out + '.tsv', 'w') as f:
        for ts, _, cid, nick in ev:
            f.write('\t'.join((str(ts), 'post', cid, nick, cid, '')) + '\n')
    users = len({e[3] for e in ev})
    print(f'posts={len(ev)} users={users} -> {out}.tsv')


if __name__ == '__main__':
    main()
