Bridge = { Framework = nil, Inventory = nil, Core = nil }
local isServer = IsDuplicityVersion()

local function Init()
    local fw = Config.Framework or 'auto'
    if fw == 'auto' then
        fw = (GetResourceState('qbx_core') == 'started' and 'qbox') or
             (GetResourceState('qb-core') == 'started' and 'qb') or
             (GetResourceState('es_extended') == 'started' and 'esx') or 'qb'
    end
    Bridge.Framework = fw

    if fw == 'qbox' and GetResourceState('qbx_core') == 'started' then
        Bridge.Core = exports['qbx_core']
    elseif (fw == 'qb' or fw == 'qbox') and GetResourceState(Config.GetCoreObject or 'qb-core') == 'started' then
        Bridge.Core = exports[Config.GetCoreObject or 'qb-core']:GetCoreObject()
    elseif fw == 'esx' and GetResourceState(Config.GetSharedObject or 'es_extended') == 'started' then
        Bridge.Core = exports[Config.GetSharedObject or 'es_extended']:getSharedObject()
    end

    local inv = Config.Inventory or 'auto'
    if inv == 'auto' then
        inv = (GetResourceState('ox_inventory') == 'started' and 'ox_inventory') or
              (GetResourceState('qs-inventory') == 'started' and 'qs-inventory') or 'framework'
    end
    Bridge.Inventory = inv

    if isServer then
        print(string.format('^2[sd-iaaheist Bridge]^7 Framework: ^3%s^7 | Inventory: ^3%s^7', fw, inv))
    end
end
Init()



if isServer then

    function Bridge.GetPlayer(source)
        if not source or source <= 0 or not Bridge.Core then return nil end
        if (Bridge.Framework == 'qbox' or Bridge.Framework == 'qb') and Bridge.Core.Functions then
            return Bridge.Core.Functions.GetPlayer(source)
        elseif Bridge.Framework == 'esx' and Bridge.Core.GetPlayerFromId then
            return Bridge.Core.GetPlayerFromId(source)
        end
        return nil
    end

    function Bridge.GetItemCount(source, itemName)
        if not source or not itemName then return 0 end
        if Bridge.Inventory == 'ox_inventory' then
            return exports.ox_inventory:GetItemCount(source, itemName) or 0
        elseif Bridge.Inventory == 'qs-inventory' then
            return exports['qs-inventory']:GetItemTotalAmount(source, itemName) or 0
        end

        local Player = Bridge.GetPlayer(source)
        if not Player then return 0 end

        if Bridge.Framework == 'qb' or Bridge.Framework == 'qbox' then
            local item = Player.Functions.GetItemByName(itemName)
            return (item and item.amount) or 0
        elseif Bridge.Framework == 'esx' then
            local item = Player.getInventoryItem(itemName)
            return (item and (item.count or item.amount)) or 0
        end
        return 0
    end

    function Bridge.AddItem(source, itemName, count)
        count = tonumber(count) or 1
        if not source or not itemName or count <= 0 then return false end
        if Bridge.Inventory == 'ox_inventory' then
            return exports.ox_inventory:AddItem(source, itemName, count)
        elseif Bridge.Inventory == 'qs-inventory' then
            return exports['qs-inventory']:AddItem(source, itemName, count)
        end

        local Player = Bridge.GetPlayer(source)
        if not Player then return false end

        if Bridge.Framework == 'qb' or Bridge.Framework == 'qbox' then
            return Player.Functions.AddItem(itemName, count)
        elseif Bridge.Framework == 'esx' then
            Player.addInventoryItem(itemName, count)
            return true
        end
        return false
    end

    function Bridge.RemoveItem(source, itemName, count)
        count = tonumber(count) or 1
        if not source or not itemName or count <= 0 then return false end
        if Bridge.Inventory == 'ox_inventory' then
            return exports.ox_inventory:RemoveItem(source, itemName, count)
        elseif Bridge.Inventory == 'qs-inventory' then
            return exports['qs-inventory']:RemoveItem(source, itemName, count)
        end

        local Player = Bridge.GetPlayer(source)
        if not Player then return false end

        if Bridge.Framework == 'qb' or Bridge.Framework == 'qbox' then
            return Player.Functions.RemoveItem(itemName, count)
        elseif Bridge.Framework == 'esx' then
            Player.removeInventoryItem(itemName, count)
            return true
        end
        return false
    end

    function Bridge.AddMoney(source, account, amount)
        amount = tonumber(amount) or 0
        if not source or amount <= 0 then return false end
        local Player = Bridge.GetPlayer(source)
        if not Player then return false end

        local isCash = (account == 'money' or account == 'cash')
        if Bridge.Framework == 'qb' or Bridge.Framework == 'qbox' then
            Player.Functions.AddMoney(isCash and 'cash' or 'bank', amount)
            return true
        elseif Bridge.Framework == 'esx' then
            Player.addAccountMoney(isCash and 'money' or 'bank', amount)
            return true
        end
        return false
    end

    function Bridge.GetPoliceCount()
        if Bridge.Framework == 'qbox' and exports.qbx_core and exports.qbx_core.GetDutyCountJob then
            return exports.qbx_core:GetDutyCountJob('police')
        elseif (Bridge.Framework == 'qb' or Bridge.Framework == 'qbox') and Bridge.Core and Bridge.Core.Functions then
            local count = 0
            for _, player in pairs(Bridge.Core.Functions.GetQBPlayers() or {}) do
                if player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.name == 'police' and player.PlayerData.job.onduty then
                    count = count + 1
                end
            end
            return count
        elseif Bridge.Framework == 'esx' and Bridge.Core and Bridge.Core.GetExtendedPlayers then
            return #(Bridge.Core.GetExtendedPlayers('job', 'police') or {})
        end
        return 0
    end

    function Bridge.Notify(source, message, msgType)
        if source and message then
            TriggerClientEvent('sd-iaaheist:client:ShowNotification', source, message)
        end
    end

else

    function Bridge.HasItem(itemName, count)
        count = count or 1
        if Bridge.Inventory == 'ox_inventory' then
            local c = exports.ox_inventory:GetItemCount(itemName)
            return (c and c >= count)
        end
        if (Bridge.Framework == 'qb' or Bridge.Framework == 'qbox') and Bridge.Core and Bridge.Core.Functions then
            return Bridge.Core.Functions.HasItem(itemName, count)
        elseif Bridge.Framework == 'esx' and Bridge.Core and Bridge.Core.SearchInventory then
            return (Bridge.Core.SearchInventory(itemName, count) >= count)
        end
        return false
    end

    function Bridge.Notify(message, msgType)
        if not message then return end
        if ShowHelpNotification then
            ShowHelpNotification(message)
        else
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandDisplayHelp(0, false, true, -1)
        end
    end

end
