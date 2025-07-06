local component = require("component")
local event = require("event")

local t1Address = ""
local t2Address = ""

local t1 = component.proxy(t1Address)
-- local t2 = component.proxy(t2Address)
local m = component.modem

local p1 = 1201
local p2 = 1202

m.setWakeMessage("WAKEUP", true)

m.open(1200)
m.open(p1)
m.open(p2)

local function onModemMessage(_, rAddress, sAddress, senderPort, _, message)
    if senderPort == p1 or senderPort == p2 then
        
    else
        --print(rAddress .. " " .. message)
        if rAddress == t1Address then
            m.broadcast(p1, message)
            --print(message)
        end
        if rAddress == t2Address then
            m.broadcast(p2, message)
            --print(message)
        end
    end
end

event.listen("modem_message", onModemMessage)

while true do
    t1.send("WAKEUP")
    --t2.send("WAKEUP")
    os.sleep(1)
end