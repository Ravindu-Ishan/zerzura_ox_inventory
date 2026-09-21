if not lib then return end

--[[
	Client half of item-backed clothing.

	This file never decides that an item was worn or taken off - it asks the
	server and applies whatever the server confirms. The only thing it is
	trusted with is reading the ped (to validate a drawable before the server is
	asked to take the item, and to remember what the ped looked like before a
	torso/legs/feet garment went on) and pushing pixels afterwards.

	`Equipped` is a read-model, not state: it mirrors the server's records so the
	Appearance card can print real item labels and know which tiles are
	clickable. Nothing is ever equipped because this table says so.
]]

local Clothing = require 'modules.clothing.shared'

local APPEARANCE_RESOURCE = 'illenium-appearance'

---@type table<string, table> slot key -> server's equipped record
local Equipped = {}

local Module = {}

---Lazily resolved: modules.appearance.client requires THIS file, so requiring it
---back at load time would be a cycle.
local Appearance

local function refreshAppearance()
	Appearance = Appearance or require 'modules.appearance.client'
	Appearance.refresh()
end

---@return table<string, table> the live read-model, for modules.appearance.client
function Module.getEquipped()
	return Equipped
end

---@param record table
local function applyRecord(record)
	if record.kind == 'prop' then
		SetPedPropIndex(cache.ped, record.id, record.drawable, record.texture, true)
	else
		SetPedComponentVariation(cache.ped, record.id, record.drawable, record.texture, 0)
	end
end

---@param record table
---@return boolean
local function isApplied(record)
	if record.kind == 'prop' then
		return GetPedPropIndex(cache.ped, record.id) == record.drawable
			and GetPedPropTextureIndex(cache.ped, record.id) == record.texture
	end

	return GetPedDrawableVariation(cache.ped, record.id) == record.drawable
		and GetPedTextureVariation(cache.ped, record.id) == record.texture
end

---Put the slot back to whatever "not wearing our item" means for it.
---
---  * head   - ClearPedProp. A real engine-level absence.
---  * mask   - drawable 0. Freemode convention for a bare face.
---  * armour - drawable 0. Freemode convention for no vest overlay.
---  * torso / legs / feet - there is no empty here, so go back to the exact
---    drawable/texture the ped had immediately before the item went on. That
---    reading was taken client-side at equip time and has been stored server-
---    side with the record ever since, so it survives a relog. `bare` is only
---    used if that reading is missing (see shared.lua).
---@param data table instruction returned by the unequip callback
local function revertSlot(data)
	if data.kind == 'prop' then
		return ClearPedProp(cache.ped, data.id)
	end

	local drawable, texture

	if data.revert then
		drawable, texture = data.revert.drawable, data.revert.texture
	elseif data.canBeEmpty then
		drawable, texture = data.emptyValue, 0
	else
		drawable, texture = data.bare, 0
	end

	if type(drawable) ~= 'number' then return end

	SetPedComponentVariation(cache.ped, data.id, drawable, texture or 0, 0)
end

---@param variation table
---@return boolean valid
local function isVariationValid(variation)
	if variation.kind == 'prop' then
		return SetPedPreloadPropData(cache.ped, variation.id, variation.drawable, variation.texture)
	end

	return IsPedComponentVariationValid(cache.ped, variation.id, variation.drawable, variation.texture)
end

---Wear the clothing item in the given inventory slot.
---
---Called from the `Item('clothing', ...)` handler in modules/items/client.lua,
---i.e. only after server.lua's `ox_inventory:useItem` has already approved the
---use. Nothing is applied to the ped until the server confirms it has taken the
---item out of the inventory.
---@param slotId number
function Module.equip(slotId)
	local slotData = PlayerData.inventory[slotId]

	if not slotData then return end

	local variation = Clothing.getVariation(slotData.name, slotData.metadata)

	if not variation then
		return lib.notify({ type = 'error', description = 'That is not something you can wear.' })
	end

	-- Validated here, before the server is asked for anything: a garment that
	-- does not exist on this ped model (every value in the starter catalog is
	-- male-only) must fail with the item still in the bag, not after it has
	-- been consumed into an invisible nothing.
	if not isVariationValid(variation) then
		return lib.notify({ type = 'error', description = 'That does not fit this body.' })
	end

	local slotDef = Clothing.byKey[variation.key]
	local revert

	if not slotDef.canBeEmpty then
		revert = {
			drawable = GetPedDrawableVariation(cache.ped, slotDef.id),
			texture = GetPedTextureVariation(cache.ped, slotDef.id),
		}
	end

	local result = lib.callback.await('ox_inventory:clothing:equip', false, { slot = slotId, revert = revert })

	if not result then return end

	Equipped[result.key] = result.record
	applyRecord(result.record)
	refreshAppearance()
end

---Take off whatever is worn in the given slot and put the item back in the bag.
---@param key string one of Clothing.byKey
function Module.unequip(key)
	if not Clothing.byKey[key] or not Equipped[key] then return end

	local result = lib.callback.await('ox_inventory:clothing:unequip', false, key)

	if not result then return end

	Equipped[result.key] = nil
	revertSlot(result)
	refreshAppearance()
end

-- Fired by the Appearance card when a tile holding a real equipped item is
-- clicked. cb() first so CEF is not left waiting on the server round trip.
RegisterNUICallback('unequipClothing', function(data, cb)
	cb(1)

	local key = type(data) == 'table' and data.key or data

	if type(key) ~= 'string' then return end

	Module.unequip(key)
end)

-----------------------------------------------------------------------------------------------
-- Restoring on spawn
-----------------------------------------------------------------------------------------------

--[[
	The sequencing problem, and why this polls instead of waiting on an event.

	illenium-appearance restores the character's saved base appearance on spawn:
	client/framework/qb/main.lua listens for QBCore:Client:OnPlayerLoaded and
	calls InitAppearance(), which fires the ASYNC callback
	`illenium-appearance:server:getAppearance` and applies the result via
	setPlayerAppearance -> setPedComponents/setPedProps. That writes EVERY
	component, so anything we put on the ped beforehand is silently overwritten.

	There is no completion event to hook: I read illenium-appearance's client,
	game/util.lua and its framework bridges - setPlayerAppearance emits nothing,
	and the only exported surface is the getters/setters. A fixed Wait() would
	just be a guess that breaks on a slow server.

	So: ask illenium-appearance's own server callback for the same saved
	appearance it is about to apply, then wait until the ped actually matches it.
	That is an observation of the finished work rather than a bet on how long it
	takes. The slots we are about to fill are excluded from the comparison -
	otherwise an ox_inventory restart mid-session (where the ped is already
	wearing our items) could never match and would always burn the full timeout.
]]

local RESTORE_TIMEOUT = 20000
local SETTLE_PASSES = 6
local SETTLE_INTERVAL = 500

---@param saved table appearance as returned by illenium-appearance
---@param skip table<number, true> component ids our own records occupy
---@return boolean
local function pedMatches(saved, skip)
	-- illenium-appearance stores the model as a name string (game/util.lua's
	-- getPedModel maps the hash back through its own table), but accept a raw
	-- hash too rather than silently never matching if that ever changes.
	local model = saved.model

	if model then
		if type(model) == 'string' then model = joaat(model) end

		if type(model) == 'number' and GetEntityModel(cache.ped) ~= model then return false end
	end

	for i = 1, #saved.components do
		local entry = saved.components[i]
		local id = entry.component_id

		if id and not skip[id] then
			if GetPedDrawableVariation(cache.ped, id) ~= entry.drawable then return false end
			if GetPedTextureVariation(cache.ped, id) ~= entry.texture then return false end
		end
	end

	return true
end

---Block until illenium-appearance has finished putting the base appearance back
---on the ped (or until we give up).
---@param records table<string, table>
---@return boolean settled
local function waitForBaseAppearance(records)
	if GetResourceState(APPEARANCE_RESOURCE) ~= 'started' then return true end

	local ok, saved = pcall(lib.callback.await, 'illenium-appearance:server:getAppearance', false)

	-- No saved appearance means a brand new character still in creation; there
	-- is nothing for it to overwrite us with.
	if not ok or type(saved) ~= 'table' or type(saved.components) ~= 'table' then return true end

	local skip = {}

	for _, record in pairs(records) do
		if record.kind == 'component' then
			skip[record.id] = true
		end
	end

	local deadline = GetGameTimer() + RESTORE_TIMEOUT

	repeat
		if pedMatches(saved, skip) then return true end

		Wait(200)
	until GetGameTimer() > deadline

	warn(('timed out waiting for %s to restore the base appearance; equipped clothing may be overwritten')
		:format(APPEARANCE_RESOURCE))

	return false
end

local restoring = false

local function doRestore()
	local ok, records = pcall(lib.callback.await, 'ox_inventory:clothing:getEquipped', false)

	for key in pairs(Equipped) do
		Equipped[key] = nil
	end

	if ok and type(records) == 'table' then
		for key, record in pairs(records) do
			if Clothing.byKey[key] and type(record) == 'table' then
				Equipped[key] = record
			end
		end
	end

	if not next(Equipped) then
		return refreshAppearance()
	end

	waitForBaseAppearance(Equipped)

	for _, record in pairs(Equipped) do
		applyRecord(record)
	end

	refreshAppearance()

	-- Belt and braces. The wait above is an observation, not a lock: a late
	-- write from illenium-appearance (or a job outfit, or another script) can
	-- still land just after it returns. Re-assert for a few seconds rather than
	-- leaving the player visibly not wearing an item their bag no longer holds.
	for _ = 1, SETTLE_PASSES do
		Wait(SETTLE_INTERVAL)

		for _, record in pairs(Equipped) do
			if not isApplied(record) then
				applyRecord(record)
			end
		end
	end
end

---Re-apply everything the server says this character is wearing.
---
---Called from client.lua once PlayerData.loaded flips, which covers both a
---fresh login and an ox_inventory restart mid-session. The guard is released in
---all cases - a restore that errors must not wedge the flag on and block every
---later attempt.
function Module.restore()
	if restoring then return end

	restoring = true

	local ok, err = pcall(doRestore)

	restoring = false

	if not ok then warn(err) end
end

return Module
