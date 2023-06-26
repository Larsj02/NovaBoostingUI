local addonName = ...

local lastData = {}
local lastTitle = {}
local active = false
local startTime = 0

local openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0")

local function throwEvent(subEvent, data)
    WeakAuras.ScanEvents("NOVA_INTERNAL", subEvent, data, active)
end

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

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
        if ... == addonName then
            print(string.format("%s: loaded", addonName))
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", OnEvent)

function f.OnGearUpdate()
    local data = {}
    for unit in Nova_IterateGroup() do
        local uGear = openRaidLib.GetUnitGear(unit)
        local uScore = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        if uGear then
            local ilvl = uGear.ilevel
            local score = uScore.currentSeasonScore
            data[unit] = {ilvl, score}
        end
    end
    throwEvent("PLAYERS", data)
    lastData = data
end

openRaidLib.RegisterCallback(f, "GearUpdate", "OnGearUpdate")

SLASH_NBUI1 = "/nb"
SLASH_NBUI2 = "/boost"

SlashCmdList.NBUI = function(msg)
    if msg == "reset" then
        throwEvent("RESET")
    elseif msg == "players" then
        print(string.format("%s: Requesting Player Data", addonName))
        openRaidLib.RequestAllData()
        if lastData then throwEvent("PLAYERS", lastData) end
    elseif msg == "last" then
        throwEvent("PLAYERS", lastData)
        throwEvent("BOOST", lastTitle)
    elseif msg == "start" then
        active = true
        startTime = GetTime()
        print(string.format("%s: Boost started", addonName))
    elseif msg == "stop" then
        active = false
        local time = GetTime() - startTime
        local formattedTime = string.format("%d:%02d", time / 60, time % 60)
        print(string.format("%s: the Boost took %s and you made %s Gold (%s Gold per Hour)", addonName, formattedTime, BreakUpLargeNumbers(lastTitle.cut), BreakUpLargeNumbers(lastTitle.cut / (time / 60 / 60))))
        throwEvent("RESET")
    elseif msg == "help" then
        print(string.format("%s: /nb and /boost can be used as Prefix", addonName))
        print(string.format("%s: /nb help to show this message", addonName))
        print(string.format("%s: /nb reset to reset data", addonName))
        print(string.format("%s: /nb players to force update players", addonName))
        print(string.format("%s: /nb last to show last data", addonName))
        print(string.format("%s: /nb <title> <cut> to update title and cut", addonName))
        print(string.format("%s: /nb start to start boost", addonName))
        print(string.format("%s: /nb stop to stop boost", addonName))
        print(string.format("%s: /nb calc <cut> to calculate cut", addonName))
        print(string.format("%s: /nb check <ilvl> to check if you can trade", addonName))
    elseif string.match(msg, "^check") then
        local minIlvl = tonumber(string.match(msg, "(%d+)$"))
        local data = {}
        for cID = 2264, 2280 do
            local cInfo = C_CurrencyInfo.GetCurrencyInfo(cID)
            if cInfo.quantity < minIlvl then
                data[cID] = {
                    name = string.match(cInfo.name, "- (.+) %["),
                    ilvl = cInfo.quantity
                }
            end
        end
        throwEvent("CHECK", data)
    elseif string.match(msg, "^calc") then
        local cut = string.match(msg, "(%d+)$")
        print(string.format("%s: Your cut would be %s Gold", addonName, BreakUpLargeNumbers(tonumber(cut) * 0.15)))
    else
        local title, cut = string.match(msg, "(.-)%s+(%d+)$")
        local data = {
            title = title,
            cut = tonumber(cut) * 0.15
        }
        throwEvent("BOOST", data)
        lastTitle = data
    end
end