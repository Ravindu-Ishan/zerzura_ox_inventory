if not lib then return end

--[[
	Server-authoritative equip/unequip for physical clothing items.

	The rule this file exists to enforce: the client never creates or destroys an
	item, and never applies a ped variation the server has not already paid for.

	Equip  -> server removes the item from the inventory, records what is now
	          worn, and only then hands the client the variation to apply.
	Unequip-> server checks the player can carry the item, adds it back, drops
	          the record, and only then tells the client what to revert to.

	Both are lib.callbacks, so the client gets a definitive yes/no and cannot
	"assume" the bookkeeping followed. Neither call accepts an item name, count
	or metadata from the client - the only client-supplied values are a slot
	number (equip) or a slot key (unequip), both of which are re-resolved
	against server state before anything happens.

	Why not `item.cb` / `Item(name, cb)` from modules/items/server.lua: it is
	marked @deprecated in that file, and for a `consume = 0` item it fires at the
	wrong times anyway. Tracing server.lua's `ox_inventory:useItem`:
	  * cb('usingItem') runs BEFORE the client's progress bar is confirmed, so
	    removing there can destroy an item the player then cancels;
	  * cb('usedItem') is inside `if consume and consume ~= 0 ...`, so for
	    clothing (consume = 0) it never fires at all.
	And the callback itself only ever returns `true` to the client - there is no
	server -> client data channel on that response path (client.lua hands the cb
	the client's own pre-existing slotData). So the equip trade gets its own
	callback, fired from inside the useItem callback, i.e. after the existing
	validation path has already approved the use.
]]

local Clothing = require 'modules.clothing.shared'
local Inventory = require 'modules.inventory.server'
local Items = require 'modules.items.server'

local Module = {}

---In-memory fallback for frameworks whose bridge cannot persist metadata. The
---records still work for the session; they are simply lost on relog.
local memory = {}

---Guards against two equip/unequip callbacks for the same player overlapping
---and both passing their capacity check before either has written.
local busy = {}

local function notify(playerId, description, kind)
	TriggerClientEvent('ox_lib:notify', playerId, { type = kind or 'error', description = description })
end

---@param inv OxInventory
---@return table<string, table> records keyed by slot key
local function loadRecords(inv)
	local records = server.getClothingMetadata and server.getClothingMetadata(inv)

	if type(records) ~= 'table' then
		records = memory[inv.id]
	end

	if type(records) ~= 'table' then return {} end

	-- Anything we don't recognise is dropped rather than carried forward - a
	-- stale key would otherwise sit in the save forever and show up as a ghost
	-- tile on the Appearance card.
	for key, record in pairs(records) do
		if not Clothing.byKey[key] or type(record) ~= 'table' or type(record.item) ~= 'string' then
			records[key] = nil
		end
	end

	return records
end

---@param inv OxInventory
---@param records table<string, table>
local function saveRecords(inv, records)
	memory[inv.id] = records

	if server.setClothingMetadata then
		server.setClothingMetadata(inv, records)
	end
end

AddEventHandler('playerDropped', function()
	memory[source] = nil
end)

---Only the three slots with no native "nothing worn" state need a remembered
---value to go back to; the other three revert to a real engine-level empty.
---@param value any
---@return { drawable: number, texture: number }?
local function sanitiseRevert(value)
	if type(value) ~= 'table' then return end
	if type(value.drawable) ~= 'number' or type(value.texture) ~= 'number' then return end
	if value.drawable < 0 or value.texture < 0 then return end

	return { drawable = math.floor(value.drawable), texture = math.floor(value.texture) }
end

---@param inv OxInventory
---@param payload { slot: number, revert: table? }
local function equip(inv, payload)
	local slotId = type(payload) == 'table' and payload.slot

	if type(slotId) ~= 'number' then return end

	local slotData = inv.items[slotId]

	if not slotData then return end

	local variation = Clothing.getVariation(slotData.name, slotData.metadata)

	if not variation then
		notify(inv.id, 'That is not something you can wear.')
		return
	end

	-- Captured up front: RemoveItem below mutates (and can nil) inv.items[slotId].
	local itemName = slotData.name
	local itemMetadata = slotData.metadata and table.deepclone(slotData.metadata) or nil
	local itemLabel = slotData.metadata?.label or Items(itemName)?.label or itemName

	local slotDef = Clothing.byKey[variation.key]
	local records = loadRecords(inv)
	local current = records[variation.key]

	-- Swapping: the item already on this slot has to come back to the bag. Check
	-- that it fits BEFORE removing the new one. The check is pessimistic (the
	-- new item is still taking up its slot and weight at this point) which is
	-- the safe direction: it can refuse a swap that would just barely have fit,
	-- but it can never approve one that would not.
	if current then
		if not Items(current.item) then
			-- The worn item no longer exists in the item list. Nothing to give
			-- back; drop the record so the player is not stuck.
			records[variation.key] = nil
			current = nil
		elseif not Inventory.CanCarryItem(inv, current.item, 1, current.metadata) then
			notify(inv.id, ('You have no room to take off your %s first.'):format(current.label or current.item))
			return
		end
	end

	if not Inventory.RemoveItem(inv, itemName, 1, nil, slotId) then return end

	if current then
		if not Inventory.AddItem(inv, current.item, 1, current.metadata) then
			-- Should be unreachable given the pre-check. Put the new item back
			-- rather than leaving the player short of both: worst case here is
			-- "nothing happened", never a duplicate.
			Inventory.AddItem(inv, itemName, 1, itemMetadata)
			warn(('failed to return worn clothing "%s" to inventory-%s; equip aborted'):format(current.item, inv.id))
			return
		end
	end

	local record = {
		item = itemName,
		label = itemLabel,
		kind = variation.kind,
		id = variation.id,
		drawable = variation.drawable,
		texture = variation.texture,
		metadata = itemMetadata,
		-- On a swap, keep the ORIGINAL pre-clothing reading rather than the one
		-- the client just took - that reading is of the item being replaced, and
		-- reverting to it later would put a garment back that is now in the bag.
		revert = not slotDef.canBeEmpty and (current and current.revert or sanitiseRevert(payload.revert)) or nil,
	}

	records[variation.key] = record
	saveRecords(inv, records)

	return { key = variation.key, record = record }
end

---A preferred destination slot, as sent by a drag of the equipped tile onto a
---specific inventory square. Purely cosmetic - Inventory.AddItem falls back to
---its own search when the slot is taken - but it MUST be range-checked here.
---AddItem will happily write to `inv.items[slot]` for any slot number it finds
---empty, including one past `inv.slots`, which would park the item in a square
---the player can never see or reach.
---@param inv OxInventory
---@param value any
---@return number?
local function sanitiseTargetSlot(inv, value)
	if type(value) ~= 'number' then return end
	if value ~= math.floor(value) then return end
	if value < 1 or value > inv.slots then return end

	return value
end

---@param inv OxInventory
---@param payload string | { key: string, slot: number? } slot key, or the key plus a preferred destination slot
local function unequip(inv, payload)
	local key = type(payload) == 'table' and payload.key or payload

	if type(key) ~= 'string' then return end

	local targetSlot = type(payload) == 'table' and sanitiseTargetSlot(inv, payload.slot) or nil

	local slotDef = Clothing.byKey[key]

	if not slotDef then return end

	local records = loadRecords(inv)
	local record = records[key]

	if not record then return end

	local instruction = {
		key = key,
		kind = slotDef.kind,
		id = slotDef.id,
		canBeEmpty = slotDef.canBeEmpty,
		emptyValue = slotDef.emptyValue,
		bare = slotDef.bare,
		revert = record.revert,
	}

	if not Items(record.item) then
		-- Item was removed from the catalog while worn. There is nothing to give
		-- back, but the player should still be able to take it off.
		records[key] = nil
		saveRecords(inv, records)
		warn(('worn clothing "%s" no longer exists; cleared it from inventory-%s'):format(record.item, inv.id))

		return instruction
	end

	if not Inventory.CanCarryItem(inv, record.item, 1, record.metadata) then
		notify(inv.id, ('You have no room to carry your %s.'):format(record.label or record.item))
		return
	end

	if not Inventory.AddItem(inv, record.item, 1, record.metadata, targetSlot) then
		notify(inv.id, ('You have no room to carry your %s.'):format(record.label or record.item))
		return
	end

	records[key] = nil
	saveRecords(inv, records)

	return instruction
end

---@param source number
---@param fn fun(inv: OxInventory, ...): any
local function guarded(source, fn, ...)
	local inv = Inventory(source) --[[@as OxInventory]]

	if not inv?.player then return end
	if busy[source] then return end

	busy[source] = true

	local ok, result = pcall(fn, inv, ...)

	busy[source] = nil

	if not ok then
		warn(result)
		return
	end

	return result
end

---Take the item out of the bag and put it on the ped.
---@return { key: string, record: table }? confirmation the client applies its visual from
lib.callback.register('ox_inventory:clothing:equip', function(source, payload)
	return guarded(source, equip, payload)
end)

---Take it off the ped and put the same item back in the bag.
---
---`payload` is either the bare slot key (right-click -> Unequip, which has no
---opinion about where the item lands) or `{ key = ..., slot = ... }` when the
---tile was dragged onto a specific inventory square. The slot is a preference,
---not an instruction: it is range-checked above and then handed to AddItem,
---which ignores it if that square is occupied.
---@return table? instruction telling the client what to revert this slot to
lib.callback.register('ox_inventory:clothing:unequip', function(source, payload)
	return guarded(source, unequip, payload)
end)

---Re-apply on spawn / after an ox_inventory restart.
lib.callback.register('ox_inventory:clothing:getEquipped', function(source)
	local inv = Inventory(source) --[[@as OxInventory]]

	if not inv?.player then return end

	return loadRecords(inv)
end)

-----------------------------------------------------------------------------------------------
-- Starter kit
-----------------------------------------------------------------------------------------------

--[[
	A character's first-ever load gets one real garment for each of the three
	always-worn slots (see Clothing.starter in shared.lua for why those three).

	This is free item creation, so it is the one place in this module where
	getting the bookkeeping wrong is a duplication exploit rather than an
	inconvenience: anything keyed off "is this player loading in" repeats every
	single relog. The protection is a persistent per-character flag, and the
	ordering around it is deliberate:

	  1. Read the flag. Set -> return immediately, nothing happens.
	  2. CLAIM the flag, and bail if the framework will not promise to store it
	     (server.setPlayerFlag returns false). On qbx this also queues the
	     player row's database write there and then, rather than leaving the
	     value to the next periodic save.
	  3. Only then create the items.

	Claiming before creating is the fail-safe direction, and it is a direction
	rather than a lock - no framework here offers a transaction across "player
	metadata" and "inventory contents". What it buys is that the only crash
	window that exists costs the character their free clothes (annoying, fixable
	with /giveitem) instead of handing out another set on every subsequent
	login, forever. The flag write is dispatched immediately while the items are
	only persisted by ox_inventory's own periodic inventory save, so losing the
	items but keeping the flag is the likely failure and the reverse effectively
	cannot happen. Never trade a dupe for a convenience.

	Existing characters have no flag, so they are backfilled once on their next
	login. That is intended - they are in exactly the same position as a new
	character, wearing clothes no item backs.
]]

local STARTER_FLAG = 'starterClothingGranted'

---@param inv OxInventory
function Module.grantStarterKit(inv)
	if not inv?.player then return end

	-- Already has them (or already had them and threw them away). Either way,
	-- this character has been paid out.
	if server.getPlayerFlag(inv, STARTER_FLAG) then return end

	-- Fail-closed: a framework that cannot store the flag must not be given
	-- items, because it would be given them again on every relog.
	if not server.setPlayerFlag(inv, STARTER_FLAG, true) then
		return warn(('cannot record a starter clothing grant for inventory-%s, so none was made'):format(inv.id))
	end

	for i = 1, #Clothing.starter do
		local name = Clothing.starter[i]

		if not Items(name) then
			warn(('starter clothing item "%s" does not exist and was skipped'):format(name))
		else
			local ok, response = Inventory.AddItem(inv, name, 1)

			if not ok then
				warn(('failed to give starter clothing "%s" to inventory-%s (%s)'):format(name, inv.id, response))
			end
		end
	end
end

return Module
