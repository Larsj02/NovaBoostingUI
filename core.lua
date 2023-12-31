local addonName = ...

local idToSlot = {}
for name, slotId in pairs(Enum.ItemRedundancySlot) do
    idToSlot[slotId] = name
end
local fontSize = select(2, GetChatWindowInfo(1))
local addonPrefix = string.format("[|TInterface\\Addons\\NovaBoostingUI\\Images\\Logo.png:%d|t|cFFEF9009%s|r]", fontSize, addonName)
local function printMessage(msg, ...)
    print(string.format("%s: " .. msg, addonPrefix, ...))
end

local openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0")

local function Nova_IterateGroup(reversed, forceParty)
    local unit = (not forceParty and IsInRaid()) and 'raid' or 'party'
    local numGroupMembers = unit == 'party' and GetNumSubgroupMembers() or GetNumGroupMembers()
    local i = reversed and numGroupMembers or (unit == 'party' and 0 or 1)
    return function()
        local ret
        if i == 0 and unit == 'party' then
            ret = 'player'
        elseif i <= numGroupMembers and i > 0 then
            ret = unit .. i
        end
        i = i + (reversed and -1 or 1)
        return ret
    end
end

local function throwEvent(subEvent, data, db)
    WeakAuras.ScanEvents("NOVA_INTERNAL", subEvent, data, db.active)
end

local function checkProgress(db)
    if db.dungeonCount == db.maxDungeons then
        db.active = false
        local time = GetTime() - db.startTime
        local formattedTime = string.format("%02d:%02d:%02d", time / 3600, (time / 60) % 60, time % 60)
        local formattedCut = BreakUpLargeNumbers(db.lastTitle.cut)
        local formattedCutPerHour = BreakUpLargeNumbers(db.lastTitle.cut / (time / 60 / 60))
        printMessage("the Boost took %s and you made %s Gold (%s Gold per Hour)", formattedTime, formattedCut, formattedCutPerHour)
        throwEvent("RESET", nil, db)
    end
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then
            NovaSaved = NovaSaved or {}
            self.db = NovaSaved
            if self.db.active then
                printMessage("Boost Still Active from Last Session use /nb last to show last data")
            end
        end
    elseif event == "CHALLENGE_MODE_START" then
        if self.db.dungeonCount == 0 then
            self.db.startTime = GetTime()
        end
        if self.db.active then
            throwEvent("DUNGEON", {count = self.db.dungeonCount, max = self.db.maxDungeons}, self.db)
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if self.db.active then
            self.db.dungeonCount = self.db.dungeonCount + 1
            checkProgress(self.db)
            throwEvent("DUNGEON", {count = self.db.dungeonCount, max = self.db.maxDungeons}, self.db)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHALLENGE_MODE_START")
f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
f:SetScript("OnEvent", OnEvent)

function f.OnGearUpdate()
    local db = f.db
    local data = {}
    for unit in Nova_IterateGroup() do
        local uGear = openRaidLib.GetUnitGear(unit)
        local uScore = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        if uGear then
            local ilvl = uGear.ilevel
            local score = uScore and uScore.currentSeasonScore or db.lastPlayers[unit] and db.lastPlayers[unit][2] or 0
            data[unit] = {ilvl, score}
        end
    end
    throwEvent("PLAYERS", data, db)
    db.lastPlayers = data
end

openRaidLib.RegisterCallback(f, "GearUpdate", "OnGearUpdate")

SLASH_NBUI1 = "/nb"
SLASH_NBUI2 = "/boost"

SlashCmdList.NBUI = function(msg)
    local db = f.db
    if msg == "reset" then
        throwEvent("RESET", nil, db)
    elseif msg == "players" then
        printMessage("Requesting Player Data")
        openRaidLib.RequestAllData()
        if db.lastPlayers then throwEvent("PLAYERS", db.lastPlayers, db) end
    elseif msg == "last" then
        throwEvent("PLAYERS", db.lastPlayers, db)
        throwEvent("BOOST", db.lastTitle, db)
        throwEvent("DUNGEON", {count = db.dungeonCount, max = db.maxDungeons}, db)
    elseif msg == "start" then
        db.active = true
        db.startTime = GetTime()
        printMessage("Boost started")
    elseif msg == "stop" then
        if db.active then
            db.dungeonCount = db.maxDungeons
            checkProgress(db)
        else
            printMessage("There is no active Boost")
        end
    elseif msg == "help" then
        printMessage("/nb and /boost can be used as Prefix")
        printMessage("/nb help to show this message")
        printMessage("/nb reset to reset data")
        printMessage("/nb players to force update players")
        printMessage("/nb last to show last data")
        printMessage("/nb start | stop to start or stop the boost")
        printMessage("/nb calc <cut> to calculate cut (15%%)")
        printMessage("/nb check <ilvl> to check if you can trade")
        printMessage("/nb <Key Message> to update the title and cut")
    elseif msg:match("^check") then
        local minIlvl = tonumber(msg:match("(%d+)$"))
        local data = {}
        for slot = 0, 16 do
            local cHWM = C_ItemUpgrade.GetHighWatermarkForSlot(slot)
            if cHWM < minIlvl then
                data[slot] = {
                    name = idToSlot[slot]:gsub("%u", " %1"),
                    ilvl = cHWM
                }
            end
        end
        throwEvent("CHECK", data, db)
        printMessage("Checking for non tradeable Slots (ilvl < %d)", minIlvl)
    elseif msg:match("^calc") then
        local cut = msg:match("calc (.+)"):gsub("%p", ""):gsub("[kK]", "000")
        printMessage("Your cut would be %s Gold", BreakUpLargeNumbers(tonumber(cut) * 0.15))
    else
        local title = msg:match(":keystone_nova:%s+(.+):[ha]")
        local count = title:match("(%d+)x")
        local cut = msg:match(":goldss:%s+(.+)"):gsub("%p", ""):gsub("[kK]", "000")
        if (not title) or (not cut) then
            printMessage("Invalid Syntax use /nb help for more information")
            return
        end
        cut = tonumber(cut) * 0.15
        local data = {
            title = title,
            cut = cut,
            count = count
        }
        throwEvent("BOOST", data, db)
        db.lastTitle = data
        db.dungeonCount = 0
        db.maxDungeons = tonumber(count) or 1
        printMessage("Set Title to %s and Cut to %s Gold", title, BreakUpLargeNumbers(cut))
    end
end