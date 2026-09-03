
HeistState = {
    isActive             = false,
    doorsUnlocked        = false,
    hackedComputersCount = 0,
    accessCode           = nil,
    securityPanels       = {},
    laptops              = {},
    computers            = {}
}

local isBuyerPhaseActive   = false
local isBagAttached        = false
local isInsideFacility     = false
local heistAreaRadiusBlip  = nil
local buyerLocationBlip    = nil
local policeAlertBlip      = nil
local attachedMoneyBagProp = nil
local currentLobbyInfo     = nil

local panelHackAnimData = {
    objects = { 'hei_p_m_bag_var22_arm_s', 'hei_prop_hst_laptop', 'hei_prop_heist_card_hack_02' },
    spawnedObjects = {}
}

local laptopHackAnimData = {
    animDict = 'anim@gangops@morgue@office@laptop@',
    anims = {
        { 'enter', 'enter_laptop', 'enter_usb' },
        { 'idle',  'idle_laptop',  'idle_usb' },
        { 'exit',  'exit_laptop',  'exit_usb' }
    },
    spawnedObjects = {}
}

local spawnedEntities = {
    startPeds      = {},
    guards         = {},
    securityPanels = {},
    laptops        = {},
    doors          = {}
}

local activeSyncHack = { type = nil, index = nil, scenes = {}, inProgress = false }

local function SafeDelete(ent)
    if ent and DoesEntityExist(ent) then
        DeleteObject(ent)
        DeleteEntity(ent)
    end
    return nil
end

local function DeleteEntityList(list)
    if not list then return end
    for k, ent in pairs(list) do
        SafeDelete(ent)
        list[k] = nil
    end
end

local function RemoveSafeBlip(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    return nil
end

function ShowHelpNotification(text)
    if not text or text == '' then return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function ShowSubtitle(text, time)
    BeginTextCommandPrint('STRING')
    AddTextComponentString(text)
    EndTextCommandPrint(time or 5000, true)
end

local function LoadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(0)
    end
end

local function LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    while not HasModelLoaded(hash) do
        RequestModel(hash)
        Wait(0)
    end
end

local function SetFacilityInsideState(inside)
    if isInsideFacility == inside then return end
    isInsideFacility = inside
    if not inside then SetRadarZoom(0) end
end

local function TeleportPlayer(coords)
    DoScreenFadeOut(500)
    Wait(2000)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z - 1.0, false, false, false, false)
    DoScreenFadeIn(500)
    SetFacilityInsideState(#(coords - Config.Exit) < 50.0)
end

local function AbortActiveSynchronizedScene()
    if not activeSyncHack.inProgress then return end
    for _, sceneId in ipairs(activeSyncHack.scenes) do
        if sceneId then NetworkStopSynchronisedScene(sceneId) end
    end
    DeleteEntityList(panelHackAnimData.spawnedObjects)
    DeleteEntityList(laptopHackAnimData.spawnedObjects)

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then ClearPedTasks(ped) end
    BusyspinnerOff()

    if activeSyncHack.type == 'panel' and activeSyncHack.index then
        TriggerServerEvent('sd-iaaheist:server:CancelPanelHack', activeSyncHack.index)
    end
    activeSyncHack = { type = nil, index = nil, scenes = {}, inProgress = false }
end

local function SafeWait(durationMs)
    local elapsed, step = 0, 50
    while elapsed < durationMs do
        if not activeSyncHack.inProgress then return false end
        local ped = PlayerPedId()
        if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 or IsPedFatallyInjured(ped) or IsPedRagdoll(ped) then
            AbortActiveSynchronizedScene()
            return false
        end
        Wait(step)
        elapsed = elapsed + step
    end
    return activeSyncHack.inProgress
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        if victim == PlayerPedId() and (IsEntityDead(victim) or GetEntityHealth(victim) <= 0 or IsPedFatallyInjured(victim)) then
            AbortActiveSynchronizedScene()
        end
    end
end)

for _, evt in ipairs({'esx:onPlayerDeath', 'hospital:client:KillPlayer', 'hospital:client:SetDoctor', 'hospital:client:RespawnAtHospital', 'qbx_medical:client:playerDied', 'qbx_medical:client:playerDowned'}) do
    RegisterNetEvent(evt, AbortActiveSynchronizedScene)
end

local function SpawnConfigProps(configs, targetTable, modelHash)
    LoadModel(modelHash)
    for idx, data in pairs(configs or {}) do
        if not DoesEntityExist(targetTable[idx]) then
            local obj = CreateObject(modelHash, data.coords.x, data.coords.y, data.coords.z, true, true, false)
            SetEntityHeading(obj, data.heading or 0.0)
            targetTable[idx] = obj
        end
    end
end

local function SpawnHeistObjects()
    SpawnConfigProps(Config.SecurityPanel, spawnedEntities.securityPanels, `hei_prop_hei_securitypanel`)
    SpawnConfigProps(Config.LaptopHack, spawnedEntities.laptops, `xm_prop_x17_laptop_mrsr`)
end

local function SetDoorsLockState(state)
    for index, door in pairs(Config.ClosedDoors) do
        spawnedEntities.doors[index] = GetClosestObjectOfType(door.coords.x, door.coords.y, door.coords.z, 1.0, door.object, false, false, false)
        if DoesEntityExist(spawnedEntities.doors[index]) then
            FreezeEntityPosition(spawnedEntities.doors[index], (state == 'close'))
        end
    end
end

local function OpenPinCodeKeyboard()
    AddTextEntry("FMMC_MPM_NA", Local['type_code'] or 'Type The Code')
    DisplayOnscreenKeyboard(1, "FMMC_MPM_NA", "", "", "", "", "", 4)
    while UpdateOnscreenKeyboard() == 0 do
        DisableAllControlActions(0)
        Wait(0)
    end
    return GetOnscreenKeyboardResult()
end

local function AttachMoneyBag()
    local playerPed = PlayerPedId()
    local bagModel  = 'xm3_prop_xm3_bag_01a'
    LoadModel(bagModel)
    attachedMoneyBagProp = CreateObject(GetHashKey(bagModel), 1.0, 1.0, 1.0, true, true, false)
    AttachEntityToEntity(attachedMoneyBagProp, playerPed, GetPedBoneIndex(playerPed, 28422), 0.38, 0.06, -0.06, -100.0, -180.0, -78.0, true, true, false, false, 2, true)
    LoadAnimDict('move_weapon@jerrycan@generic')
    TaskPlayAnim(playerPed, 'move_weapon@jerrycan@generic', "idle", 1.0, -1.0, -1, 51, 1, false, false, false)
end

local function SetupCutscenePeds(coords)
    local playerPed = PlayerPedId()
    local clones = {}
    for i = 1, 5 do clones[i] = ClonePedEx(playerPed, 0.0, false, true, 1) end

    SetBlockingOfNonTemporaryEvents(clones[1], true)
    SetEntityVisible(clones[1], false, false)
    SetEntityInvincible(clones[1], true)
    SetEntityCollision(clones[1], false, false)
    FreezeEntityPosition(clones[1], true)

    SetCutsceneEntityStreamingFlags('MP_1', 0, 1)
    RegisterEntityForCutscene(playerPed, 'MP_1', 0, GetEntityModel(playerPed), 64)
    for i = 2, 5 do
        SetCutsceneEntityStreamingFlags('MP_' .. i, 0, 1)
        RegisterEntityForCutscene(clones[i], 'MP_' .. i, 0, GetEntityModel(clones[i]), 64)
    end

    Wait(10)
    StartCutsceneAtCoords(coords.x, coords.y, coords.z, 0)
    SetCutsceneOrigin(Config.Finish.x, Config.Finish.y, Config.Finish.z, Config.FinishHeading, 0)
    Wait(10)
    ClonePedToTarget(clones[1], playerPed)
    Wait(10)
    for i = 1, 5 do DeleteEntity(clones[i]) end
    Wait(50)
    DoScreenFadeIn(250)
end

local function PlayFinishCutscene(cutsceneName, coords)
    ClearAllHelpMessages()
    ClearHelp(true)
    while not HasThisCutsceneLoaded(cutsceneName) do
        RequestCutscene(cutsceneName, 8)
        Wait(0)
    end
    SetupCutscenePeds(coords)
    Wait(6300)
    StopCutsceneImmediately()
    RemoveCutscene()
    DoScreenFadeIn(500)
end

local function CleanupAllSpawnedEntities()
    DeleteEntityList(spawnedEntities.securityPanels)
    DeleteEntityList(spawnedEntities.laptops)
    DeleteEntityList(spawnedEntities.guards)
    DeleteEntityList(panelHackAnimData.spawnedObjects)
    DeleteEntityList(laptopHackAnimData.spawnedObjects)
    attachedMoneyBagProp = SafeDelete(attachedMoneyBagProp)
    heistAreaRadiusBlip  = RemoveSafeBlip(heistAreaRadiusBlip)
    buyerLocationBlip    = RemoveSafeBlip(buyerLocationBlip)
    policeAlertBlip      = RemoveSafeBlip(policeAlertBlip)
    SetFacilityInsideState(false)
end

RegisterNetEvent('sd-iaaheist:client:SyncHeistState', function(serverState)
    if not serverState then return end
    HeistState = serverState
    if HeistState.isActive then
        SpawnHeistObjects()
        PrepareAllGuards(HeistState)
    else
        CleanupAllGuards()
    end
end)

RegisterNetEvent('sd-iaaheist:client:UpdateLobbyVote', function(readyCount, totalInCircle, minReq, maxCap)
    currentLobbyInfo = { ready = readyCount, total = totalInCircle, min = minReq, max = maxCap }
end)

RegisterNetEvent('sd-iaaheist:client:TeleportToCoords', function(coords)
    TeleportPlayer(coords)
end)

RegisterNetEvent('sd-iaaheist:client:TriggerBuyerPhase', function()
    if not isBuyerPhaseActive and HeistState.isActive then
        buyerLocationBlip = AddBlipForCoord(Config.Finish.x, Config.Finish.y, Config.Finish.z)
        SetBlipSprite(buyerLocationBlip, 106)
        SetBlipColour(buyerLocationBlip, 2)
        SetBlipAsShortRange(buyerLocationBlip, true)
        SetBlipScale(buyerLocationBlip, 0.8)
        SetBlipAlpha(buyerLocationBlip, 128)

        heistAreaRadiusBlip = RemoveSafeBlip(heistAreaRadiusBlip)
        ShowSubtitle(Local['finish'], 7000)
        isBuyerPhaseActive = true
    end
end)

RegisterNetEvent('sd-iaaheist:client:ExecuteFinishScene', function()
    isBuyerPhaseActive = false
    ClearAllHelpMessages()
    ClearHelp(true)
    attachedMoneyBagProp = SafeDelete(attachedMoneyBagProp)
    buyerLocationBlip    = RemoveSafeBlip(buyerLocationBlip)

    ClearPedTasks(PlayerPedId())
    PlayFinishCutscene('hs3f_all_drp1', Config.Finish)
    TriggerServerEvent('sd-iaaheist:server:FinishReward')
    ShowSubtitle(Local['finished'], 6000)
end)

RegisterNetEvent('sd-iaaheist:client:OnHeistStarted', function()
    ShowHelpNotification(Local['m_started3'])
    SpawnHeistObjects()
    PrepareAllGuards(HeistState)

    heistAreaRadiusBlip = RemoveSafeBlip(heistAreaRadiusBlip)
    heistAreaRadiusBlip = AddBlipForRadius(Config.Enter.x, Config.Enter.y, Config.Enter.z, 100.0)
    SetBlipHighDetail(heistAreaRadiusBlip, true)
    SetBlipColour(heistAreaRadiusBlip, 1)
    SetBlipAlpha(heistAreaRadiusBlip, 128)
    SetBlipAsShortRange(heistAreaRadiusBlip, true)
end)

RegisterNetEvent('sd-iaaheist:client:ShowNotification', function(message)
    ShowHelpNotification(message)
end)

-- Minigame helper (local NUI color-memory game)
local minigameResultPromise = nil

RegisterNUICallback('minigameResult', function(data, cb)
    cb('ok')
    if minigameResultPromise then
        minigameResultPromise:resolve(data.success == true)
        minigameResultPromise = nil
    end
end)

local function RunPanelMinigame()
    local m = Config.Minigame or {}
    local blocks = m.blocks or 4
    local time = m.time or 7
    local timeMs = (time < 100) and (time * 1000) or time

    SetNuiFocus(true, true)
    minigameResultPromise = promise.new()

    SendNUIMessage({
        action = 'startMinigame',
        blocks = blocks,
        time   = timeMs
    })

    local success = Citizen.Await(minigameResultPromise)
    SetNuiFocus(false, false)
    return success == true
end

-- Test command to preview the minigame
-- RegisterCommand('testminigame', function()
--     local result = RunPanelMinigame()
--     print('[sd-iaaheist] Minigame result: ' .. tostring(result))
-- end, false)

-- Executes security panel hack synchronized scene & minigame
RegisterNetEvent('sd-iaaheist:client:BeginPanelHackScene', function(panelIndex)
    local playerPed = PlayerPedId()
    if IsEntityDead(playerPed) or GetEntityHealth(playerPed) <= 0 then
        TriggerServerEvent('sd-iaaheist:server:CancelPanelHack', panelIndex)
        return
    end

    AbortActiveSynchronizedScene()
    activeSyncHack = { type = 'panel', index = panelIndex, scenes = {}, inProgress = true }

    local playerCoords = GetEntityCoords(playerPed)
    local animDict     = 'anim@heists@ornate_bank@hack'
    local panelConfig  = Config.SecurityPanel[panelIndex]
    local targetCoords = panelConfig and panelConfig.coords or playerCoords
    local panelEntity  = GetClosestObjectOfType(targetCoords.x, targetCoords.y, targetCoords.z, 2.5, `hei_prop_hei_securitypanel`, false, false, false)

    local panelCoords = (DoesEntityExist(panelEntity) and GetEntityCoords(panelEntity)) or (panelConfig and panelConfig.coords) or playerCoords
    local panelRot    = (DoesEntityExist(panelEntity) and GetEntityRotation(panelEntity)) or (panelConfig and vector3(0.0, 0.0, panelConfig.heading or 0.0)) or GetEntityRotation(playerPed)

    LoadAnimDict(animDict)
    for i, modelName in ipairs(panelHackAnimData.objects) do
        LoadModel(modelName)
        local obj = CreateObject(GetHashKey(modelName), playerCoords.x, playerCoords.y, playerCoords.z, true, true, true)
        SetEntityCollision(obj, false, false)
        panelHackAnimData.spawnedObjects[i] = obj
    end

    local bagProp, laptopProp, cardProp = panelHackAnimData.spawnedObjects[1], panelHackAnimData.spawnedObjects[2], panelHackAnimData.spawnedObjects[3]

    local function CreatePanelScene(looped, pAnim, bAnim, lAnim, cAnim)
        local scene = NetworkCreateSynchronisedScene(panelCoords.x, panelCoords.y, panelCoords.z, panelRot.x, panelRot.y, panelRot.z, 2, looped, looped, 1065353216, 0, 1.3)
        table.insert(activeSyncHack.scenes, scene)
        NetworkAddPedToSynchronisedScene(playerPed, scene, animDict, pAnim, 1.5, -4.0, 1, 16, 1148846080, 0)
        NetworkAddEntityToSynchronisedScene(bagProp, scene, animDict, bAnim, 1.0, 1.0, 1)
        NetworkAddEntityToSynchronisedScene(laptopProp, scene, animDict, lAnim, 1.0, 1.0, 1)
        NetworkAddEntityToSynchronisedScene(cardProp, scene, animDict, cAnim, 1.0, 1.0, 1)
        NetworkStartSynchronisedScene(scene)
        return scene
    end

    local enterScene = CreatePanelScene(false, 'hack_enter', 'hack_enter_bag', 'hack_enter_laptop', 'hack_enter_card')
    if not SafeWait(6000) then return end

    local loopScene = CreatePanelScene(true, 'hack_loop', 'hack_loop_bag', 'hack_loop_laptop', 'hack_loop_card')
    if not SafeWait(1500) then return end

    local hackSuccess = RunPanelMinigame()

    if not activeSyncHack.inProgress or IsEntityDead(playerPed) or GetEntityHealth(playerPed) <= 0 then
        AbortActiveSynchronizedScene()
        return
    end

    if not SafeWait(500) then return end
    local exitScene = CreatePanelScene(false, 'hack_exit', 'hack_exit_bag', 'hack_exit_laptop', 'hack_exit_card')
    if not SafeWait(4500) then return end

    NetworkStopSynchronisedScene(exitScene)
    NetworkStopSynchronisedScene(loopScene)
    NetworkStopSynchronisedScene(enterScene)
    ClearPedTasks(playerPed)
    DeleteEntityList(panelHackAnimData.spawnedObjects)
    activeSyncHack = { type = nil, index = nil, scenes = {}, inProgress = false }

    Bridge.Notify(hackSuccess and (Local['hack_success'] or 'Security Panel Hacked Successfully!') or (Local['hack_failed'] or 'Security Panel Hack Failed!'), hackSuccess and 'success' or 'error')
    TriggerServerEvent('sd-iaaheist:server:FinishPanelHack', panelIndex, hackSuccess)
end)

-- Plays computer hacking animation
RegisterNetEvent('sd-iaaheist:client:PlayComputerHackAnim', function(coords, heading)
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z - 1.0, false, false, false, false)
    SetEntityHeading(playerPed, heading)
    local animDict = "anim@scripted@player@mission@tunf_bunk_ig3_nas_upload@"
    LoadAnimDict(animDict)
    TaskPlayAnim(playerPed, animDict, "normal_typing", 3.0, 4.0, 7000, 1, 0, false, false, false)
end)

local function Draw2DText(x, y, text, scale, r, g, b, a)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextOutline()
    SetTextRightJustify(true)
    SetTextWrap(0.0, x)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

RegisterNetEvent('sd-iaaheist:client:UpdateHackedCodeInfo', function(count, code)
    Wait(7100)
    HeistState.hackedComputersCount = count
    if code then HeistState.accessCode = code end
    if count >= 4 and code then ShowSubtitle(Local['go_to_sc'], 7000) end
end)

-- Terminal & Code HUD thread
CreateThread(function()
    while true do
        local sleep = 1000
        if HeistState.isActive and not HeistState.doorsUnlocked then
            local count, code = HeistState.hackedComputersCount or 0, HeistState.accessCode
            if count > 0 and count < 4 then
                sleep = 0
                Draw2DText(0.985, 0.92, string.format("TERMINALS: ~s~~y~%d/4", count), 0.40)
            elseif count >= 4 and code then
                sleep = 0
                Draw2DText(0.985, 0.89, "TERMINALS: ~s~~g~4/4", 0.40)
                Draw2DText(0.985, 0.92, string.format("PASSCODE: ~g~%s", code), 0.40, 60, 255, 80)
            end
        end
        Wait(sleep)
    end
end)

-- Executes USB data extraction animation
RegisterNetEvent('sd-iaaheist:client:BeginLaptopDataDownload', function(laptopIndex)
    local playerPed = PlayerPedId()
    if IsEntityDead(playerPed) or GetEntityHealth(playerPed) <= 0 then return end

    AbortActiveSynchronizedScene()
    activeSyncHack = { type = 'laptop', index = laptopIndex, scenes = {}, inProgress = true }

    local playerCoords = GetEntityCoords(playerPed)
    local animDict     = laptopHackAnimData.animDict
    local laptopConfig = Config.LaptopHack[laptopIndex]
    local targetCoords = laptopConfig and laptopConfig.coords or playerCoords
    local laptopEntity = (laptopIndex and spawnedEntities.laptops[laptopIndex]) or GetClosestObjectOfType(targetCoords.x, targetCoords.y, targetCoords.z, 2.5, `xm_prop_x17_laptop_mrsr`, false, false, false)

    local laptopCoords = (DoesEntityExist(laptopEntity) and GetEntityCoords(laptopEntity)) or (laptopConfig and laptopConfig.coords) or playerCoords
    local laptopRot    = (DoesEntityExist(laptopEntity) and GetEntityRotation(laptopEntity)) or (laptopConfig and vector3(0.0, 0.0, laptopConfig.heading or 0.0)) or GetEntityRotation(playerPed)

    LoadAnimDict(animDict)
    LoadModel('hei_prop_hst_usb_drive')

    local usbEntity = CreateObject(`hei_prop_hst_usb_drive`, laptopCoords.x, laptopCoords.y, laptopCoords.z, true, true, true)
    SetEntityCollision(usbEntity, false, false)
    laptopHackAnimData.spawnedObjects[1] = usbEntity

    local function CreateLaptopScene(looped, anims)
        local scene = NetworkCreateSynchronisedScene(laptopCoords.x, laptopCoords.y, laptopCoords.z, laptopRot.x, laptopRot.y, laptopRot.z, 2, looped, looped, 1065353216, 0, 1.3)
        table.insert(activeSyncHack.scenes, scene)
        NetworkAddPedToSynchronisedScene(playerPed, scene, animDict, anims[1], 1.5, -4.0, 1, 16, 1148846080, 0)
        if DoesEntityExist(laptopEntity) and laptopEntity ~= 0 then
            NetworkAddEntityToSynchronisedScene(laptopEntity, scene, animDict, anims[2], 4.0, -8.0, 1)
        end
        NetworkAddEntityToSynchronisedScene(usbEntity, scene, animDict, anims[3], 4.0, -8.0, 1)
        NetworkStartSynchronisedScene(scene)
        return scene
    end

    local anims = laptopHackAnimData.anims
    local enterScene = CreateLaptopScene(false, anims[1])
    if not SafeWait(2500) then return end

    local idleScene = CreateLaptopScene(true, anims[2])
    BeginTextCommandBusyspinnerOn('STRING')
    AddTextComponentSubstringPlayerName(Local['stealing_data'] or 'Downloading Data...')
    EndTextCommandBusyspinnerOn(5)

    local waitResult = SafeWait(8000)
    BusyspinnerOff()
    if not waitResult then return end

    local exitScene = CreateLaptopScene(false, anims[3])
    if not SafeWait(2500) then return end

    NetworkStopSynchronisedScene(exitScene)
    NetworkStopSynchronisedScene(idleScene)
    NetworkStopSynchronisedScene(enterScene)
    ClearPedTasks(playerPed)
    DeleteEntityList(laptopHackAnimData.spawnedObjects)
    activeSyncHack = { type = nil, index = nil, scenes = {}, inProgress = false }

    TriggerServerEvent('sd-iaaheist:server:CompleteLaptopDownload', laptopIndex)
end)

-- Full Heist Reset
RegisterNetEvent('sd-iaaheist:client:HeistReset', function()
    HeistState = { isActive = false, doorsUnlocked = false, hackedComputersCount = 0, accessCode = nil, securityPanels = {}, laptops = {}, computers = {} }
    isBuyerPhaseActive, isBagAttached, currentLobbyInfo = false, false, nil
    CleanupAllGuards()
    CleanupAllSpawnedEntities()
end)

-- Police Alert Blip
RegisterNetEvent('sd-iaaheist:client:AddBlip', function()
    Bridge.Notify(Local['alert'], 'error')
    policeAlertBlip = AddBlipForCoord(Config.Enter.x, Config.Enter.y, Config.Enter.z)
    SetBlipSprite(policeAlertBlip, 60)
    SetBlipColour(policeAlertBlip, 1)
    SetBlipAsShortRange(policeAlertBlip, true)
    SetBlipScale(policeAlertBlip, 0.8)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Local['alert'])
    EndTextCommandSetBlipName(policeAlertBlip)

    Wait(60000 * 5)
    policeAlertBlip = RemoveSafeBlip(policeAlertBlip)
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        AbortActiveSynchronizedScene()
        CleanupAllSpawnedEntities()
        DeleteEntityList(spawnedEntities.startPeds)
        SetRadarZoom(0)
    end
end)

-- Request initial state on player spawn
CreateThread(function()
    Wait(2000)
    TriggerServerEvent('sd-iaaheist:server:RequestHeistState')
end)


local function DrawRedCircle(coords, radius)
    local r = radius or 1.2
    DrawMarker(1, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r * 2.0, r * 2.0, 0.6, 255, 0, 0, 200, false, false, 2, false, nil, nil, false)
end

-- Thread: Spawn Heist Start Peds
CreateThread(function()
    for index, pedConfig in pairs(Config.StartPeds) do
        LoadModel(pedConfig.model)
        local ped = CreatePed(4, GetHashKey(pedConfig.model), pedConfig.coords.x, pedConfig.coords.y, pedConfig.coords.z, pedConfig.heading, false, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        spawnedEntities.startPeds[index] = ped
    end
end)

-- Thread: Heist Start interaction & Group Lobby Circle
CreateThread(function()
    while true do
        local sleep = 1500
        local playerCoords = GetEntityCoords(PlayerPedId())
        local startCoords = Config.StartPeds[1] and Config.StartPeds[1].coords or vector3(1533.93, 1702.68, 108.71)
        local distToStart = #(playerCoords - startCoords)

        if not HeistState.isActive and distToStart <= 30.0 then
            sleep = 0
            DrawRedCircle(startCoords, 1.5)
            if distToStart <= 2.5 then
                local playersInCircle = 0
                for _, player in ipairs(GetActivePlayers()) do
                    local ped = GetPlayerPed(player)
                    if DoesEntityExist(ped) and #(GetEntityCoords(ped) - startCoords) <= 2.5 then
                        playersInCircle = playersInCircle + 1
                    end
                end

                local maxCap = Config.MaxPlayers or 4
                local readyCount = (currentLobbyInfo and currentLobbyInfo.ready) or 0
                ShowHelpNotification(string.format("[ %d / %d Players in Circle ] (Ready: %d)\n%s", playersInCircle, maxCap, readyCount, Local['start_m']))

                if IsControlJustPressed(0, 38) then
                    TriggerServerEvent('sd-iaaheist:server:ToggleStartReady')
                end
            end
        end

        Wait(sleep)
    end
end)

-- Thread: Interior security doors management
CreateThread(function()
    while true do
        local sleep = 1500
        local playerCoords = GetEntityCoords(PlayerPedId())

        if HeistState.isActive then
            for _, door in pairs(Config.ClosedDoors) do
                if #(playerCoords - door.coords) <= 20.0 then
                    SetDoorsLockState(HeistState.doorsUnlocked and 'open' or 'close')
                    break
                end
            end
        end

        Wait(sleep)
    end
end)

-- Thread: Facility elevator entry and exit (Group Ready Markers & Interaction)
CreateThread(function()
    while true do
        local sleep = 1500
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distToEnter = #(playerCoords - Config.Enter)
        local distToExit  = #(playerCoords - Config.Exit)

        if HeistState.isActive then
            local panel1State = HeistState.securityPanels and HeistState.securityPanels[1]
            if distToEnter <= 25.0 and panel1State and panel1State.used then
                sleep = 0
                DrawRedCircle(Config.Enter, 1.2)
                if distToEnter < 2.0 then
                    ShowHelpNotification(Local['enter_i'] .. " (All Players Must Press E)")
                    if IsControlJustPressed(0, 38) then TriggerServerEvent('sd-iaaheist:server:VoteEnterFacility') end
                end
            end
        end

        if distToExit <= 25.0 then
            sleep = 0
            DrawRedCircle(Config.Exit, 1.2)
            if distToExit < 2.0 then
                ShowHelpNotification(Local['exit_i'] .. " (All Players Must Press E)")
                if IsControlJustPressed(0, 38) then TriggerServerEvent('sd-iaaheist:server:VoteExitFacility') end
            end
        end

        Wait(sleep)
    end
end)

-- Thread: Active minimap zoom while inside the interior facility
CreateThread(function()
    while true do
        if isInsideFacility then
            SetRadarZoom(1100)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- Thread: Security panels, Computers and Laptop interactions
CreateThread(function()
    while true do
        local sleep = 1500
        local playerCoords = GetEntityCoords(PlayerPedId())

        if HeistState.isActive then
            -- Security Panels
            for panelIndex, panel in pairs(Config.SecurityPanel) do
                local panelState = HeistState.securityPanels and HeistState.securityPanels[panelIndex]
                if panelState and not panelState.used and not panelState.busy then
                    if #(playerCoords - panel.coords) <= 1.5 then
                        sleep = 1
                        ShowHelpNotification(Local['start_h'])
                        if IsControlJustPressed(0, 38) then
                            local enteredCode = (panelIndex == 2) and OpenPinCodeKeyboard() or nil
                            if panelIndex == 2 and not enteredCode then
                                Bridge.Notify(Local['code_incorrect'], 'error')
                            else
                                TriggerServerEvent('sd-iaaheist:server:RequestPanelHack', panelIndex, tonumber(enteredCode))
                            end
                        end
                    end
                end
            end

            -- Computers
            for compIndex, computer in pairs(Config.HackComputers) do
                local compState = HeistState.computers and HeistState.computers[compIndex]
                if compState and not compState.used then
                    if #(playerCoords - computer.coords) <= 1.2 then
                        sleep = 1
                        ShowHelpNotification(Local['hack_computer'])
                        if IsControlJustPressed(0, 38) then
                            TriggerServerEvent('sd-iaaheist:server:HackComputer', compIndex)
                        end
                    end
                end
            end

            -- Laptops
            for laptopIndex, laptop in pairs(Config.LaptopHack) do
                local laptopState = HeistState.laptops and HeistState.laptops[laptopIndex]
                if laptopState and not laptopState.used then
                    if #(playerCoords - laptop.coords) <= 1.2 then
                        sleep = 1
                        ShowHelpNotification(Local['steal_d'])
                        if IsControlJustPressed(0, 38) then
                            TriggerServerEvent('sd-iaaheist:server:DownloadLaptopData', laptopIndex)
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- Thread: Buyer delivery and finish cutscene
CreateThread(function()
    while true do
        local sleep = 1000
        if isBuyerPhaseActive and not IsCutsceneActive() and not IsCutscenePlaying() then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distToBuyer  = #(playerCoords - Config.Finish)

            if distToBuyer <= 20.0 then
                sleep = 0
                DrawRedCircle(Config.Finish, 2.0)

                if not isBagAttached then
                    AttachMoneyBag()
                    isBagAttached = true
                end

                if distToBuyer <= 3.0 then
                    ShowHelpNotification("Press ~INPUT_PICKUP~ To Hand Over Stolen Data (All Players Must Press E)")
                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('sd-iaaheist:server:VoteFinishBuyer')
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

