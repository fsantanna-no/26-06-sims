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

return {
    MODE  = MODE,
    SRC   = '../data/' .. CORPUS,  -- corpus: TSV + bodies (from p2p/)
    LIMIT = 5000,           -- corpus: first LIMIT events
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
    SWEEP = 500,            -- sweep all peers every SWEEP actions
                            -- (keeps peers ~5 MB, not ~200 MB loose)
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 112 links and exit
    ALIAS = '/' .. KEY,     -- chain name
    BASE  = './.freechains-p2p-' .. KEY,   -- peers dir, wiped on start
    T0    = 1700000000,     -- simple: chain time before the first action
                            -- (corpus: first event - 3600)
}
