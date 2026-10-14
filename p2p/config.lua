-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE   = 'corpus'     -- simple | corpus
local CORPUS = 'usenet'     -- corpus: chat | usenet (posts only)

-- relay secs per hop (push), U(min, max): decided 26/10/09:
-- chat 1-2 (latency), usenet 1-60; simple: 0-1800 over 3600
-- gaps (~25-31% forks; 45% on the asymmetric topology)
local RELAY = { simple = {0, 1800}, chat = {1, 2}, usenet = {1, 60} }
local KEY   = (MODE == 'simple') and 'simple' or CORPUS
local RL    = RELAY[KEY]

-- env overrides (one run per command line, no file edits):
-- LIMIT=<n>, SM=<secs>, LM=<secs>, PRESYNC=1
local function env (k, v)
    return tonumber(os.getenv(k) or '') or v
end

return {
    MODE  = MODE,
    SRC   = '../data/' .. CORPUS,  -- corpus: TSV + bodies (from p2p/)
    LIMIT = env('LIMIT', 33814),    -- corpus: first LIMIT events (usenet: all)
    N_ACT = 20,             -- simple: number of actions
    T = {
        action = 3600,      -- simple: chain secs between actions
        relay  = RL,        -- push delay U(min, max) secs per hop
        tick   = math.max(1, RL[2] // 10),  -- pulls due in one tick share waves
    },
    -- corpus runs (decided 26/10/06): chat relay 0 (instant, tick
    -- 1: same-second messages fork, ~3%); all others relay 60,
    -- tick 6 (= relay / 10); forks at 60 s: adhd 15-22%, github
    -- 12-15%, wiki 10-30%, se-veg 4-26%, usenet 1-7% (spread)
    -- simple: relay 1800 over 3600 gaps forks 25-31% (merges);
    -- tick = relay / 10
    LANES = 6,              -- tasks per wave, all in parallel
    -- local first (26/10/10): session period (secs) per link
    -- kind, 0 = always on; UUCP-like: mids dial the supers every
    -- 6 h, leaves dial their mid every 24 h (seeded phases)
    SYNC  = { SS = 0, SM = env('SM', 0), LM = env('LM', 0) },
    -- sync, post, re-sync (26/10/13): the author's leaf pulls
    -- from its primary mid right before a post, and the mid
    -- pulls the post right after (sessions as SYNC otherwise)
    PRESYNC = (os.getenv('PRESYNC') == '1'),
    -- session phases on whole SLOT secs (shared dial-in times,
    -- so pulls share waves); 0 = any time
    SLOT  = 3600,
    SWEEP = 500,            -- sweep all peers every SWEEP actions
                            -- (keeps peers ~5 MB, not ~200 MB loose)
    -- kept copies (S1, L45, keys) of a run, while it runs: env
    -- KEEP=<run> copies every KEEP_N actions to .freechains-keep/
    -- <run>-<a>; ev/ev.sh runs on every EV_N copy (background)
    KEEP   = os.getenv('KEEP'),
    KEEP_N = 5000,
    EV_N   = 10000,
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 112 links and exit
    ALIAS = '/' .. KEY,     -- chain name
    BASE  = './.freechains-p2p-' .. KEY,   -- peers dir, wiped on start
    T0    = 1700000000,     -- simple: chain time before the first action
                            -- (corpus: first event - 3600)
}
