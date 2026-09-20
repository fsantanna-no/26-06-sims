#!/usr/bin/env lua5.4

-- Checks claims 3, 4 and 5 of tpd-21 (sec.consensus.eval) against the
-- first 10.000 messages of the Wikimedia chat archive:
--      3. "which represent 3 months of activity in the chat"
--      4. "The original chat archive is 800kB in size"
--      5. "80B for each message"

local out = io.open('wikimedia-10k.chat', 'w')

local n     = 0
local lines = 0
local bytes = 0
local msgs  = 0
local users = {}
local nusers = 0
local ts1, ts2

for l in io.lines('../data/wikimedia.chat') do
    local y,m,d,hh,mm,ss,user,msg = string.match(l, "(%d%d%d%d)(%d%d)(%d%d) %[(%d%d):(%d%d):(%d%d)%] %<([%a%d-_]+)%>\t(.*)")
    if y then
        n = n + 1
        out:write(l, '\n')

        -- +1 for the newline, as counted by the file on disk
        lines = lines + #l + 1
        msgs  = msgs + #msg

        if not users[user] then
            users[user] = true
            nusers = nusers + 1
        end

        local ts = os.time({ year=y, month=m, day=d, hour=hh, min=mm, sec=ss })
        ts1 = ts1 or ts
        ts2 = ts

        if n == 10000 then
            break
        end
    end
end

out:close()

print('messages', n)
print('users', nusers)
print()

print('3. period of activity')
print('   from', os.date('%Y-%m-%d %H:%M:%S', ts1))
print('   to  ', os.date('%Y-%m-%d %H:%M:%S', ts2))
print('   days', (ts2-ts1) / (24*60*60))
print('   months', (ts2-ts1) / (30*24*60*60))
print()

print('4. archive size')
print('   full lines', lines, lines/1000 .. 'kB')
print('   payloads  ', msgs, msgs/1000 .. 'kB')
print()

print('5. size per message')
print('   full line', lines/n)
print('   payload  ', msgs/n)
