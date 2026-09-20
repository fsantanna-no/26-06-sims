# 26-06-sims

Simulations for the Freechains paper (`26-06-vcs`): replays of real forum
archives over the `freechains` CLI (`/x/x/freechains/vcs`, on `PATH`).

- `chat/`: Wikimedia IRC channel (155k messages); `chat-simple.lua` (open
  chain), `chat-02.lua` (gated chain with reps/likes/begs); `FINDINGS.md`
- `usenet/`: comp.compilers mbox; `use-simple.lua`; `RESULTS.md`
- `se/`: Stack Exchange dumps (coffee, vegetarianism); `se-simple.lua`;
  `RESULTS.md`
- `wiki/`: Wikipedia article histories, reverts as revokes;
  `wiki-simple.lua`; `RESULTS.md`
- `github/`: GitHub event streams; `gh-simple.lua`; `RESULTS.md`
- `*/paper.lua`: checks the numbers quoted in the paper

Datasets are git-ignored; `fetch.sh` downloads them into `data/` and checks
their hashes. Runs use a shared root at `.freechains/` (ignored) and write
`*/logs/` (ignored). Each driver reads its parameters from environment
variables (e.g. `N=1000 lua5.4 chat-simple.lua`).
