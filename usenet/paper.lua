#!/usr/bin/env lua5.4

-- Checks the newsgroup claims of tpd-21 (sec.consensus.eval) against the
-- first 10.000 messages of the comp.compilers archive:
--      3. "9 years in the newsgroup"
--      4. "The original newsgroup is 30MB in size"
--      5. "3kB for each message"
--      6. "For the newsgroup with 5000 users" (item d)
--
-- Reads yyy.mbox, the chronologically sorted archive produced by use-01.
-- (xxx.mbox is the unsorted input: 6879 of its first 10.000 are out of order.)

local MON = {
    Jan=1, Feb=2, Mar=3, Apr=4,  May=5,  Jun=6,
    Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12
}

local f   = io.open('../data/yyy.mbox')
local out = io.open('comp-10k.mbox', 'w')

function read_until (patt)
    while true do
        local l = f:read('*l')
        local ret = { string.match(l, patt) }
        if #ret > 0 then
            return table.unpack(ret)
        end
    end
end

local n      = 0
local bytes  = 0
local heads  = 0
local users  = {}
local nusers = 0
local unsorted = 0
local ts1, ts2

while true do
    local from = read_until("^From: (.*)")
    local subj = read_until("^Subject: (.*)")
    local date = read_until("^Date: (.*)")
    read_until("^$")
    local body = ''
    local term = false
    while true do
        local l = f:read('*l')
        if (not l) or string.match(l, "^From %-?%d+$") then
            term = (not l)
            break
        end
        body = body ..'\n'.. l
    end

    local ts; do
        --        "       29   Oct   1994   19 :  43 :  31"
        local p = "[^%d]*(%d+)[ -](%a+)[ -](%d+) (%d+):(%d+)"
        local d,m,y,hh,mm = string.match(date, p)
        local M
        if d then
            M = MON[m]
        else
            local p = "(%d+)/(%d+)/(%d+)"
            y,M,d = string.match(date, p)
            hh,mm = 0,0
        end
        assert(d)
        y = tonumber(y)
        if y < 1000 then
            if y < 30 then
                y = y + 2000
            else
                y = y + 1900
            end
        end
        ts = os.time({ year=y, month=M, day=d, hour=hh, min=mm, sec=0 })
    end

    n = n + 1

    local rec = ("From 0123456789")..'\n'..
                ("From: "..from)..'\n'..
                ("Subject: "..subj)..'\n'..
                ("Date: "..date)..'\n'..
                (body)..'\n'
    out:write(rec)

    -- the whole record, and the header framing alone
    bytes = bytes + #rec
    heads = heads + #("From 0123456789\nFrom: "..from.."\nSubject: "..subj.."\nDate: "..date.."\n")

    if not users[from] then
        users[from] = true
        nusers = nusers + 1
    end

    ts1 = ts1 or ts
    if ts2 and ts < ts2 then
        unsorted = unsorted + 1
    end
    ts2 = ts

    if term or n == 10000 then
        break
    end
end

out:close()
f:close()

print('messages', n)
print('out of order', unsorted)
print()

print('3. period of activity')
print('   from', os.date('%Y-%m-%d %H:%M:%S', ts1))
print('   to  ', os.date('%Y-%m-%d %H:%M:%S', ts2))
print('   days', (ts2-ts1) / (24*60*60))
print('   years', (ts2-ts1) / (365*24*60*60))
print()

print('4. archive size')
print('   records', bytes, bytes/1000000 .. 'MB')
print('   headers', heads, heads/1000000 .. 'MB')
print('   bodies ', bytes-heads, (bytes-heads)/1000000 .. 'MB')
print()

print('5. size per message')
print('   record', bytes/n)
print('   body  ', (bytes-heads)/n)
print()

print('6. users', nusers)
