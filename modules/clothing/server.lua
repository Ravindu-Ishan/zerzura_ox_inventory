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
-- First-load sync of the clothes the character was created in
-----------------------------------------------------------------------------------------------

--[[
	A character comes out of character creation already dressed - the creator
	picks a torso, legs and feet drawable and illenium-appearance saves them.
	Those three slots have no "nothing worn" state (see Clothing.alwaysWorn in
	shared.lua), so the ped is definitely wearing something there, and until now
	that something was backed by no inventory item: the Appearance card could
	only say "Worn", and there was nothing to take off.

	This closes that gap by SYNCING, not by granting. On a character's first
	relevant load the client reads the drawable/texture actually on the ped -
	once the ped has been observed to match the character's stored appearance,
	see waitForSettledAppearance in client.lua, which is a stricter wait than
	the one the spawn restore uses and explains why - and reports them here. The
	server then mints one equipped record per slot pointing at exactly those
	numbers. The player keeps the clothes they made; they just now have an item
	behind them that can be taken off.

	This deliberately replaces an earlier, wrong approach that handed every new
	character three fixed catalog garments (a bomber jacket, belted jeans,
	patrol boots). That put clothes on people they had not chosen and left the
	ones they had chosen still unbacked, which is why it is gone rather than
	kept alongside this.

	The backing item is the stock generic `clothing` item, whose appearance
	lives entirely in its metadata (Clothing.getVariation prefers
	metadata.component/drawable/texture over the named catalog). That is the
	only honest option: an arbitrary drawable index out of character creation
	has no product name, so it gets a generic per-slot label and a metadata
	payload that reproduces the exact same variation if it is ever put back on.

	`revert` is intentionally never set on these records. `revert` means "what
	the ped looked like before this item went on", and for a synced record there
	is no before - this IS the baseline. revertSlot in client.lua already falls
	through a nil `revert` to the slot's `bare` drawable, so taking off the
	starting shirt leaves the ped bare-chested, which is the correct answer.

	One-time-ness still matters, though not for the old reason. Nothing here is
	free money, but re-running it after the player took a synced garment off
	would mint a second one, so it keeps the same persistent flag discipline the
	grant had:

	  1. Read the flag. Already done for a slot -> that slot is never touched
	     again.
	  2. CLAIM the flag, and bail if the framework will not promise to store it.
	  3. Only then write records.

	The flag is PER SLOT rather than one boolean for the character, because
	"already has a real item on this slot" and "already synced this slot" are
	different facts and conflating them loses one of them. The test character
	that ran the old grant is the case in point: it is wearing a bomber jacket
	on torso, so torso must be left alone now - but the moment that jacket comes
	off, the shirt underneath is once again a garment with no item behind it, and
	it should be synced then. A single boolean set on this pass would have closed
	that door forever. A slot is marked done only when a record is actually
	minted for it, so taking a synced garment off can never re-trigger it.

	NOTE the flag key is NEW. The old `starterClothingGranted` flag is already
	set on any character that loaded under the previous version, and reusing it
	would skip this sync entirely for exactly the characters that need it most.

	Characters that predate this feature have no flag either, so they are
	backfilled once on their next login - the same principle the old code had,
	and the reason it has to work for characters that are not "new".
]]

local SYNC_FLAG = 'starterClothingSynced'

---The item every synced record is backed by. Metadata-driven, so one item name
---covers all three slots and any drawable/texture the creator produced.
local SYNC_ITEM = 'clothing'

---Generic, honest labels. We know which slot a garment occupies and nothing
---else about it - an arbitrary drawable index has no product name, and making
---one up would put a confident lie in the player's bag.
local SYNC_LABELS = {
	torso = 'Shirt',
	legs = 'Jeans',
	feet = 'Shoes',
}

--[[
	Bounds for the client-reported values.

	The trust model here is genuinely different from equip/unequip, and worth
	being explicit about. There is no item to steal or duplicate: the client is
	not naming an item, a count or a source slot - the item name, the label and
	the slot are all decided here, and the sync runs at most once per character.
	The worst a forged payload achieves is one weightless generic `clothing`
	item whose drawable is a number of the liar's choosing, which they could
	already have asked an admin for. That is not an economy exploit.

	What is worth guarding is garbage propagating into ped state: a negative,
	fractional or absurd index would be handed to SetPedComponentVariation on
	re-equip and stored in the character's metadata forever. So the values are
	required to be non-negative integers inside a range comfortably wider than
	any real freemode component (torso tops out in the low hundreds with DLC),
	and anything outside it drops that slot rather than the whole sync.

	This cannot be a real validity check - IsPedComponentVariationValid is a
	client native and the server has no ped. The real check already exists
	client-side at re-equip time (isVariationValid in client.lua refuses to
	apply an invalid variation with the item still in the bag), and the
	Appearance card independently cross-checks every record against the live ped
	before it will name an item, so a fabricated record simply shows as "Worn".
]]
local MAX_DRAWABLE = 1023
local MAX_TEXTURE = 63

---@param value any
---@param max number
---@return number?
local function sanitiseIndex(value, max)
	if type(value) ~= 'number' then return end
	if value ~= math.floor(value) then return end
	if value < 0 or value > max then return end

	return value
end

---Slots this character has already had synced.
---@param inv OxInventory
---@return table<string, true>
local function syncedSlots(inv)
	local flag = server.getPlayerFlag(inv, SYNC_FLAG)

	if type(flag) == 'table' then return flag end

	-- Anything non-table but truthy is read as "all of them". Nothing writes
	-- that today; it is here so a coarser value can never be mistaken for
	-- "nothing has been synced" and re-run the whole thing.
	if flag then
		local all = {}

		for i = 1, #Clothing.alwaysWorn do
			all[Clothing.alwaysWorn[i]] = true
		end

		return all
	end

	return {}
end

---Which always-worn slots this character still needs synced.
---
---Recomputed from server state on every call - the flag plus the records that
---actually exist - so it is the single answer to "is this needed", and the
---client cannot widen it.
---@param inv OxInventory
---@return string[]? keys nil when nothing is pending
local function pendingSyncSlots(inv)
	local done = syncedSlots(inv)
	local records = loadRecords(inv)
	local pending

	for i = 1, #Clothing.alwaysWorn do
		local key = Clothing.alwaysWorn[i]

		-- Already synced once, or already wearing a real item here. Either way
		-- this slot is not ours to touch.
		if not done[key] and not records[key] then
			pending = pending or {}
			pending[#pending + 1] = key
		end
	end

	return pending
end

---Mint equipped records for what the ped is already wearing.
---
---Deliberately NOT routed through equip(): equip's job is to move an existing
---item out of the inventory and onto the ped, and there is no item here to
---move. This is the opposite direction - clothing that was never an item
---becoming one - so it shares equip's record shape and persistence and none of
---its Inventory.RemoveItem/AddItem trade.
---@param inv OxInventory
---@param payload table<string, { drawable: number, texture: number }> as reported by the client
---@return table<string, table>? records the client applies its read-model from
local function syncStarter(inv, payload)
	if type(payload) ~= 'table' then return end

	local pending = pendingSyncSlots(inv)

	if not pending then return end

	if not Items(SYNC_ITEM) then
		return warn(('item "%s" does not exist, so worn clothing cannot be synced for inventory-%s')
			:format(SYNC_ITEM, inv.id))
	end

	-- Validate everything BEFORE claiming the flag. A payload with nothing
	-- usable in it must leave the character unsynced-and-unflagged so the next
	-- login can try again, rather than burning their one attempt.
	local usable

	for i = 1, #pending do
		local key = pending[i]
		local reported = payload[key]
		local drawable = type(reported) == 'table' and sanitiseIndex(reported.drawable, MAX_DRAWABLE) or nil
		local texture = type(reported) == 'table' and sanitiseIndex(reported.texture, MAX_TEXTURE) or nil

		if drawable and texture then
			usable = usable or {}
			usable[#usable + 1] = { key = key, drawable = drawable, texture = texture }
		else
			warn(('inventory-%s reported no usable %s variation, so that slot was not synced'):format(inv.id, key))
		end
	end

	if not usable then return end

	-- Claimed before anything is written, for the same fail-safe reason the old
	-- grant claimed first: if this half-completes, the character is left as they
	-- were (clothes with no item behind them) instead of picking up another
	-- record on every login. Only the slots actually being minted are marked.
	local done = syncedSlots(inv)

	for i = 1, #usable do
		done[usable[i].key] = true
	end

	if not server.setPlayerFlag(inv, SYNC_FLAG, done) then
		return warn(('cannot record a clothing sync for inventory-%s, so none was made'):format(inv.id))
	end

	local records = loadRecords(inv)
	local synced = {}

	for i = 1, #usable do
		local entry = usable[i]
		local slotDef = Clothing.byKey[entry.key]
		local label = SYNC_LABELS[entry.key] or slotDef.key

		local record = {
			item = SYNC_ITEM,
			label = label,
			kind = 'component',
			id = slotDef.id,
			drawable = entry.drawable,
			texture = entry.texture,
			-- The whole point of using the generic item: these numbers ARE the
			-- garment. getVariation reads them straight back if the player ever
			-- takes this off and puts it on again.
			metadata = {
				component = slotDef.id,
				drawable = entry.drawable,
				texture = entry.texture,
				label = label,
				description = 'Part of the outfit this character was created in.',
			},
			-- No `revert` on purpose - see the note at the top of this section.
			-- revertSlot falls back to the slot's bare drawable.
		}

		records[entry.key] = record
		synced[entry.key] = record
	end

	saveRecords(inv, records)

	return synced
end

---Does this character still need its created-in clothes synced?
---@return string[]? the always-worn slot keys still missing a record
lib.callback.register('ox_inventory:clothing:needsStarterSync', function(source)
	local inv = Inventory(source) --[[@as OxInventory]]

	if not inv?.player then return end

	return pendingSyncSlots(inv)
end)

---Report what the ped is actually wearing, and get equipped records for it.
---
---The client is the only thing that can read a ped, so the drawable/texture
---pairs have to come from there. Everything else about the resulting records -
---which slots, which item, which label - is decided server-side, and the values
---themselves are range-checked above.
---@param payload table<string, { drawable: number, texture: number }>
---@return table<string, table>? records
lib.callback.register('ox_inventory:clothing:syncStarterClothing', function(source, payload)
	return guarded(source, syncStarter, payload)
end)
