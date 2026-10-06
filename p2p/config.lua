-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE = 'simple'       -- simple | corpus (not yet)

return {
    MODE  = MODE,
    N_ACT = 20,             -- simple: number of actions
    T = {
        action = 3600,      -- simple: chain secs between actions
        sync   = 1800,      -- each peer syncs every T.sync secs
    },
    RMAX  = 20,             -- max T.action periods of the drain
    LANES = 6,              -- tasks per wave, all in parallel
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 108 links and exit
    ALIAS = '/simple',      -- chain name
    BASE  = './.freechains-p2p-' .. MODE,  -- peers dir, wiped on start
    T0    = 1700000000,     -- chain time of the first action
}
