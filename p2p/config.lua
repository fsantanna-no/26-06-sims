-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE   = 'corpus'     -- simple | corpus
local CORPUS = 'chat'       -- corpus: chat | usenet (posts only)

-- relay secs per hop (push), U(min, max): decided 26/10/09:
-- chat 1-2 (latency), usenet 1-60; simple: 0-1800 over 3600
-- gaps (~25-31% forks; 45% on the asymmetric topology)
local RELAY = { simple = {0, 1800}, chat = {1, 2}, usenet = {1, 60} }
local KEY   = (MODE == 'simple') and 'simple' or CORPUS
local RL    = RELAY[KEY]

-- env overrides (one run per command line, no file edits):
-- LIMIT=<n>, SM=<secs>, LM=<secs>, PRESYNC=1, MERGES=1, MIX=1,
-- CHURN=1, DEFER=1, EV_N=<n>, CKPT_N=<n>, RESUME=1, BASE=<dir>
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
    -- merge-only pulls (26/10/14): also pull when the source HEAD
    -- is unseen by the receiver (as git), not only on a missing
    -- action; else equal posts in other merges never reconcile
    -- and hard fork after 7 days (freechains 261014-merge-order)
    MERGES = (os.getenv('MERGES') == '1'),
    -- mixed classes (26/10/14): each mid and its leaves share one
    -- class, 49/27/24 of the leaves (22/12/11; M4, M6 swapped so
    -- M1 has a ps neighbour): on = always on
    -- (mid too), ps = sessions + sync around posts (PRESYNC),
    -- lf = sessions only; supers always on; needs SM, LM
    MIX = (os.getenv('MIX') == '1') and {
        M1 = 'on', M3 = 'on', M9 = 'on',
        M2 = 'ps', M6 = 'ps', M8 = 'ps',
        M4 = 'lf', M5 = 'lf', M7 = 'lf',
    } or nil,
    -- churn (26/10/14): seeded outages per peer, own RNG (the
    -- run's random sequence is kept); availability by tier and
    -- class; leaves with sessions have none (sessions are their
    -- uptime); downtime Pareto (median `down`, shape `alpha`,
    -- capped below the 7-day window); a leaf whose mid is down
    -- uses its backup mid, a mid whose supers are all down its
    -- ring; reconnects pull from every primary neighbour
    CHURN = (os.getenv('CHURN') == '1') and {
        S = 0.99,           -- supers
        on = 0.95,          -- always-on mids and leaves
        mid = 0.90,         -- session mids (ps, lf)
        down = 3600,        -- median outage (secs)
        alpha = 2.5,        -- Pareto shape (26/10/23: 1.5 -> 2.5)
        cap = 3 * 86400,    -- longest outage (secs)
        seed = 1,
    } or nil,
    -- defer (26/10/23): a down leaf posts at its reconnect
    -- (chat: no offline posts); needs CHURN; authors placed up
    -- front, so the random sequence differs from DEFER=0
    DEFER = (os.getenv('DEFER') == '1'),
    -- session phases on whole SLOT secs (shared dial-in times,
    -- so pulls share waves); 0 = any time
    SLOT  = 3600,
    SWEEP = 500,            -- sweep all peers every SWEEP actions
                            -- (keeps peers ~5 MB, not ~200 MB loose)
    -- kept copies (S1, L45, keys) of a run, while it runs: env
    -- KEEP=<run> copies every KEEP_N actions to .freechains-keep/
    -- <run>-<a>; ev/ev.sh runs on every EV_N copy (background;
    -- 0: off, run it on the kept copies after: ~2.5 GB at 20k)
    KEEP   = os.getenv('KEEP'),
    KEEP_N = 5000,
    EV_N   = env('EV_N', 10000),
    -- checkpoint every CKPT_N actions (0: off): the run state
    -- (`state.lua`) and a copy of BASE at <BASE>.ckpt; the RNG
    -- is reseeded there (SEED, a), so a resumed run equals an
    -- uninterrupted one; RESUME=1 restarts from the checkpoint
    -- (26/10/17, plan 261017-resume)
    CKPT_N = env('CKPT_N', 5000),
    RESUME = (os.getenv('RESUME') == '1'),
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 112 links and exit
    ALIAS = '/' .. KEY,     -- chain name
    BASE  = os.getenv('BASE') or ('./.freechains-p2p-' .. KEY),   -- peers dir, wiped on start
    T0    = 1700000000,     -- simple: chain time before the first action
                            -- (corpus: first event - 3600)
}
