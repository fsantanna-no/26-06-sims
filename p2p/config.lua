-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE = 'simple'       -- simple | corpus (not yet)

return {
    MODE  = MODE,
    N_ACT = 20,             -- simple: number of actions
    T = {
        action = 3600,      -- simple: chain secs between actions
        relay  = 1800,      -- push delay U(0, relay) secs per hop
        tick   = 180,       -- pulls due in one tick share waves
    },
    -- corpus runs (decided 26/10/06): chat relay 0 (instant, tick
    -- 1: same-second messages fork, ~3%); all others relay 60,
    -- tick 6 (= relay / 10); forks at 60 s: adhd 15-22%, github
    -- 12-15%, wiki 10-30%, se-veg 4-26%, usenet 1-7% (spread)
    -- simple: relay 1800 over 3600 gaps forks 25-31% (merges);
    -- tick = relay / 10
    LANES = 6,              -- tasks per wave, all in parallel
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 108 links and exit
    ALIAS = '/simple',      -- chain name
    BASE  = './.freechains-p2p-' .. MODE,  -- peers dir, wiped on start
    T0    = 1700000000,     -- chain time of the first action
}
