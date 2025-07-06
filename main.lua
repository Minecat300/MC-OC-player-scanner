local computer = require("computer")

--computer.shutdown()

local component = require("component")
local seri = require("serialization")
local event = require("event")
local io = require("io")
local term = require("term")
local fs = require("filesystem")
local thread = require("thread")

local t = component.tunnel
local m = component.modem
local gpu = component.gpu

gpu.setResolution(80, 25)

t.setWakeMessage("WAKEUP", true)

local ports = {1200, 1201, 1202, 1203}
local dims = {"Overworld", "Barnarda C", "Proxima B"}
local playerBlacklist = {"Minecat_300", "V3rdantM0ss", "Maximus_Meridiuz", "housetable"}
local commands = {"allPlayers", "help", "reboot", "shutdown", "clearLogs", "openPlayerLog", "showPointOfIntrests"}

local saveRate = 30
local blockSize = 500
local maxBlockAmount = 10

local POIMaxDist = 200

local logDrive = "/mnt/b7f/"
local playerLogFolder = logDrive .. "playerLogs/"
local POILogFolder = logDrive .. "POILogs/"

local function mergeTables(table1, table2)
    table.move(table2, 1, #table2, #table1 + 1, table1)
    return table1
end

local function openFile(filePath)
    local file = io.open(filePath, "r")
    local data = {}

    if file then
        local fileContent = file:read("*all")
        file:close()

        data = seri.unserialize(fileContent)
        if not data then
            print("Error: Failed to unserialize the file content")
            data = {}
        end
    else
        file = io.open(filePath, "w")
        if file then
            file:close()
        else
            print("Error: Failed to create file")
        end
    end
    return data
end

local function writeFile(filePath, data)
    local serializedData = seri.serialize(data)
    local file = io.open(filePath, "w")
    if file then
        file:write(serializedData)
        file:close()
    else
        print("Error: Failed to open file for writing.")
    end
end

local function getLog(path, blocks)
    local returnTable = {}
    local tmpTable = {}
    local tmp1 = {}
    local tmp2 = -1
    for player in fs.list(path) do
        tmpTable = {}
        tmp1 = {}
        tmp2 = -1
        for block in fs.list(path .. player) do
            if blocks == "last" then
                if tonumber(block) > tmp2 then
                    tmp2 = tonumber(block)
                    tmp1 = openFile(path .. player .. "/" .. block)
                end
            end
            if blocks == "all" then
                table.insert(tmpTable, block)
            end
        end
        if blocks == "all" then
            table.sort(tmpTable)
            for _, block in ipairs(tmpTable) do
                tmp1 = mergeTables(tmp1, openFile(path .. player .. "/" .. block))
            end
        end
        returnTable[player] = tmp1
    end
    return returnTable
end

local function getFileAmount(path)
    local fileCount = 0
    for file in fs.list(path) do
        fileCount = fileCount + 1
    end
    return fileCount
end

local function saveLogsToDisk(path, data, blocks)
    
    if next(data) == nil then
        return {}
    end

    local blockWrite = 0
    local count = 0
    local newTable = {}
    local tmpI = 0
    local returnTable = {}

    for name, player in pairs(data) do
        
        if not fs.exists(path .. name) then
            fs.makeDirectory(path .. name)
            blockWrite = 1

        else
            if blocks == "last" then
                blockWrite = getFileAmount(path .. name)
            end
            if blocks == "all" then
                fs.remove(path)
                os.sleep(0.1)
                fs.makeDirectory(path)
                blockWrite = 1
            end
        end
        if #player > blockSize then
            count = 0
            newTable = {}
            for i, item in ipairs(player) do
            
                if count >= blockSize then
                    writeFile(path .. name .. "/" .. blockWrite + math.ceil(i/blockSize)-1, newTable)
                    --print(path .. name .. "/" .. blockWrite + math.ceil(i/blockSize)-1, newTable)
                    count = 0
                    newTable = {}
                end

                count = count + 1
                table.insert(newTable, item)

                tmpI = i + 1
            end
            writeFile(path .. name .. "/" .. blockWrite + math.ceil(tmpI/blockSize)-1, newTable)
            --print(path .. name .. "/" .. blockWrite + math.ceil(tmpI/blockSize)-1, newTable)
            returnTable[name] = newTable
        else
            writeFile(path .. name .. "/" .. blockWrite, player)
            --print(path .. name .. "/" .. blockWrite, player)
            returnTable[name] = player
        end
    end
    return returnTable
end

local function capBlockAmount(path, amount)
    local fileCount = 0
    local files = {}
    local absPath = ""
    for player in fs.list(path) do
        fileCount = getFileAmount(path .. player)
        if fileCount > amount then
            absPath = path .. player .. "/"
            files = {}
            for file in fs.list(path .. player) do
                if tonumber(file) <= fileCount - amount then
                    fs.remove(absPath .. file)
                else
                    table.insert(files, file)
                end
            end
            table.sort(files)
            for _, file in ipairs(files) do
                fs.rename(absPath .. file, absPath .. file - (fileCount - amount))
            end
        end
    end
end

local playerLogTable = getLog(playerLogFolder, "last")
local POILogTable = getLog(POILogFolder, "last")

if not fs.exists(playerLogFolder) then
    fs.makeDirectory(playerLogFolder)
end
if not fs.exists(POILogFolder) then
    fs.makeDirectory(POILogFolder)
end

for _, p in ipairs(ports) do
    m.open(p)
end

m.broadcast(1200, "WAKEUP")

local function utils_Set(list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end

local _set = utils_Set(ports)
local _playerBlacklist = utils_Set(playerBlacklist)
local _commands = utils_Set(commands)

local function checkForPOI(player, oldPlayer)

    local chunkX = player.x // POIMaxDist
    local chunkZ = player.z // POIMaxDist
    local chunk = chunkX .. "," .. chunkZ .. "," .. player.dim

    local log = POILogTable[oldPlayer.name]
    if log[chunk] then
        local poi = log[chunk]
        poi.amount = poi.amount + 1
        poi.x = poi.x + player.x
        poi.y = poi.z + player.y
        poi.z = poi.z + player.z

        local deltaX = poi.x / poi.amount - player.x
        local deltaZ = poi.z / poi.amount - player.z

        poi.diversity = poi.diversity + math.floor(math.sqrt(deltaX*deltaX + deltaZ*deltaZ)*100)/100

        log[chunk] = poi
    else
        local poi = {
            chunk = chunk,
            x = player.x,
            y = player.y,
            z = player.z,
            dim = player.dim,
            amount = 1,
            diversity = 0
        }
        log[chunk] = poi
    end

    POILogFolder[oldPlayer.name] = log
end

local function logPlayer(player, sPort)
    local time = math.floor(os.time())

    local log = {}

    if playerLogTable[player.name] then
        log = playerLogTable[player.name]
    end

    if #log == 0 then
        local newPlayer = {
            x = math.floor(player.pos.x * 100)/100,
            y = math.floor(player.pos.y * 100)/100,
            z = math.floor(player.pos.z * 100)/100,
            dim = sPort - 1200,
            startTime = time,
            endTime = time
        }
        table.insert(log, newPlayer)
    else
        local oldPlayer = log[#log]
        if oldPlayer then

            local newPlayer = {
                x = math.floor(player.pos.x * 100)/100,
                y = math.floor(player.pos.y * 100)/100,
                z = math.floor(player.pos.z * 100)/100,
                dim = sPort - 1200,
                startTime = time,
                endTime = time
            }

            if not (oldPlayer.x == newPlayer.x and oldPlayer.y == newPlayer.y and oldPlayer.z == newPlayer.z and oldPlayer.dim == sPort - 1200) then
                table.insert(log, newPlayer)
                checkForPOI(newPlayer, player)
            else
                oldPlayer.endTime = time
                log[#log] = oldPlayer
            end
        end
    end

    playerLogTable[player.name] = log

end

local players = {}

local function handlePLayerData(player, sPort)
    local newPlayer = {
        name = player.name,
        x = math.floor(player.pos.x),
        y = math.floor(player.pos.y),
        z = math.floor(player.pos.z),
        dim = sPort - 1200
    }
    players[player.name] = newPlayer

    logPlayer(player, sPort)
end

local function onModemMessage(_, rAddress, sAddress, sPort, _, message)
    if _set[sPort] then
        local oldPlayers = seri.unserialize(message)
        for _, player in ipairs(oldPlayers) do
            if not _playerBlacklist[player.name] then
                handlePLayerData(player, sPort)
            end
        end
    else

    end
end

local function drawPlayers()
    term.clear()
    local i = 1
    for _, player in pairs(players) do
        gpu.set(1, i, dims[player.dim] .. ": " .. player.name .. ": X: " .. player.x .. " Y: " .. player.y .. " Z: " .. player.z)
        i = i + 1
    end
end

local function checkAllPlayers()
    while true do
        m.broadcast(1200, "WAKEUP")
        drawPlayers()
        os.sleep(1)
    end
end

local function openHelp()
    print("")
    print("allPlayers: Shows all the players in game and their position")
    print("help: opens this menu")
    print("reboot: Reboots the computer")
    print("shutdown: Turns off the computer")
    print("clearLogs: Clears all the log data (Note: it will also reboot the computer)")
    print("openPlayerLog: Opens and shows the log of a specific player")
    print("showPointOfIntrests: Shows potential points of intrest like bases")
    print("")
end

local function deleteAllLogs()
    fs.remove(playerLogFolder)
    fs.remove(POILogFolder)
    os.sleep(0.2)
    fs.makeDirectory(POILogFolder)
    fs.makeDirectory(playerLogFolder)
    os.sleep(0.2)
    computer.shutdown(true)
end

local function showPlayerLog()
    local awnser

    local file = getLog(playerLogFolder, "all")

    repeat
        print("enter Player:")
        awnser = io.read()
        if not (file[awnser .. "/"] or awnser == "exit") then
            print("No data of this player. try again or exit")
        end
    until file[awnser .. "/"] or awnser == "exit"

    if awnser == "exit" then
        return
    end

    local log = file[awnser .. "/"]

    gpu.setResolution(gpu.maxResolution())

    term.clear()

    for _, item in ipairs(log) do
        local hours = (item.startTime // 1000 + 6) % 24
        local minutes = (item.startTime % 1000) * 60 // 1000
        local time =  string.format("%02d:%02d", hours, minutes)
        local day = item.startTime // 24000
        print(dims[item.dim] .. ": X: " .. item.x .. " Y: " .. item.y .. " Z: " .. item.z .. " At: " .. time .. " Day: " .. day)
    end

    print("press enter to exit")
    io.read()

    computer.shutdown(true)
end

local function showPOILogs()
    
end

local function commandRunner()
    local awnser

    repeat
        print("enter command:")
        awnser = io.read()
        if not _commands[awnser] then
            print("Not a command. try again.")
        end
    until _commands[awnser]

    if awnser == commands[1] then checkAllPlayers() end
    if awnser == commands[2] then openHelp() end
    if awnser == commands[3] then computer.shutdown(true) end
    if awnser == commands[4] then computer.shutdown() end
    if awnser == commands[5] then deleteAllLogs() end
    if awnser == commands[6] then showPlayerLog() end
    if awnser == commands[7] then showPOILogs() end

end
thread.create(function()
    while true do
        POILogTable = saveLogsToDisk(POILogFolder, POILogTable, "last")
        playerLogTable = saveLogsToDisk(playerLogFolder, playerLogTable, "last")
        capBlockAmount(playerLogFolder, maxBlockAmount)
        os.sleep(saveRate)
    end
end)

event.listen("modem_message", onModemMessage)

term.clear()
term.setCursor(1, 1)

print("Please select a command to run:")

for _, command in ipairs(commands) do
    print(command)
end

print("")

while true do
    commandRunner()
    os.sleep(0.2)
end