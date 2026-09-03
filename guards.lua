local ActiveGuards = {}
local RelationshipGroup, PlayerRelationship = nil, nil
local LastChatterTime = 0
local GuardCombatThreads, isSpawningGuards, guardsSpawned = false, false, false

local SpeechPool = {
    Spot   = { 'ENEMY_SPOTTED', 'TARGET_FOUND', 'GUN_PULL', 'CHALLENGE_THREAT', 'COVER_ME' },
    Combat = { 'SURROUND_THEM', 'COVER_ME', 'PIN_THEM_DOWN', 'TAKE_COVER', 'RELOADING', 'ADVANCE', 'GENERIC_CURSE_HIGH' },
    Pain   = { 'GENERIC_PAIN_MED', 'INJURED_SHOUT', 'GENERIC_CURSE_MED' }
}

local function ShowHelpNotification(text)
    if not Config.GuardSettings or not Config.GuardSettings.ShowHelpOnAlert then return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, 4000)
end

local function PlayGuardSpeech(ped, category, force)
    if not Config.GuardSettings or not Config.GuardSettings.EnableVoiceChatter then return end
    local now = GetGameTimer()
    if not force and (now - LastChatterTime < 4000) then return end
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then return end
    local pool = SpeechPool[category]
    if pool then
        PlayPedAmbientSpeechNative(ped, pool[math.random(#pool)], 'SPEECH_PARAMS_FORCE_SHOUTED')
        LastChatterTime = now
    end
end

local function IsInVisionCone(guardPed, targetCoords, maxAngle)
    local gPos, fwd = GetEntityCoords(guardPed), GetEntityForwardVector(guardPed)
    local dir = targetCoords - gPos
    local len = #(dir)
    if len == 0.0 then return true end
    local dot = ((fwd.x * dir.x) + (fwd.y * dir.y) + (fwd.z * dir.z)) / len
    return dot >= math.cos(math.rad(maxAngle))
end

local function SetupRelationshipGroups()
    if not RelationshipGroup then
        local _, grp = AddRelationshipGroup('IAA_GUARDS')
        RelationshipGroup = grp or `IAA_GUARDS`
    end
    if not PlayerRelationship then
        local _, pGrp = AddRelationshipGroup('IAA_PLAYERS')
        PlayerRelationship = pGrp or `IAA_PLAYERS`
    end
    local playerPed = PlayerPedId()
    SetPedRelationshipGroupHash(playerPed, PlayerRelationship)
    SetRelationshipBetweenGroups(5, RelationshipGroup, PlayerRelationship)
    SetRelationshipBetweenGroups(5, PlayerRelationship, RelationshipGroup)
    SetRelationshipBetweenGroups(0, RelationshipGroup, RelationshipGroup)
end

local function ApplyGTAOnlineCombatProfile(ped, guardData)
    local s = Config.GuardSettings or {}
    SetPedCombatAbility(ped, s.CombatAbility or 2)
    SetPedCombatRange(ped, s.CombatRange or 2)
    SetPedCombatMovement(ped, s.CombatMovement or 2)
    SetPedAlertness(ped, 3)
    SetPedAccuracy(ped, s.Accuracy or 65)
    SetPedShootRate(ped, 1000)
    SetPedFiringPattern(ped, `FIRING_PATTERN_BURST_FIRE_SMG`)

    local hp = s.Health or 200
    SetEntityMaxHealth(ped, hp)
    SetEntityHealth(ped, hp)
    SetPedArmour(ped, s.Armor or 100)
    SetPedSuffersCriticalHits(ped, s.HeadshotsKill ~= false)
    SetPedDiesWhenInjured(ped, false)
    SetPedDropsWeaponsWhenDead(ped, s.DropsWeapons or false)

    SetPedSeeingRange(ped, s.VisionDistance or 45.0)
    SetPedHearingRange(ped, s.HearingDistance or 40.0)
    SetPedIdRange(ped, 50.0)
    local vAngle = s.VisionAngle or 75.0
    SetPedVisualFieldMinAngle(ped, -vAngle)
    SetPedVisualFieldMaxAngle(ped, vAngle)
    SetPedVisualFieldPeripheralRange(ped, 30.0)
    SetPedVisualFieldCenterAngle(ped, 60.0)

    for _, flag in ipairs({0, 2, 3, 5, 14, 20, 28, 38, 42, 46, 52, 58}) do
        SetPedCombatAttributes(ped, flag, true)
    end
    SetPedCombatAttributes(ped, 1, false)
    SetPedCombatAttributes(ped, 13, false)

    SetPedRelationshipGroupHash(ped, RelationshipGroup)
    SetPedVoiceGroup(ped, `SPEECH_MALE_S_M_M_SECURITY_01`)

    local weaponHash = GetHashKey(guardData.weapon or 'WEAPON_COMBATPISTOL')
    GiveWeaponToPed(ped, weaponHash, 9999, false, true)
    SetPedInfiniteAmmo(ped, true, weaponHash)
    SetPedInfiniteAmmoClip(ped, true)
    SetCurrentPedWeapon(ped, weaponHash, true)

    if s.EnableFlashlights then
        if DoesWeaponTakeWeaponComponent(weaponHash, `COMPONENT_AT_AR_FLSH`) then
            GiveWeaponComponentToPed(ped, weaponHash, `COMPONENT_AT_AR_FLSH`)
        elseif DoesWeaponTakeWeaponComponent(weaponHash, `COMPONENT_AT_PI_FLSH`) then
            GiveWeaponComponentToPed(ped, weaponHash, `COMPONENT_AT_PI_FLSH`)
        end
    end
end

local function CreateGuardBlip(ped)
    if not Config.GuardSettings or not Config.GuardSettings.EnableBlips or not DoesEntityExist(ped) then return nil end
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.65)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("IAA Security")
    EndTextCommandSetBlipName(blip)
    return blip
end

local function RemoveGuardBlip(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function DeleteGuard(guard)
    if not guard then return end
    RemoveGuardBlip(guard.blip)
    guard.blip = nil
    if DoesEntityExist(guard.ped) then
        DeletePed(guard.ped)
        DeleteEntity(guard.ped)
    end
end

local function StartGuardPatrol(guard)
    if not guard or not DoesEntityExist(guard.ped) or guard.isDead or guard.isAlerted then return end
    local ped, cfg = guard.ped, guard.config
    local coords = cfg.coords
    local spawnPos = (type(coords) == 'vector4' and vector3(coords.x, coords.y, coords.z)) or coords
    local s = Config.GuardSettings or {}
    local radius = cfg.wanderRadius or s.WanderRadius or 10.0

    ClearPedTasks(ped)
    if cfg.scenario then
        TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
    else
        TaskWanderInArea(ped, spawnPos.x, spawnPos.y, spawnPos.z, radius, 2.5, 4.0)
    end
end

local function EngageGuardInCombat(guard, targetPed)
    if not guard or not DoesEntityExist(guard.ped) or guard.isDead then return end
    guard.isAlerted = true
    guard.spottedState = false
    local ped = guard.ped
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    TaskCombatPed(ped, targetPed, 0, 16)

    if guard.combatThreadActive then return end
    guard.combatThreadActive = true

    CreateThread(function()
        while DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and guard.isAlerted do
            local dist = #(GetEntityCoords(ped) - GetEntityCoords(targetPed))
            if GetEntityHealth(ped) < 90 then
                SetPedCombatMovement(ped, 1)
                TaskSeekCoverFromPed(ped, targetPed, 5000, false)
                Wait(5000)
            elseif dist > 25.0 then
                SetPedCombatMovement(ped, 2)
                TaskCombatPed(ped, targetPed, 0, 16)
                Wait(4000)
            else
                Wait(2500)
            end
        end
        guard.combatThreadActive = false
    end)
end

local function SpotPlayer(guard, targetPed, now)
    guard.spottedState = true
    guard.spotStartTime = now
    guard.hasAlertedOthers = false
    PlayGuardSpeech(guard.ped, 'Spot', true)
    EngageGuardInCombat(guard, targetPed)
end

local function ApplyNearbyAlert(sourceIdx)
    local s = Config.GuardSettings or {}
    local alertRadius, maxZDiff = s.AlertRadius or 35.0, s.MaxFloorZDiff or 2.5
    local playerPed = PlayerPedId()

    local sourceGuard = ActiveGuards[sourceIdx]
    local sourceCoords = nil
    if sourceGuard and DoesEntityExist(sourceGuard.ped) then
        sourceCoords = GetEntityCoords(sourceGuard.ped)
        sourceGuard.hasAlertedOthers = true
        PlayGuardSpeech(sourceGuard.ped, 'Spot', true)
    elseif Config.Guards and Config.Guards[sourceIdx] then
        local c = Config.Guards[sourceIdx].coords
        sourceCoords = (type(c) == 'vector4' and vector3(c.x, c.y, c.z)) or c
    end

    local alertedAny = false
    for idx, guard in pairs(ActiveGuards) do
        if DoesEntityExist(guard.ped) and not guard.isDead then
            local shouldAlert = (idx == sourceIdx)
            if not shouldAlert and sourceCoords then
                local gCoords = GetEntityCoords(guard.ped)
                shouldAlert = (#(gCoords - sourceCoords) <= alertRadius) and (math.abs(gCoords.z - sourceCoords.z) <= maxZDiff)
            end

            if shouldAlert and not guard.isAlerted then
                alertedAny = true
                guard.hasAlertedOthers = true
                EngageGuardInCombat(guard, playerPed)
            end
        end
    end

    if alertedAny then
        ShowHelpNotification("~r~Security Alert!~s~ Nearby guards on this floor detected an intruder.")
    end
end

local function AlertNearbyGuards(sourceIdx, reason)
    TriggerServerEvent('sd-iaaheist:server:guardAlerted', sourceIdx or 1, reason or 'SPOTTED', 'IAA_GUARDS')
    ApplyNearbyAlert(sourceIdx)
end

local function StartGuardPerceptionLoop()
    if GuardCombatThreads then return end
    GuardCombatThreads = true

    -- Dedicated frame-accurate gunshot detection thread (never misses single shots)
    CreateThread(function()
        local s = Config.GuardSettings or {}
        local hDist = s.HearingDistance or 60.0
        local maxZDiff = s.MaxFloorZDiff or 3.0

        while next(ActiveGuards) ~= nil do
            local pPed = PlayerPedId()
            if IsPedShooting(pPed) then
                if not IsPedCurrentWeaponSilenced(pPed) then
                    local pCoords = GetEntityCoords(pPed)
                    for idx, guard in pairs(ActiveGuards) do
                        if DoesEntityExist(guard.ped) and not guard.isDead and not guard.isAlerted then
                            local gCoords = GetEntityCoords(guard.ped)
                            local dist = #(gCoords - pCoords)
                            local zDiff = math.abs(gCoords.z - pCoords.z)
                            if dist <= hDist and zDiff <= maxZDiff then
                                AlertNearbyGuards(idx, 'GUNSHOT_HEARD')
                                break
                            end
                        end
                    end
                    Wait(250)
                end
            end
            Wait(0)
        end
    end)

    CreateThread(function()
        local s = Config.GuardSettings or {}
        local vDist, vAngle = s.VisionDistance or 45.0, s.VisionAngle or 75.0
        local sDist = s.FootstepHearingDistance or 9.0
        local grace = s.DetectionGraceTime or 2000
        local blipDist = s.BlipDistance or 30.0
        local enableBlips = s.EnableBlips ~= false
        local maxZDiff = s.MaxFloorZDiff or 3.0

        while next(ActiveGuards) ~= nil do
            local pPed = PlayerPedId()
            local pCoords = GetEntityCoords(pPed)
            local isSprinting = IsPedSprinting(pPed) or IsPedRunning(pPed)
            local isStealth = GetPedStealthMovement(pPed) or IsPedDucking(pPed)
            local anyNear, activeCount, anyAlerted = false, 0, false
            local now = GetGameTimer()

            for idx, guard in pairs(ActiveGuards) do
                if DoesEntityExist(guard.ped) and not guard.isDead then
                    activeCount = activeCount + 1
                    local gPed = guard.ped

                    if guard.isAlerted then anyAlerted = true end

                    if IsPedDeadOrDying(gPed, true) then
                        guard.isDead, guard.spottedState = true, false
                        RemoveGuardBlip(guard.blip)
                        guard.blip = nil
                        TriggerServerEvent('sd-iaaheist:server:guardDied', idx)
                    else
                        local gCoords = GetEntityCoords(gPed)
                        local dist = #(gCoords - pCoords)
                        local zDiffToPlayer = math.abs(gCoords.z - pCoords.z)

                        -- Proximity guard blips
                        if enableBlips then
                            if dist <= blipDist then
                                if not guard.blip then guard.blip = CreateGuardBlip(gPed) end
                            elseif guard.blip then
                                RemoveGuardBlip(guard.blip)
                                guard.blip = nil
                            end
                        end

                        if dist < 120.0 then
                            anyNear = true
                            local hp = GetEntityHealth(gPed)
                            if HasEntityBeenDamagedByAnyPed(gPed) or (hp < guard.lastHealth) then
                                ClearEntityLastDamageEntity(gPed)
                                PlayGuardSpeech(gPed, 'Pain', true)
                                if hp > 0 then AlertNearbyGuards(idx, 'DAMAGED') end
                            end
                            guard.lastHealth = hp

                            -- Footsteps: only heard by unalerted guard on same floor
                            if not guard.isAlerted and not isStealth and isSprinting and dist <= sDist and zDiffToPlayer <= maxZDiff and not guard.spottedState then
                                TaskTurnPedToFaceEntity(gPed, pPed, 1000)
                                if HasEntityClearLosToEntity(gPed, pPed, 17) then
                                    SpotPlayer(guard, pPed, now)
                                end
                            end

                            -- Vision: only unalerted guards check vision cone
                            if not guard.isAlerted and dist <= vDist and zDiffToPlayer <= (maxZDiff * 2.0) then
                                local eff = isStealth and (vDist * 0.55) or vDist
                                if dist <= eff and IsInVisionCone(gPed, pCoords, vAngle) and HasEntityClearLosToEntity(gPed, pPed, 17) then
                                    SpotPlayer(guard, pPed, now)
                                end
                            end

                            -- Delayed alert to fellow guards after grace delay (2s) if still alive and in combat
                            if guard.isAlerted and not guard.hasAlertedOthers and guard.spotStartTime and guard.spotStartTime > 0 then
                                if (now - guard.spotStartTime) >= grace then
                                    guard.hasAlertedOthers = true
                                    AlertNearbyGuards(idx, 'PLAYER_SPOTTED')
                                end
                            end

                            -- Dead body discovery: only unalerted guards check on same floor
                            if not guard.isAlerted then
                                for _, other in pairs(ActiveGuards) do
                                    if other.isDead and DoesEntityExist(other.ped) then
                                        local dPos = GetEntityCoords(other.ped)
                                        if #(gCoords - dPos) <= 15.0 and math.abs(gCoords.z - dPos.z) <= maxZDiff and IsInVisionCone(gPed, dPos, vAngle) and HasEntityClearLosToEntity(gPed, other.ped, 17) then
                                            AlertNearbyGuards(idx, 'DEAD_BODY_FOUND')
                                            break
                                        end
                                    end
                                end
                            end

                            if guard.isAlerted and math.random(100) <= 8 then
                                PlayGuardSpeech(gPed, 'Combat', false)
                            end
                        end
                    end
                end
            end

            local sleep = (activeCount == 0 and 1500) or (not anyNear and 1000) or (anyAlerted and 100) or 250
            Wait(sleep)
        end
        GuardCombatThreads = false
    end)
end

function PrepareAllGuards(heistState)
    if not Config.EnableGuardsPeds or not Config.Guards or #Config.Guards == 0 then return end
    if isSpawningGuards or guardsSpawned then return end
    isSpawningGuards = true

    CleanupAllGuards()
    SetupRelationshipGroups()

    local gState = (heistState and heistState.guards) or {}

    for idx, cfg in ipairs(Config.Guards) do
        if ActiveGuards[idx] then
            DeleteGuard(ActiveGuards[idx])
            ActiveGuards[idx] = nil
        end

        if not (gState[idx] and gState[idx].isDead) then
            local model = GetHashKey(cfg.model or 'S_M_M_CIASec_01')
            RequestModel(model)
            local t = 0
            while not HasModelLoaded(model) and t < 50 do Wait(50) t = t + 1 end

            if HasModelLoaded(model) then
                local coords = cfg.coords
                local h = (type(coords) == 'vector4' and coords.w) or cfg.heading or 0.0
                local pos = (type(coords) == 'vector4' and vector3(coords.x, coords.y, coords.z)) or coords
                local ped = CreatePed(4, model, pos.x, pos.y, pos.z, h, false, true)

                SetEntityHeading(ped, h)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                ApplyGTAOnlineCombatProfile(ped, cfg)

                local guard = {
                    ped               = ped,
                    blip              = nil,
                    isDead            = false,
                    isAlerted         = false,
                    hasAlertedOthers  = false,
                    spottedState      = false,
                    spotStartTime     = 0,
                    lastHealth        = GetEntityHealth(ped),
                    config            = cfg
                }
                ActiveGuards[idx] = guard

                StartGuardPatrol(guard)
                SetModelAsNoLongerNeeded(model)
            end
        end
    end

    guardsSpawned = true
    isSpawningGuards = false
    StartGuardPerceptionLoop()
end

function CleanupAllGuards()
    guardsSpawned = false
    isSpawningGuards = false
    for _, guard in pairs(ActiveGuards) do
        guard.isAlerted = false
        guard.hasAlertedOthers = false
        DeleteGuard(guard)
    end
    ActiveGuards = {}
end

RegisterNetEvent('sd-iaaheist:client:onGuardDied', function(guardIndex)
    local guard = ActiveGuards[guardIndex]
    if guard then
        guard.isDead, guard.spottedState = true, false
        guard.isAlerted = false
        guard.hasAlertedOthers = true
        RemoveGuardBlip(guard.blip)
        guard.blip = nil
        if DoesEntityExist(guard.ped) and not IsPedDeadOrDying(guard.ped, true) then
            SetEntityHealth(guard.ped, 0)
            SetPedToRagdoll(guard.ped, 1000, 1000, 0, 0, 0, 0)
        end
    end
end)

RegisterNetEvent('sd-iaaheist:client:onGuardAlerted', function(guardIndex, reason, group)
    ApplyNearbyAlert(guardIndex)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanupAllGuards()
    end
end)
