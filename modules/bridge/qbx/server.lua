assert(lib.checkDependency('qbx_core', '1.18.1'), 'qbx_core v1.18.1 or higher is required')
assert(lib.checkDependency('qbx_vehicles', '1.2.0'), 'qbx_vehicles v1.2.0 or higher is required')
local Inventory = require 'modules.inventory.server'
local QBX = exports.qbx_core

AddEventHandler('qbx_core:server:playerLoggedOut', server.playerDropped)

AddEventHandler('qbx_core:server:onGroupUpdate', function(source, groupName, groupGrade)
    local inventory = Inventory(source)
    if not inventory then return end
    inventory.player.groups[groupName] = not groupGrade and nil or groupGrade
end)

---Lazily required. server.lua loads modules/bridge/server.lua (which loads THIS
---file) before modules/clothing/server.lua, so requiring the clothing module at
---the top of this file would drag it - and the item/inventory modules it pulls
---in - ahead of that order for no reason. By the time setupPlayer runs, the
---whole resource is up.
local ClothingServer

local function setupPlayer(playerData)
    playerData.identifier = playerData.citizenid
    playerData.name = ('%s %s'):format(playerData.charinfo.firstname, playerData.charinfo.lastname)
    server.setPlayerInventory(playerData)

    -- Starter clothing for a character that has never had it. This runs on
    -- EVERY load - see modules/clothing/server.lua for the persistent flag that
    -- makes the grant itself happen exactly once.
    local inventory = Inventory(playerData.source)

    if inventory then
        ClothingServer = ClothingServer or require 'modules.clothing.server'
        ClothingServer.grantStarterKit(inventory)
    end

    local accounts = Inventory.GetAccountItemCounts(playerData.source)
    if not accounts then return end
    for account in pairs(accounts) do
        local playerAccount = account == 'money' and 'cash' or account
        Inventory.SetItem(playerData.source, account, playerData.money[playerAccount])
    end
end

AddStateBagChangeHandler('loadInventory', nil, function(bagName, _, value)
    if not value then return end
    local plySrc = GetPlayerFromStateBagName(bagName)
    if not plySrc then return end
    setupPlayer(QBX:GetPlayer(plySrc).PlayerData)
end)

SetTimeout(500, function()
    local playersData = QBX:GetPlayersData()
    for i = 1, #playersData do setupPlayer(playersData[i]) end
end)

function server.UseItem(source, itemName, data)
    local cb = QBX:CanUseItem(itemName)
    return cb and cb(source, data)
end

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
    local groups = QBX:GetGroups(player.source)
    return {
        source = player.source,
        name = ('%s %s'):format(player.charinfo.firstname, player.charinfo.lastname),
        groups = groups,
        sex = player.charinfo.gender,
        dateofbirth = player.charinfo.birthdate,
    }
end

---@diagnostic disable-next-line: duplicate-set-field
function server.syncInventory(inv)
    local accounts = Inventory.GetAccountItemCounts(inv)

    if not accounts then return end

    local player = QBX:GetPlayer(inv.id)
    player.Functions.SetPlayerData('items', inv.items)

    for account, amount in pairs(accounts) do
        account = account == 'money' and 'cash' or account
        if player.Functions.GetMoney(account) ~= amount then
            player.Functions.SetMoney(account, amount, ('Sync %s with inventory'):format(account))
        end
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.hasLicense(inv, license)
    local player = QBX:GetPlayer(inv.id)
    return player and player.PlayerData.metadata.licences[license]
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense(inv, license)
    local player = QBX:GetPlayer(inv.id)
    if not player then return end

    if player.PlayerData.metadata.licences[license.name] then
        return false, 'already_have'
    elseif Inventory.GetItem(inv, 'money', false, true) < license.price then
        return false, 'can_not_afford'
    end

    Inventory.RemoveItem(inv, 'money', license.price)
    player.PlayerData.metadata.licences[license.name] = true
    player.Functions.SetMetaData('licences', player.PlayerData.metadata.licences)

    return true, 'have_purchased'
end

---Equipped clothing lives in qbx_core player metadata, exactly like licences
---above: written through SetMetaData so it rides the framework's own player
---save. No new table, no new query.
---@param inv OxInventory
---@return table<string, table>?
---@diagnostic disable-next-line: duplicate-set-field
function server.getClothingMetadata(inv)
    local player = QBX:GetPlayer(inv.id)
    return player and player.PlayerData.metadata.equippedClothing
end

---@param inv OxInventory
---@param value table<string, table>
---@diagnostic disable-next-line: duplicate-set-field
function server.setClothingMetadata(inv, value)
    local player = QBX:GetPlayer(inv.id)
    if not player then return end

    player.PlayerData.metadata.equippedClothing = value
    player.Functions.SetMetaData('equippedClothing', value)
end

---One-time flags, in the same qbx_core player metadata as equippedClothing.
---
---Durability is the whole point here (see modules/bridge/server.lua). qbx_core
---gives us about as much as it has: server/player.lua's SetMetadata ends with
---`savePlayer(player)` -> `Save(source)`, which queues the players-row upsert
---immediately rather than leaving the value sitting in memory until the next
---periodic save.
---
---It is queued, not awaited - Save wraps storage.upsertPlayerEntity in a
---CreateThread - so this is "written within a tick", not "committed before this
---function returns". That is still the right side of the trade: the flag write
---is dispatched the moment it is set, whereas the items it guards are only
---persisted by ox_inventory's own (far slower, periodic) inventory save. A
---crash cannot therefore keep the items while losing the flag; if anything is
---lost, the items go first.
---@param inv OxInventory
---@param key string
---@return any
---@diagnostic disable-next-line: duplicate-set-field
function server.getPlayerFlag(inv, key)
    local player = QBX:GetPlayer(inv.id)
    return player and player.PlayerData.metadata[key]
end

---@param inv OxInventory
---@param key string
---@param value any
---@return boolean persisted
---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerFlag(inv, key, value)
    local player = QBX:GetPlayer(inv.id)
    if not player then return false end

    player.PlayerData.metadata[key] = value
    player.Functions.SetMetaData(key, value)

    return true
end

---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerBoss(playerId, group, grade)
    return QBX:IsGradeBoss(group, grade)
end

---@param entityId number
---@return number | string
---@diagnostic disable-next-line: duplicate-set-field
function server.getOwnedVehicleId(entityId)
    return Entity(entityId).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(GetVehicleNumberPlateText(entityId))
end
