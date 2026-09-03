

local HeistState = {
    isActive             = false,
    startTime            = 0,
    lastCooldown         = 0,
    startedBy            = nil,
    accessCode           = nil,
    doorsUnlocked        = false,
    hackedComputersCount = 0,
    participants         = {},
    securityPanels       = {},
    laptops              = {},
    computers            = {}
}

---Initializes or resets the internal heist state tables
local function ResetHeistState()
    HeistState.isActive             = false
    HeistState.startTime            = 0
    HeistState.startedBy            = nil
    HeistState.accessCode           = nil
    HeistState.doorsUnlocked        = false
    HeistState.hackedComputersCount = 0
    HeistState.participants         = {}
    HeistState.securityPanels       = {}
    HeistState.laptops              = {}
    HeistState.computers            = {}

    for i = 1, #Config.SecurityPanel do
        HeistState.securityPanels[i] = { used = false, busy = false }
    end

    for i = 1, #Config.LaptopHack do
        HeistState.laptops[i] = { used = false }
    end

    for i = 1, #Config.HackComputers do
        HeistState.computers[i] = { used = false }
    end

    HeistState.guards = {}
    for i = 1, #Config.Guards do
        HeistState.guards[i] = { isDead = false }
    end
    HeistState.isAlerted = false
end

-- Initialize state at server start
ResetHeistState()




---Validates player proximity to target coordinates
---@param source number
---@param targetCoords vector3
---@param maxDist number|nil
---@return boolean
local function ValidatePlayerProximity(source, targetCoords, maxDist)
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed == 0 then return false end

    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - targetCoords)
    local allowedDist = maxDist or Config.MaxInteractDistance or 4.0

    return distance <= allowedDist
end

---Checks if player is an authorized heist participant
---@param source number
---@return boolean
local function IsHeistParticipant(source)
    return HeistState.isActive and (HeistState.participants[source] == true)
end

---Broadcasts full heist state to all connected clients
local function SyncHeistStateToAll()
    TriggerClientEvent('sd-iaaheist:client:SyncHeistState', -1, HeistState)
end

local GroupVotes = {
    ['start']  = {},
    ['enter']  = {},
    ['exit']   = {},
    ['finish'] = {}
}

---Clears votes for a category
local function ResetGroupVotes(category)
    if category then
        GroupVotes[category] = {}
    else
        GroupVotes = { ['start'] = {}, ['enter'] = {}, ['exit'] = {}, ['finish'] = {} }
    end
end


RegisterServerEvent('sd-iaaheist:server:RequestHeistState')
AddEventHandler('sd-iaaheist:server:RequestHeistState', function()
    local src = source
    TriggerClientEvent('sd-iaaheist:client:SyncHeistState', src, HeistState)
end)



-- Group Start Heist Toggle Vote
RegisterServerEvent('sd-iaaheist:server:ToggleStartReady')
AddEventHandler('sd-iaaheist:server:ToggleStartReady', function()
    local src = source

    if HeistState.isActive then
        Bridge.Notify(src, Local['heist_already_active'], 'error')
        return
    end

    local currentTime = os.time()
    local cooldownSeconds = (Config.Cooldown or 45) * 60
    if (currentTime - HeistState.lastCooldown) < cooldownSeconds then
        local remainingMinutes = math.ceil((cooldownSeconds - (currentTime - HeistState.lastCooldown)) / 60)
        Bridge.Notify(src, string.format(Local['heist_cooldown'], remainingMinutes), 'error')
        return
    end

    local policeCount = Bridge.GetPoliceCount()
    if policeCount < (Config.RequiredPolice or 0) then
        Bridge.Notify(src, string.format(Local['not_enough_police'], Config.RequiredPolice), 'error')
        return
    end

    local startCoords = Config.StartPeds[1] and Config.StartPeds[1].coords or vector3(1533.93, 1702.68, 108.71)
    if not ValidatePlayerProximity(src, startCoords, 3.5) then
        return
    end

    -- Toggle ready status
    GroupVotes['start'][src] = not GroupVotes['start'][src]

    -- Collect all players in circle
    local playersInCircle = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pSrc = tonumber(playerId)
        if ValidatePlayerProximity(pSrc, startCoords, 3.5) then
            playersInCircle[#playersInCircle + 1] = pSrc
        else
            GroupVotes['start'][pSrc] = nil
        end
    end

    local totalInCircle = #playersInCircle
    local readyCount = 0
    for _, pSrc in ipairs(playersInCircle) do
        if GroupVotes['start'][pSrc] then
            readyCount = readyCount + 1
        end
    end

    local minPlayers = Config.MinPlayers or 1
    local maxPlayers = Config.MaxPlayers or 4

    -- Broadcast ready status to players in circle
    for _, pSrc in ipairs(playersInCircle) do
        TriggerClientEvent('sd-iaaheist:client:UpdateLobbyVote', pSrc, readyCount, totalInCircle, minPlayers, maxPlayers)
    end

    -- If all players in circle pressed E and min reached, start heist!
    if totalInCircle >= minPlayers and totalInCircle <= maxPlayers and readyCount >= totalInCircle then
        ResetHeistState()
        HeistState.isActive     = true
        HeistState.startTime    = currentTime
        HeistState.lastCooldown = currentTime
        HeistState.startedBy    = src

        local crewNames = {}
        for _, pSrc in ipairs(playersInCircle) do
            HeistState.participants[pSrc] = true
            crewNames[#crewNames + 1] = GetPlayerName(pSrc) .. ' (' .. pSrc .. ')'
        end

        ResetGroupVotes()


        if Config.EnablePoliceReport then
            TriggerEvent('sd-iaaheist:server:AddAlert')
        end

        SyncHeistStateToAll()
        for _, pSrc in ipairs(playersInCircle) do
            TriggerClientEvent('sd-iaaheist:client:OnHeistStarted', pSrc)
        end

        local thisStartTime = HeistState.startTime
        SetTimeout((Config.TimeToReset or 60) * 60000, function()
            if HeistState.isActive and HeistState.startTime == thisStartTime then
                ResetHeistState()
                SyncHeistStateToAll()
                TriggerClientEvent('sd-iaaheist:client:HeistReset', -1)
            end
        end)
    end
end)

-- Group Enter Elevator
RegisterServerEvent('sd-iaaheist:server:VoteEnterFacility')
AddEventHandler('sd-iaaheist:server:VoteEnterFacility', function()
    local src = source
    if not IsHeistParticipant(src) then return end
    if not ValidatePlayerProximity(src, Config.Enter, 3.0) then return end

    GroupVotes['enter'][src] = true

    -- Count participants in enter circle
    local readyCount = 0
    local crewTotal = 0
    for pSrc, _ in pairs(HeistState.participants) do
        crewTotal = crewTotal + 1
        if GroupVotes['enter'][pSrc] and ValidatePlayerProximity(pSrc, Config.Enter, 3.0) then
            readyCount = readyCount + 1
        end
    end

    for pSrc, _ in pairs(HeistState.participants) do
        TriggerClientEvent('sd-iaaheist:client:ShowNotification', pSrc, string.format("Elevator Entry: %d/%d Crew Ready", readyCount, crewTotal))
    end

    if readyCount >= crewTotal then
        GroupVotes['enter'] = {}
        for pSrc, _ in pairs(HeistState.participants) do
            TriggerClientEvent('sd-iaaheist:client:TeleportToCoords', pSrc, Config.Exit)
        end
    end
end)

-- Group Exit Elevator
RegisterServerEvent('sd-iaaheist:server:VoteExitFacility')
AddEventHandler('sd-iaaheist:server:VoteExitFacility', function()
    local src = source
    if not IsHeistParticipant(src) then return end
    if not ValidatePlayerProximity(src, Config.Exit, 3.0) then return end

    GroupVotes['exit'][src] = true

    local readyCount = 0
    local crewTotal = 0
    for pSrc, _ in pairs(HeistState.participants) do
        crewTotal = crewTotal + 1
        if GroupVotes['exit'][pSrc] and ValidatePlayerProximity(pSrc, Config.Exit, 3.0) then
            readyCount = readyCount + 1
        end
    end

    for pSrc, _ in pairs(HeistState.participants) do
        TriggerClientEvent('sd-iaaheist:client:ShowNotification', pSrc, string.format("Elevator Exit: %d/%d Crew Ready", readyCount, crewTotal))
    end

    if readyCount >= crewTotal then
        GroupVotes['exit'] = {}
        for pSrc, _ in pairs(HeistState.participants) do
            TriggerClientEvent('sd-iaaheist:client:TeleportToCoords', pSrc, Config.Enter)
            TriggerClientEvent('sd-iaaheist:client:TriggerBuyerPhase', pSrc)
        end
    end
end)

-- Group Finish Delivery
RegisterServerEvent('sd-iaaheist:server:VoteFinishBuyer')
AddEventHandler('sd-iaaheist:server:VoteFinishBuyer', function()
    local src = source
    if not IsHeistParticipant(src) then return end
    if not ValidatePlayerProximity(src, Config.Finish, 5.0) then return end

    GroupVotes['finish'][src] = true

    local readyCount = 0
    local crewTotal = 0
    for pSrc, _ in pairs(HeistState.participants) do
        crewTotal = crewTotal + 1
        if GroupVotes['finish'][pSrc] and ValidatePlayerProximity(pSrc, Config.Finish, 5.0) then
            readyCount = readyCount + 1
        end
    end

    for pSrc, _ in pairs(HeistState.participants) do
        TriggerClientEvent('sd-iaaheist:client:ShowNotification', pSrc, string.format("Buyer Handover: %d/%d Crew Ready", readyCount, crewTotal))
    end

    if readyCount >= crewTotal then
        GroupVotes['finish'] = {}
        for pSrc, _ in pairs(HeistState.participants) do
            TriggerClientEvent('sd-iaaheist:client:ExecuteFinishScene', pSrc)
        end
    end
end)


RegisterServerEvent('sd-iaaheist:server:RequestPanelHack')
AddEventHandler('sd-iaaheist:server:RequestPanelHack', function(panelIndex, enteredCode)
    local src = source

    if not IsHeistParticipant(src) then
        Bridge.Notify(src, Local['not_in_heist'], 'error')
        return
    end

    local panelConfig = Config.SecurityPanel[panelIndex]
    if not panelConfig then return end

    -- Distance check
    if not ValidatePlayerProximity(src, panelConfig.coords, 3.5) then
        Bridge.Notify(src, Local['too_far_away'], 'error')
        return
    end

    -- State check
    local panelState = HeistState.securityPanels[panelIndex]
    if not panelState or panelState.used or panelState.busy then
        Bridge.Notify(src, Local['already_hacked'], 'error')
        return
    end

    -- Item Check
    local requiredItem = Config.Items['hack_laptop']
    if Bridge.GetItemCount(src, requiredItem) < 1 then
        Bridge.Notify(src, string.format(Local['missed_item'], requiredItem), 'error')
        return
    end

    -- PIN Code Check for Panel 2 (Interior Security Door)
    if panelIndex == 2 then
        local codeStr = tostring(enteredCode)
        if not HeistState.accessCode or codeStr ~= tostring(HeistState.accessCode) then
            Bridge.Notify(src, Local['code_incorrect'], 'error')
            return
        else
            Bridge.Notify(src, Local['code_correct'], 'success')
        end
    end

    -- Remove required item on server
    Bridge.RemoveItem(src, requiredItem, 1)

    -- Mark panel as busy and broadcast
    HeistState.securityPanels[panelIndex].busy = true
    HeistState.securityPanels[panelIndex].busyBy = src
    SyncHeistStateToAll()

    -- Tell client to execute synchronized animation & minigame
    TriggerClientEvent('sd-iaaheist:client:BeginPanelHackScene', src, panelIndex)
end)

RegisterServerEvent('sd-iaaheist:server:CancelPanelHack')
AddEventHandler('sd-iaaheist:server:CancelPanelHack', function(panelIndex)
    local src = source
    if not IsHeistParticipant(src) then return end

    local panel = HeistState.securityPanels[panelIndex]
    if panel and panel.busy and (panel.busyBy == src or panel.busyBy == nil) then
        panel.busy = false
        panel.busyBy = nil
        SyncHeistStateToAll()
    end
end)

RegisterServerEvent('sd-iaaheist:server:FinishPanelHack')
AddEventHandler('sd-iaaheist:server:FinishPanelHack', function(panelIndex, success)
    local src = source

    if not IsHeistParticipant(src) then return end

    local panelConfig = Config.SecurityPanel[panelIndex]
    if not panelConfig or not HeistState.securityPanels[panelIndex] then return end

    if not ValidatePlayerProximity(src, panelConfig.coords, 6.0) then
        return
    end

    if success then
        HeistState.securityPanels[panelIndex].used = true
        HeistState.securityPanels[panelIndex].busy = false
        HeistState.securityPanels[panelIndex].busyBy = nil

        if panelIndex == 2 then
            HeistState.doorsUnlocked = true
            for pSrc, _ in pairs(HeistState.participants) do
                TriggerClientEvent('sd-iaaheist:client:ShowNotification', pSrc, Local['doors_opened'])
            end
        end
    else
        HeistState.securityPanels[panelIndex].busy = false
        HeistState.securityPanels[panelIndex].busyBy = nil
    end

    SyncHeistStateToAll()
end)


RegisterServerEvent('sd-iaaheist:server:HackComputer')
AddEventHandler('sd-iaaheist:server:HackComputer', function(computerIndex)
    local src = source

    if not IsHeistParticipant(src) then
        Bridge.Notify(src, Local['not_in_heist'], 'error')
        return
    end

    local compConfig = Config.HackComputers[computerIndex]
    if not compConfig or not HeistState.computers[computerIndex] then return end

    if not ValidatePlayerProximity(src, compConfig.coords, 3.5) then
        Bridge.Notify(src, Local['too_far_away'], 'error')
        return
    end

    if HeistState.computers[computerIndex].used then
        Bridge.Notify(src, Local['already_hacked'], 'error')
        return
    end

    -- Mark used and increment count
    HeistState.computers[computerIndex].used = true
    HeistState.hackedComputersCount = HeistState.hackedComputersCount + 1

    -- If all 4 computers are hacked, generate secure random PIN code on server
    if HeistState.hackedComputersCount >= 4 and not HeistState.accessCode then
        HeistState.accessCode = string.format("%04d", math.random(1000, 9999))
        print('^2[sd-iaaheist]^7 Generated Server Access PIN Code: ' .. HeistState.accessCode)
    end

    SyncHeistStateToAll()

    -- Trigger typing animation on actor & code update to all participants
    TriggerClientEvent('sd-iaaheist:client:PlayComputerHackAnim', src, compConfig.coords, compConfig.heading)
    for pSrc, _ in pairs(HeistState.participants) do
        TriggerClientEvent('sd-iaaheist:client:UpdateHackedCodeInfo', pSrc, HeistState.hackedComputersCount, HeistState.accessCode)
    end
end)



RegisterServerEvent('sd-iaaheist:server:DownloadLaptopData')
AddEventHandler('sd-iaaheist:server:DownloadLaptopData', function(laptopIndex)
    local src = source

    if not IsHeistParticipant(src) then
        Bridge.Notify(src, Local['not_in_heist'], 'error')
        return
    end

    local laptopConfig = Config.LaptopHack[laptopIndex]
    if not laptopConfig or not HeistState.laptops[laptopIndex] then return end

    if not ValidatePlayerProximity(src, laptopConfig.coords, 3.5) then
        Bridge.Notify(src, Local['too_far_away'], 'error')
        return
    end

    if HeistState.laptops[laptopIndex].used then
        Bridge.Notify(src, Local['already_hacked'], 'error')
        return
    end

    -- Check required USB item
    local requiredUsb = Config.Items['hack_usb']
    if Bridge.GetItemCount(src, requiredUsb) < 1 then
        Bridge.Notify(src, string.format(Local['missed_item'], requiredUsb), 'error')
        return
    end

    -- Consume hack USB
    Bridge.RemoveItem(src, requiredUsb, 1)

    -- Mark laptop used
    HeistState.laptops[laptopIndex].used = true
    SyncHeistStateToAll()

    -- Trigger client download animation
    TriggerClientEvent('sd-iaaheist:client:BeginLaptopDataDownload', src, laptopIndex)
end)

RegisterServerEvent('sd-iaaheist:server:CompleteLaptopDownload')
AddEventHandler('sd-iaaheist:server:CompleteLaptopDownload', function(laptopIndex)
    local src = source

    if not IsHeistParticipant(src) then return end

    local laptopConfig = Config.LaptopHack[laptopIndex]
    if not laptopConfig then return end

    -- Give reward data USB on server
    local rewardItem = Config.Items['data_usb']
    local added = Bridge.AddItem(src, rewardItem, 1)
    if added or Bridge.GetItemCount(src, rewardItem) > 0 then
        TriggerClientEvent('sd-iaaheist:client:ShowNotification', src, Local['received_data_usb'] or 'Data Downloaded! You received a Data USB.')
    end
end)



RegisterServerEvent('sd-iaaheist:server:FinishReward')
AddEventHandler('sd-iaaheist:server:FinishReward', function()
    local src = source

    if not IsHeistParticipant(src) then
        Bridge.Notify(src, Local['not_in_heist'], 'error')
        return
    end

    -- Validate distance to buyer dropoff location
    if not ValidatePlayerProximity(src, Config.Finish, 30.0) then
        return
    end

    -- Count data USB items in player inventory on server
    local dataUsbItem = Config.Items['data_usb']
    local usbCount = Bridge.GetItemCount(src, dataUsbItem)

    if usbCount <= 0 then
        TriggerClientEvent('sd-iaaheist:client:ShowNotification', src, Local['no_reward_data'])
        return
    end

    -- Calculate total payout
    local totalPayout = usbCount * (Config.UsbPrice or 1000)

    -- Remove USB items on server and add cash
    Bridge.RemoveItem(src, dataUsbItem, usbCount)
    Bridge.AddMoney(src, 'cash', totalPayout)

    local playerName = GetPlayerName(src) or ('ID ' .. tostring(src))
    print('^2[sd-iaaheist]^7 Player ' .. playerName .. ' (ID: ' .. src .. ') sold ' .. usbCount .. ' Data USBs for $' .. totalPayout)
    TriggerClientEvent('sd-iaaheist:client:ShowNotification', src, string.format("Sold %d Data USBs for ~g~$%d~s~!", usbCount, totalPayout))
end)



RegisterServerEvent('sd-iaaheist:server:guardDied')
AddEventHandler('sd-iaaheist:server:guardDied', function(guardIndex)
    local src = source
    if not IsHeistParticipant(src) then return end

    if HeistState.guards[guardIndex] then
        HeistState.guards[guardIndex].isDead = true
    end

    for pSrc, _ in pairs(HeistState.participants) do
        if pSrc ~= src then
            TriggerClientEvent('sd-iaaheist:client:onGuardDied', pSrc, guardIndex)
        end
    end
end)

RegisterServerEvent('sd-iaaheist:server:guardAlerted')
AddEventHandler('sd-iaaheist:server:guardAlerted', function(guardIndex, reason, group)
    local src = source
    if not IsHeistParticipant(src) then return end

    if not HeistState.isAlerted then
        HeistState.isAlerted = true
        if Config.EnablePoliceReport then
            TriggerEvent('sd-iaaheist:server:AddAlert')
        end
    end

    for pSrc, _ in pairs(HeistState.participants) do
        if pSrc ~= src then
            TriggerClientEvent('sd-iaaheist:client:onGuardAlerted', pSrc, guardIndex, reason, group)
        end
    end
end)



RegisterServerEvent('sd-iaaheist:server:AddAlert')
AddEventHandler('sd-iaaheist:server:AddAlert', function()
    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qb' then
        if Bridge.Core and Bridge.Core.Functions then
            local players = Bridge.Core.Functions.GetQBPlayers()
            for _, player in pairs(players) do
                if player and player.PlayerData and player.PlayerData.job then
                    if player.PlayerData.job.name == 'police' and player.PlayerData.job.onduty then
                        TriggerClientEvent('sd-iaaheist:client:AddBlip', player.PlayerData.source)
                    end
                end
            end
        end
    elseif Bridge.Framework == 'esx' then
        if Bridge.Core and Bridge.Core.GetExtendedPlayers then
            local policePlayers = Bridge.Core.GetExtendedPlayers('job', 'police')
            for _, player in pairs(policePlayers) do
                TriggerClientEvent('sd-iaaheist:client:AddBlip', player.source)
            end
        end
    end
end)



AddEventHandler('playerDropped', function(reason)
    local src = source

    -- Clear votes for this player
    for category, votes in pairs(GroupVotes) do
        if votes[src] then
            votes[src] = nil
        end
    end

    -- Unlock any security panel that was actively being hacked by this player
    for i = 1, #HeistState.securityPanels do
        if HeistState.securityPanels[i].busy and HeistState.securityPanels[i].busyBy == src then
            HeistState.securityPanels[i].busy = false
            HeistState.securityPanels[i].busyBy = nil
        end
    end

    -- Handle active heist participant departure
    if HeistState.participants[src] then
        HeistState.participants[src] = nil

        local remainingCount = 0
        for pSrc, _ in pairs(HeistState.participants) do
            if GetPlayerPing(pSrc) > 0 then
                remainingCount = remainingCount + 1
            else
                HeistState.participants[pSrc] = nil
            end
        end

        print(string.format('^3[sd-iaaheist]^7 Participant ID %s dropped. Remaining active crew: %d', tostring(src), remainingCount))

        if HeistState.isActive and remainingCount <= 0 then
            print('^1[sd-iaaheist]^7 All heist participants dropped. Resetting heist state.')
            ResetHeistState()
            TriggerClientEvent('sd-iaaheist:client:HeistReset', -1)
        else
            SyncHeistStateToAll()
        end
    end
end)



