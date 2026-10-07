#!/usr/bin/env python3
"""
comp.compilers mbox -> sorted event stream for p2p.lua (corpus mode).

Writes <out>.tsv with one event per line (as lemmy-events.py):
    ts  kind  id  user  target  reason
kinds:
    post   id = u<n> (archive order), user = From, target = id
bodies go to <out>.bodies/<id>: the record, as use-simple.lua
(From, Subject, Date headers + body).
Times (UTC, seconds):
  - full dates: parsed with their zone (email.utils)
  - date-only (`YYYY/MM/DD`, ~10k records, 1995-2000): spread
    evenly over their day, in archive order
  - 2000-2007 dates are stamped at moderation release (US
    Eastern for every author): each batch (gaps < BATCH secs)
    is spread evenly over the gap before it, order kept, its
    last message keeps its stamp
usage: use-events.py [mbox] [out-prefix]
"""

import calendar
import datetime as dt
import email.utils
import os
import re
import sys

BATCH = 600                                         # secs within a batch
A = calendar.timegm((2000, 1, 1, 0, 0, 0))          # moderation stamps
B = calendar.timegm((2008, 1, 1, 0, 0, 0))
SEP = re.compile(r'^From -?\d+$')


def records (src):
    """
    Records of the mbox, in archive order.
    Inputs:
     - src [str]: mbox path
    Outputs:
     - [list]: (from, subject, date, body) per record
    Callers:
     - main [use-events.py]
    """
    out, hdr, body, state = [], None, [], None
    for line in open(src, errors='ignore'):
        line = line.rstrip('\n')
        if SEP.match(line):
            if hdr is not None:
                out.append((hdr.get('from', ''), hdr.get('subject', ''),
                            hdr.get('date', ''), '\n'.join(body)))
            hdr, body, state = {}, [], 'hdr'
        elif state == 'hdr':
            if line == '':
                state = 'body'
            elif ':' in line and not line.startswith((' ', '\t')):
                k, v = line.split(':', 1)
                hdr.setdefault(k.lower(), v.strip())
        elif state == 'body':
            body.append(line)
    if hdr is not None:
        out.append((hdr.get('from', ''), hdr.get('subject', ''),
                    hdr.get('date', ''), '\n'.join(body)))
    return out


def stamp (date):
    """
    A Date header -> (epoch secs, exact) or (day start, False).
    Inputs:
     - date [str]: header value
    Outputs:
     - [tuple]: (secs, True) for full dates, (day secs, False) for
       `YYYY/MM/DD`, (None, False) when unparsed
    Callers:
     - main [use-events.py]
    """
    try:
        return email.utils.parsedate_to_datetime(date).timestamp(), True
    except Exception:
        pass
    m = re.match(r'^(\d{4})/(\d\d)/(\d\d)', date)
    if m:
        y, mo, d = map(int, m.groups())
        return calendar.timegm((y, mo, d, 0, 0, 0)), False
    return None, False


def main ():
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'data', 'yyy.mbox')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'data', 'usenet')
    bodies = out + '.bodies'
    os.makedirs(bodies, exist_ok=True)
    recs = records(src)
    ev, days, nodate = [], {}, 0
    for i, (frm, subj, date, body) in enumerate(recs):
        ts, exact = stamp(date)
        if ts is None:
            nodate += 1
            continue
        uid = 'u%d' % (i + 1)
        with open(os.path.join(bodies, uid), 'w') as f:
            f.write('From: %s\nSubject: %s\nDate: %s\n%s\n' % (frm, subj, date, body))
        user = email.utils.parseaddr(frm)[1] or frm or 'anonymous'
        e = [ts, i, uid, user]
        ev.append(e)
        if not exact:
            days.setdefault(ts, []).append(e)
    # date-only: spread evenly over the day, archive order
    for day, es in days.items():
        for k, e in enumerate(es):
            e[0] = day + (k + 0.5) * 86400 / len(es)
    ev.sort(key=lambda e: (e[0], e[1]))
    # moderation batches 2000-2007: spread over the gap before each
    ts = [e[0] for e in ev]
    new, i, nb, nm = [], 0, 0, 0
    while i < len(ts):
        j = i
        while j + 1 < len(ts) and A <= ts[j] < B and ts[j+1] - ts[j] < BATCH:
            j += 1
        k = j - i + 1
        if k > 1 and new:
            prev, end = new[-1], ts[j]
            new += [prev + (end - prev) * x / k for x in range(1, k + 1)]
            nb, nm = nb + 1, nm + k
        else:
            new += ts[i:j+1]
        i = j + 1
    with open(out + '.tsv', 'w') as f:
        for e, t in zip(ev, new):
            f.write('\t'.join((str(int(t)), 'post', e[2], e[3], e[2], '')) + '\n')
    users = len({e[3] for e in ev})
    print(f'records={len(recs)} posts={len(ev)} undated={nodate} '
          f'date-only={sum(len(v) for v in days.values())} in {len(days)} days '
          f'batches={nb} ({nm} msgs) users={users} -> {out}.tsv')


if __name__ == '__main__':
    main()
