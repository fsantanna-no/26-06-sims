-- hubs-59 topology (as drawn in hubs50.dia).
-- 5 supers, fully connected.
-- 9 mids, each on its 2 nearest supers (Mi carries i leaves).
-- 45 leaves.
-- Edge leaves also link to the neighbouring mid.
-- Peer ids (in p2p.lua): S01-S05 = 0-4, M01-M09 = 5-13,
-- leaves L14-L58 = 14-58.

-- Each peer and the peers it links to.
-- Each link is listed once, on the lower tier.
-- A leaf's first mid is its own, a second mid is the neighbour.
return {
    _ns = 5,                -- supers S01-S05
    _nm = 9,                -- mids M01-M09
    _nl = 45,               -- leaves L14-L58
    S01 = {},
    S02 = { 'S01' },
    S03 = { 'S01', 'S02' },
    S04 = { 'S01', 'S02', 'S03' },
    S05 = { 'S01', 'S02', 'S03', 'S04' },
    M01 = { 'S01', 'S02' },
    M02 = { 'S02', 'S03' },
    M03 = { 'S03', 'S04' },
    M04 = { 'S04', 'S05' },
    M05 = { 'S01', 'S05' },
    M06 = { 'S01', 'S02' },
    M07 = { 'S02', 'S03' },
    M08 = { 'S04', 'S05' },
    M09 = { 'S01', 'S05' },
    L14 = { 'M01', 'M06' },
    L15 = { 'M02', 'M07' },
    L16 = { 'M02', 'M06' },
    L17 = { 'M03', 'M08' },
    L18 = { 'M03' },
    L19 = { 'M03', 'M07' },
    L20 = { 'M04', 'M09' },
    L21 = { 'M04' },
    L22 = { 'M04' },
    L23 = { 'M04', 'M08' },
    L24 = { 'M05', 'M01' },
    L25 = { 'M05' },
    L26 = { 'M05' },
    L27 = { 'M05' },
    L28 = { 'M05', 'M09' },
    L29 = { 'M06', 'M02' },
    L30 = { 'M06' },
    L31 = { 'M06' },
    L32 = { 'M06' },
    L33 = { 'M06' },
    L34 = { 'M06', 'M01' },
    L35 = { 'M07', 'M03' },
    L36 = { 'M07' },
    L37 = { 'M07' },
    L38 = { 'M07' },
    L39 = { 'M07' },
    L40 = { 'M07' },
    L41 = { 'M07', 'M02' },
    L42 = { 'M08', 'M04' },
    L43 = { 'M08' },
    L44 = { 'M08' },
    L45 = { 'M08' },
    L46 = { 'M08' },
    L47 = { 'M08' },
    L48 = { 'M08' },
    L49 = { 'M08', 'M03' },
    L50 = { 'M09', 'M05' },
    L51 = { 'M09' },
    L52 = { 'M09' },
    L53 = { 'M09' },
    L54 = { 'M09' },
    L55 = { 'M09' },
    L56 = { 'M09' },
    L57 = { 'M09' },
    L58 = { 'M09', 'M04' },
}
