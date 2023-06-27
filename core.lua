local addonName = ...
local fontSize = select(2, GetChatWindowInfo(1))
local addonPrefix = string.format("[|TInterface\\Addons\\NovaBoostingUI\\Images\\Logo.png:%d|t|cFFEF9009%s|r]", fontSize, addonName)
local function printMessage(msg, ...)
    print(string.format("%s: " .. msg, addonPrefix, ...))
end

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

local f = CreateFrame("Frame")

function f.OnGearUpdate()
    local data = {}
    for unit in Nova_IterateGroup() do
        local uGear = openRaidLib.GetUnitGear(unit)
        local uScore = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        if uGear then
            local ilvl = uGear.ilevel
            local score = uScore and uScore.currentSeasonScore or 0
            data[unit] = {ilvl, score}
        end
    end
    throwEvent("PLAYERS", data)
    lastData = data
end

openRaidLib.RegisterCallback(f, "GearUpdate", "OnGearUpdate")

SLASH_NBUI1 = "/nb"
SLASH_NBUI2 = "/boost"

SlashCmdList.NBUI = function(msg, msgBox)
    local fontSize = msgBox.fontSize
    if msg == "reset" then
        throwEvent("RESET")
    elseif msg == "players" then
        printMessage("Requesting Player Data")
        openRaidLib.RequestAllData()
        if lastData then throwEvent("PLAYERS", lastData) end
    elseif msg == "last" then
        throwEvent("PLAYERS", lastData)
        throwEvent("BOOST", lastTitle)
    elseif msg == "start" then
        active = true
        startTime = GetTime()
        printMessage("Boost started")
    elseif msg == "stop" then
        active = false
        local time = GetTime() - startTime
        local formattedTime = string.format("%d:%02d", time / 60, time % 60)
        local formattedCut = BreakUpLargeNumbers(lastTitle.cut)
        local formattedCutPerHour = BreakUpLargeNumbers(lastTitle.cut / (time / 60 / 60))
        printMessage("the Boost took %s and you made %s Gold (%s Gold per Hour)", formattedTime, formattedCut, formattedCutPerHour)
        throwEvent("RESET")
    elseif msg == "help" then
        printMessage("/nb and /boost can be used as Prefix")
        printMessage("/nb help to show this message")
        printMessage("/nb reset to reset data")
        printMessage("/nb <title> <cut> to update title and cut")
        printMessage("/nb players to force update players")
        printMessage("/nb last to show last data")
        printMessage("/nb start | stop to start or stop the boost")
        printMessage("/nb calc <cut> to calculate cut (15%%)")
        printMessage("/nb check <ilvl> to check if you can trade")
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
        printMessage("Checking for non tradeable Slots (ilvl < %d)", minIlvl)
    elseif string.match(msg, "^calc") then
        local cut = string.match(msg, "(%d+)$")
        printMessage("Your cut would be %s Gold", BreakUpLargeNumbers(tonumber(cut) * 0.15))
    else
        local title, cut = string.match(msg, "(.-)%s+(%d+)$")
        if (not title) or (not cut) then
            printMessage("Invalid Syntax use /nb help for more information")
            return
        end
        cut = tonumber(cut) * 0.15
        local data = {
            title = title,
            cut = cut
        }
        throwEvent("BOOST", data)
        lastTitle = data
        printMessage("Set Title to %s and Cut to %s Gold", title, BreakUpLargeNumbers(cut))
    end
end