-- Settings for p2p.lua (one comment per field).
-- Loaded by p2p.lua as G.

local MODE = 'simple'       -- simple | corpus (not yet)

return {
    MODE  = MODE,
    N_ACT = 20,             -- simple: number of actions
    GAP   = 3600,           -- simple: chain secs between actions
    D     = 60,             -- chain secs per round
    RMAX  = 40,             -- max rounds per action
    LANES = 6,              -- parallel lanes per step
    SEED  = 1,              -- random seed
    DUMP  = false,          -- print the 108 links and exit
    ALIAS = '/simple',      -- chain name
    BASE  = './.freechains-p2p-' .. MODE,  -- peers dir, wiped on start
    T0    = 1700000000,     -- chain time of the first action
}
