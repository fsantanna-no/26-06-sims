-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE = 'simple'       -- simple | corpus (not yet)

return {
    MODE  = MODE,
    N_ACT = 20,             -- simple: number of actions
    T = {
        action = 3600,      -- simple: chain secs between actions
        relay  = 1800,      -- push delay U(0, relay) secs per hop
    },
    -- relay for ~15% forks on real gaps (2,000-gap slices, 26/10/06):
    -- adhd 52, github 65, wiki 20, usenet 11, se-veg 192; chat 0
    -- (instantaneous, ~3% forks: same-second messages only)
    -- simple: 1800 over a 3600 gap forks ~25% (exercises merges)
    LANES = 6,              -- tasks per wave, all in parallel
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 108 links and exit
    ALIAS = '/simple',      -- chain name
    BASE  = './.freechains-p2p-' .. MODE,  -- peers dir, wiped on start
    T0    = 1700000000,     -- chain time of the first action
}
