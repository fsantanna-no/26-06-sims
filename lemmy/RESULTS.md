# lemmy-simple: Lemmy community replay (adhd@lemmy.dbzer0.com)

- corpus: `adhd@lemmy.dbzer0.com` as seen by its home instance,
  2023-06-12 to 2026-10-03; 1,357 posts + 30,007 comments
  listed, 58 hidden items recovered from the modlog; 33,027
  events; 7,447 keys (members + moderators)
- first corpus with revoke REASONS by named (id) moderators,
  author self-deletes, and a second instance (feddit.org)
  holding the same community
- mapping: post = signed by actor id; modlog removal = revoke
  by the moderator's own key, `--why=<reason>`, amount = 1000
  + likes; restore = unrevoke `--file`; author delete = free
  self-revoke; no votes (not public)
- freechains: v0.21.0 (`--version` does not tell builds apart)
    - `main` 5e04aa4 (26/10/03): first open run
    - 260914-tree-trash (installed 26/10/05 11:56): reruns

## OPEN chain, home stream, `main` build (26/10/05)

- log: `logs/open-main.log`
- 33,027 events in 14h50m; zero skip_t, 11 skip_r (revoke of
  an already revoked item), zero clamps
- 31,422 posts, 170 revokes, 2 restores, 1,277 self-revokes,
  138 bans/unbans (counted only)

| N     | ev avg | revokes | deletes | sweep  | packed |
|-------|--------|---------|---------|--------|--------|
|  2000 | 0.169s |       1 |      47 |    16s |   2 MB |
|  8000 | 0.345s |      65 |     278 |   333s |  15 MB |
| 16000 | 0.596s |     104 |     605 |  1407s |  39 MB |
| 24000 | 0.861s |     135 |     874 |  3097s |  81 MB |
| 32000 | 1.146s |     157 |   1,197 |  5454s | 135 MB |
| END   |        |     170 |   1,277 |        | 167 MB |

- LATENCY GROWS LINEARLY: 0.17 -> 1.15 s/ev over 16x N,
  unlike GitHub (flat 0.21 -> 0.26 s over 94k); sweeps grow
  ~quadratically and take 31,865 s = 60% of the run
    - same shape as GitHub on the old blob build (1.17 s/ev
      at 36k, 2 h sweeps); `main` lacks the 260914-tree-trash
      state (checked): rerun on tree-trash pending
- revokes: 0.54% of posts (GitHub 5.1%); all 172 revokes +
  unrevokes signed by the moderators' own keys, in debt
  (open chain)
- self-revokes: 1,277 (4.1% of posts), 7.5x the moderator
  revokes: forgetting dominates moderation
- revoke reasons: "Rule 1" (No Party Pooping) and variants
  82, "Community rule 1" 34, slurs/ableism 9, wrong or
  off-topic community 8, rude 4, spam 3, none 8
- restores: 2 (1.2% of removals)
