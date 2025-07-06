local component = require("component")
local seri = require("serialization")
local event = require("event")

local tunnel = component.tunnel
local sensor = component.sensor

local xOff = -2277
local yOff = 10
local zOff = -6634

local range = 20000

print(tunnel.maxPacketSize())

tunnel.setWakeMessage("WAKEUP", true)

local function getPlayers()

    local players = {}
    for _, entity in ipairs(sensor.searchEntities(-range, -range, -range, range, range, range)) do

        if(entity.type == "player") then
            entity.pos.x = entity.pos.x + xOff
            entity.pos.y = entity.pos.y + yOff
            entity.pos.z = entity.pos.z + zOff
            players[#players+1] = entity
        end
    end
    tunnel.send(seri.serialize(players))
    return players
end

while true do
    getPlayers()
    --print(seri.serialize(getPlayers()))
    os.sleep(1)
end