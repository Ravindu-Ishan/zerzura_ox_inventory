if not lib then return end

--[[
	Client half of item-backed clothing.

	This file never decides that an item was worn or taken off - it asks the
	server and applies whatever the server confirms. What it is trusted with is
	everything that requires a ped, which the server does not have:

	  * validating a drawable before the server is asked to take the item;
	  * remembering what the ped looked like before a torso/legs/feet garment
	    went on;
	  * reading the ped for the first-load sync of the clothes the character was
	    created in (see the section near the bottom of this file);
	  * pushing pixels afterwards, and mirroring the result into
	    illenium-appearance's stored record so the character creator and the
	    character-select preview see it too.

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

---@param variation table
---@return boolean valid
local function isVariationValid(variation)
	if variation.kind == 'prop' then
		return SetPedPreloadPropData(cache.ped, variation.id, variation.drawable, variation.texture)
	end

	return IsPedComponentVariationValid(cache.ped, variation.id, variation.drawable, variation.texture)
end

--[[
	The components that decide what a BARE component 11 actually looks like.

	Component 11 (tops) is not the whole upper body: 3 is the torso/arms mesh and
	8 is the undershirt. Drawable 252 on component 11 is not a standalone "bare
	chest" - it is one third of a set, and it is only meant to be worn with the
	other two. Verified at the original source, not recalled:
	illenium-appearance's strip-the-ped routine removeClothes
	(game/customization.lua:509-523) writes every pair in
	constants.DATA_CLOTHES.body.components.male (game/constants.lua:289-296) in
	one go - {11, 252}, {3, 15}, {8, 15} - and z-player-charcreation's
	UNDRESS_DRAWABLES (main server repo, client/main.lua) carries the same three
	numbers for male.

	This block used to log those two components and deliberately not write them,
	because it was still a hypothesis. The owner's F8 capture settled it:

	    [clothing] unequip torso: bare -> component 11 drawable 252 texture 0 | valid=true | ...
	    [clothing] unequip torso: component 11 is now 252/0
	    [clothing] unequip torso: neighbour component 3 is drawable 0 texture 0 (of 214 variations)
	    [clothing] unequip torso: neighbour component 8 is drawable 0 texture 0 (of 213 variations)

	valid=true and the read-back both say the component 11 write landed exactly
	as asked, which rules out the DLC-unavailable theory on that client - and the
	character still looked wrong (a generic tank-top-and-shorts look), because 3
	and 8 were sitting at 0/0 instead of 15/15. 252 against an unrelated 0/0 is
	that broken-looking outfit; it is not a bare chest.

	So the bare fallback now writes all three. ONLY the bare fallback does - see
	applyBareTorsoSet for the paths that are deliberately left alone.

	DATA_CLOTHES's male body set also lists {10, 0} and {5, 0}. Those are decals
	and the bag/parachute slot - neither is upper-body mesh, and clearing a bag
	off a player who is carrying one is not this fix's business. Left alone.

	MALE ONLY, like every other number in this feature. DATA_CLOTHES does carry a
	female set ({11, 15}, {3, 15}, {8, 14}), but `bare` for torso in shared.lua is
	the male 252 to begin with, so a female ped has no coherent torso value to
	pair anything with. Female stays one follow-up rather than a half-done one.
]]
local TORSO_BARE_SET = {
	{ id = 3, drawable = 15 },
	{ id = 8, drawable = 15 },
}

---Log the components around a torso revert, so the F8 console can tell a
---correct bare-chest result apart from a broken ped.
---
---Still printed on every torso revert, including the ones where nothing below
---is written (a stored `revert`, or a revert where every candidate was
---rejected) - those are exactly the cases where "what are 3 and 8 right now" is
---not something this file decided, and so the only way to know is to read them.
---@param id number the component that was just reverted
local function logNeighbours(id)
	if id ~= 11 then return end

	for i = 1, #TORSO_BARE_SET do
		local neighbour = TORSO_BARE_SET[i].id

		print(('[clothing] unequip torso: neighbour component %d is drawable %d texture %d (of %d variations)'):format(
			neighbour,
			GetPedDrawableVariation(cache.ped, neighbour),
			GetPedTextureVariation(cache.ped, neighbour),
			GetNumberOfPedDrawableVariations(cache.ped, neighbour)))
	end
end

---Write the two components that pair with a bare component 11.
---
---Reached on ONE path: a torso revert that actually applied `bare` to component
---11. Traced against the three cases that must not be touched:
---
---  * Module.equip never reaches here. It applies a real item's own
---    drawable/texture to component 11 and does not call revertSlot at all.
---    Nothing anywhere documents what a real jacket expects components 3 and 8
---    to be, and only the BARE value is documented as needing this pairing, so
---    a real garment gets nothing from this function.
---  * A revert that used the stored `revert` reading leaves the loop below with
---    `candidate.source == 'revert'`, which is not 'bare'. That reading is what
---    the ped genuinely looked like just before the garment went on - very
---    possibly whatever character creation set, not this 252/15/15 set at all -
---    so there is no problem there for this to fix, and overwriting 3 and 8
---    would be inventing one.
---  * A revert where every candidate was rejected writes nothing at all,
---    component 11 included. 15/15 without the 252 it pairs with would be a
---    change with no point to it.
---
---The gate is what was APPLIED, not what was stored. A stored `revert` that
---fails validation falls through to `bare`, and at that point the ped really is
---showing 252 and really does need its pair, whatever the record happens to
---hold.
---
---Validated and read back exactly like the component 11 write - these are
---drawables on the same ped from the same table, and are no more guaranteed to
---exist than 252 is. Palette 0 matches the rest of this file (illenium passes 2
---in removeClothes; the palette selects a texture palette and is not what this
---bug was about).
---
---Deliberately NOT mirrored into illenium-appearance's stored row. persistSlot
---patches the one component the equipped record owns, which is 11. Components 3
---and 8 in that row are the character's own creation-time values, and after the
---player puts a jacket back on this file has nothing to say about what they
---should be - so writing 15/15 there would make a temporary bare state
---permanent in the database. The consequence is that this fix is a live-ped fix
---for the session: on relog illenium restores the character's own 3/8 again.
---@param key string slot key, for the log lines
local function applyBareTorsoSet(key)
	for i = 1, #TORSO_BARE_SET do
		local part = TORSO_BARE_SET[i]
		local worn = GetPedDrawableVariation(cache.ped, part.id)
		local wornTexture = GetPedTextureVariation(cache.ped, part.id)
		local variations = GetNumberOfPedDrawableVariations(cache.ped, part.id)

		local valid = isVariationValid({
			kind = 'component',
			id = part.id,
			drawable = part.drawable,
			texture = 0,
		})

		print(('[clothing] unequip %s: bare set -> component %d drawable %d texture 0 | valid=%s | currently %d/%d | %d variations exist')
			:format(key, part.id, part.drawable, tostring(valid), worn, wornTexture, variations))

		if valid then
			SetPedComponentVariation(cache.ped, part.id, part.drawable, 0, 0)

			local got = GetPedDrawableVariation(cache.ped, part.id)
			local gotTexture = GetPedTextureVariation(cache.ped, part.id)

			if got ~= part.drawable or gotTexture ~= 0 then
				warn(('unequip %s: asked component %d for drawable %d texture 0 but the ped reports %d/%d - the value did not take')
					:format(key, part.id, part.drawable, got, gotTexture))
			else
				print(('[clothing] unequip %s: component %d is now %d/%d'):format(key, part.id, got, gotTexture))
			end
		else
			warn(('unequip %s: bare set drawable %d texture 0 is not valid on this ped (component %d has %d variations), so it was not applied - component 11 is bare without the pair it expects')
				:format(key, part.drawable, part.id, variations))
		end
	end
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
---
---A record synced from the clothes the character was created in has no `revert`
---ON PURPOSE - it is the baseline, so there is no "before" to go back to - and
---it lands in that last case: taking off the shirt you were created in leaves
---you bare-chested, which is the only honest answer.
---
---NOTHING IS APPLIED UNVALIDATED HERE. Module.equip has always checked
---isVariationValid before asking the server for anything, precisely so a value
---this ped cannot wear fails with the item still in the bag instead of being
---painted on. The revert path had no equivalent and applied `revert` / `bare` /
---`emptyValue` straight to SetPedComponentVariation. The reason to close that
---was `bare` for torso being drawable 252, which z-player-charcreation's own
---UNDRESS_DRAWABLES table says "only exists if the DLC that ships it is
---streaming", having traced a "character has no body" bug to it.
---
---THAT IS NOT WHAT THIS SERVER'S TORSO BUG TURNED OUT TO BE. The owner's F8
---capture shows 252 validating and reading back cleanly on their client - see
---the TORSO_BARE_SET block above for the log and for what was actually wrong.
---The validation stays anyway: it costs one native call, the DLC caveat is still
---true of some other client, and the same check now guards the two companion
---writes. So each fallback is validated, they are tried in order of how much we
---trust them, and if none of them is valid the ped is LEFT ALONE: still wearing
---a garment that is now back in the bag is a cosmetic lie that the next
---equip/relog corrects, whereas a rejected drawable is the broken ped itself.
---
---The prints are deliberate and are meant to stay. This whole path is
---in-game-only (there is no ped in a browser and no IsPedComponentVariationValid
---outside the client), it has already produced one report that read as two
---different bugs, and it is what turned the second of those from a guess into a
---known cause. The same read-back-and-print pattern is what pinned down the
---undress bug in z-player-charcreation. Whether 15/15 is what the ped should
---look like is the next thing these lines are there to answer.
---@param data table instruction returned by the unequip callback
local function revertSlot(data)
	if data.kind == 'prop' then
		print(('[clothing] unequip %s: clearing prop %d'):format(data.key, data.id))

		return ClearPedProp(cache.ped, data.id)
	end

	-- Ordered by trust, which is the same order the old if/elseif had - the only
	-- difference is that a rejected candidate now falls through to the next one
	-- instead of ending the attempt.
	local candidates = {}

	if data.revert then
		candidates[#candidates + 1] = {
			source = 'revert',
			drawable = data.revert.drawable,
			texture = data.revert.texture,
		}
	end

	if data.canBeEmpty then
		candidates[#candidates + 1] = { source = 'emptyValue', drawable = data.emptyValue, texture = 0 }
	else
		candidates[#candidates + 1] = { source = 'bare', drawable = data.bare, texture = 0 }
	end

	local worn = GetPedDrawableVariation(cache.ped, data.id)
	local wornTexture = GetPedTextureVariation(cache.ped, data.id)
	local variations = GetNumberOfPedDrawableVariations(cache.ped, data.id)

	-- Records written by earlier versions of this feature (and the in-memory
	-- fallback for frameworks that cannot persist metadata) are not re-sanitised
	-- on load, so a stored `revert` is not guaranteed to hold two integers. A
	-- non-integer reaching the `%d` in the log below would throw before it ever
	-- reached the ped, which is a silly way to break an unequip.
	---@param value any
	---@return number?
	local function index(value)
		if type(value) ~= 'number' then return end
		if value ~= math.floor(value) then return end

		return value
	end

	for i = 1, #candidates do
		local candidate = candidates[i]
		local drawable = index(candidate.drawable)
		local texture = index(candidate.texture) or 0

		if drawable then
			local valid = isVariationValid({
				kind = 'component',
				id = data.id,
				drawable = drawable,
				texture = texture,
			})

			print(('[clothing] unequip %s: %s -> component %d drawable %d texture %d | valid=%s | currently %d/%d | %d variations exist')
				:format(data.key, candidate.source, data.id, drawable, texture, tostring(valid), worn, wornTexture,
					variations))

			if valid then
				SetPedComponentVariation(cache.ped, data.id, drawable, texture, 0)

				-- Read back instead of trusting the write, the same way
				-- z-player-charcreation's undress routine does: an out-of-range
				-- drawable is rejected silently, so "I called the native" is not
				-- evidence that anything changed.
				local got = GetPedDrawableVariation(cache.ped, data.id)
				local gotTexture = GetPedTextureVariation(cache.ped, data.id)

				if got ~= drawable or gotTexture ~= texture then
					warn(('unequip %s: asked component %d for drawable %d texture %d but the ped reports %d/%d - the value did not take')
						:format(data.key, data.id, drawable, texture, got, gotTexture))
				else
					print(('[clothing] unequip %s: component %d is now %d/%d'):format(data.key, data.id, got, gotTexture))
				end

				-- A bare component 11 is only a third of the change. Gated on
				-- the candidate that was actually APPLIED, so a stored `revert`
				-- reading, every other slot and every all-candidates-rejected
				-- revert fall straight past it - see applyBareTorsoSet.
				if candidate.source == 'bare' and data.id == 11 then
					applyBareTorsoSet(data.key)
				end

				return logNeighbours(data.id)
			end

			warn(('unequip %s: %s drawable %d texture %d is not valid on this ped (component %d has %d variations), so it was not applied')
				:format(data.key, candidate.source, drawable, texture, data.id, variations))
		end
	end

	warn(('unequip %s: no valid value to revert component %d to, so the ped was left as it is - it will still show the garment until something else changes that component')
		:format(data.key, data.id))

	logNeighbours(data.id)
end

-----------------------------------------------------------------------------------------------
-- Keeping illenium-appearance's SAVED record honest
-----------------------------------------------------------------------------------------------

---The appearance illenium-appearance has STORED for this character, which is
---also the appearance it applies on spawn.
---@return table? saved
local function fetchSavedAppearance()
	if GetResourceState(APPEARANCE_RESOURCE) ~= 'started' then return end

	local ok, saved = pcall(lib.callback.await, 'illenium-appearance:server:getAppearance', false)

	-- Nil means there is no row for this character yet - illenium's
	-- server/framework/qb/main.lua Framework.GetAppearance returns nothing when
	-- the lookup misses. An empty component list is treated the same way rather
	-- than as "matches anything", which is what pedMatches would otherwise
	-- conclude from it.
	if not ok or type(saved) ~= 'table' or type(saved.components) ~= 'table' or saved.components[1] == nil then return end

	return saved
end

--[[
	Equipping used to change the ped and nothing else, which left two different
	answers to "what is this character wearing" in the database.

	The bug that exposed it: put a jacket on in game, then go back to the
	character creator (or look at the character-select screen) and the jacket is
	not there - but relog and it is on again. Nothing was corrupt; there are
	simply two stores, and only one of them was being written.

	  * OUR store - equipped records in player metadata. Re-applied on every
	    spawn by doRestore below, which is why the in-world ped looks right.
	  * illenium-appearance's store - the playerskins row. This is the one that
	    every OTHER reader of the character's appearance uses, and none of them
	    involve the live ped:
	      - z-player-charcreation's previewSavedCharacter (client/main.lua) ->
	        qbx_core:server:getPreviewPedData -> storage.fetchPlayerSkin, then
	        setPedAppearance on the preview ped;
	      - qbx_core's own character.lua preview, the same way;
	      - illenium-appearance's InitAppearance on spawn.
	    Never written by us, so all of them showed pre-equip clothes.

	So after every equip/unequip the changed slot is mirrored into that row.

	It is a SURGICAL PATCH, not a snapshot. The obvious implementation - call
	getPedAppearance and save the result, which is what illenium's own clothing
	shop does - is wrong here, because getPedAppearance reads tattoos from
	illenium's PED_TATTOOS cache (game/util.lua) and head blend / face features
	/ overlays from the live ped. Any of those being unset or not-yet-applied at
	the moment we happened to save would be written over the character's real
	data, permanently. Trading a stale preview for a wiped face is not a fix.
	Instead the stored record is fetched, the one component or prop entry we
	actually changed is rewritten, and everything else is passed back through
	byte for byte.

	The values come from reading the ped back AFTER the change is applied, so
	what gets stored is what is actually on the character - not what we intended
	to put there.
]]

---@param kind 'prop' | 'component'
---@param id number
local function persistSlot(kind, id)
	local saved = fetchSavedAppearance()

	-- No stored row yet (a character mid-creation, whose own save has not landed
	-- yet). There is nothing to patch, and inventing a whole appearance here is
	-- exactly the snapshot behaviour the comment above rejects. The creator
	-- saves the finished character a moment later anyway.
	if not saved then return end

	local entries, idKey, drawable, texture

	if kind == 'prop' then
		entries, idKey = saved.props, 'prop_id'
		drawable, texture = GetPedPropIndex(cache.ped, id), GetPedPropTextureIndex(cache.ped, id)
	else
		entries, idKey = saved.components, 'component_id'
		drawable, texture = GetPedDrawableVariation(cache.ped, id), GetPedTextureVariation(cache.ped, id)
	end

	if type(entries) ~= 'table' then return end

	local patched = false

	for i = 1, #entries do
		local entry = entries[i]

		if type(entry) == 'table' and entry[idKey] == id then
			entry.drawable, entry.texture = drawable, texture
			patched = true
			break
		end
	end

	-- The stored row genuinely did not list this id (an older save, or a
	-- different id set). Add it rather than silently dropping the change; the
	-- shape is identical to what getPedComponents/getPedProps produce.
	if not patched then
		entries[#entries + 1] = { [idKey] = id, drawable = drawable, texture = texture }
	end

	TriggerServerEvent('illenium-appearance:server:saveAppearance', saved)
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
	-- does not exist on this ped model (every value in the named catalog is
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

	-- The ped now shows the garment; make the stored appearance agree, so the
	-- character creator and the select screen show it too.
	persistSlot(result.record.kind, result.record.id)
end

---Take off whatever is worn in the given slot and put the item back in the bag.
---@param key string one of Clothing.byKey
---@param targetSlot number? preferred inventory slot for the returned item
function Module.unequip(key, targetSlot)
	if not Clothing.byKey[key] or not Equipped[key] then return end

	-- Only the key and the destination preference ever cross to the server, and
	-- the server range-checks the latter and treats it as a hint. There is no
	-- item name, count or metadata in this payload for the same reason there
	-- never was: nothing the client says may decide what gets created.
	local result = lib.callback.await('ox_inventory:clothing:unequip', false, {
		key = key,
		slot = type(targetSlot) == 'number' and targetSlot or nil,
	})

	if not result then return end

	Equipped[result.key] = nil
	revertSlot(result)
	refreshAppearance()

	-- Same as equip: taking something off is a change to the character's
	-- appearance, so the stored record has to hear about it as well.
	persistSlot(result.kind, result.id)
end

-- Fired by the Appearance card, either from its right-click "Unequip" action or
-- from dragging the tile onto an inventory square (which supplies `slot`, the
-- square that was dropped on). Both are the same call - the drag is an input
-- method, not a second code path. cb() first so CEF is not left waiting on the
-- server round trip.
RegisterNUICallback('unequipClothing', function(data, cb)
	cb(1)

	local key = type(data) == 'table' and data.key or data

	if type(key) ~= 'string' then return end

	Module.unequip(key, type(data) == 'table' and tonumber(data.slot) or nil)
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

---How long the first-load clothing sync will wait for a saved appearance to
---exist AND be observed on the ped. Much longer than RESTORE_TIMEOUT above
---because on a brand new character it is waiting for the character creator's
---own save to land, not just for a restore of something already in the
---database - see waitForSettledAppearance.
local SYNC_TIMEOUT = 60000
local SYNC_SAVED_INTERVAL = 1000
local SYNC_PED_INTERVAL = 200

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

---Component ids our own records occupy, which must be excluded from any
---comparison against the saved appearance - we put those there on purpose.
---@param records table<string, table>
---@return table<number, true>
local function occupiedComponents(records)
	local skip = {}

	for _, record in pairs(records) do
		if record.kind == 'component' then
			skip[record.id] = true
		end
	end

	return skip
end

---Block until illenium-appearance has finished putting the base appearance back
---on the ped (or until we give up).
---@param records table<string, table>
---@return boolean settled
local function waitForBaseAppearance(records)
	local saved = fetchSavedAppearance()

	-- No saved appearance means a brand new character still in creation; there
	-- is nothing for it to overwrite us with.
	if not saved then return true end

	local skip = occupiedComponents(records)
	local deadline = GetGameTimer() + RESTORE_TIMEOUT

	repeat
		if pedMatches(saved, skip) then return true end

		Wait(200)
	until GetGameTimer() > deadline

	warn(('timed out waiting for %s to restore the base appearance; equipped clothing may be overwritten')
		:format(APPEARANCE_RESOURCE))

	return false
end

-----------------------------------------------------------------------------------------------
-- First-load sync of the clothes the character was created in
-----------------------------------------------------------------------------------------------

--[[
	The server needs to know the drawable/texture actually on the ped for the
	three always-worn slots, so it can mint equipped records for exactly those -
	see the long note in modules/clothing/server.lua for what this replaces and
	why. This half's whole job is to not read the ped too early.

	The relog wait above is NOT sufficient for a character's first load, and
	this server's character creation is the reason. Traced through
	z-player-charcreation/client/main.lua's submitNewCharacter:

	  1. `qbx_core:server:createCharacter` is awaited. That runs qbx_core's
	     CreatePlayer, which sets the `loadInventory` statebag -> ox_inventory's
	     setupPlayer -> ox_inventory:setPlayerInventory -> PlayerData.loaded ->
	     THIS code starts running. The creation UI is still open at this point.
	  2. destroyPreviewCam() runs, and with it setPreviewUndressed(false) - the
	     only thing that puts the ped's real clothes back on. Until this line,
	     the ped may still be wearing the creator's bare-skin UNDRESS_DRAWABLES
	     (it holds the ped undressed for the whole Tattoos tab).
	  3. getPedAppearance() is read and `illenium-appearance:server:saveAppearance`
	     is FIRED AND FORGOTTEN - so the stored row does not exist yet.
	  4. closeUiAndSpawn spawns the player and fires QBCore:Client:OnPlayerLoaded,
	     which is what makes illenium-appearance apply the saved appearance.

	So on a first load we start at step 1: there is no saved appearance to
	compare against (waitForBaseAppearance returns immediately, correctly, for
	its own purpose) and the ped may be standing there undressed. Reading it
	then would mint records for bare skin - the same bug z-player-charcreation
	already has a comment about having fixed once.

	Hence a stricter wait for this one job: proceed only when a stored
	appearance EXISTS and the ped demonstrably MATCHES it. The undress window
	cannot satisfy that (the stored appearance has real clothes in it), a
	pre-save window cannot satisfy it (there is nothing stored yet), and the
	model is part of the comparison so a gender swap or a fresh ped entity
	cannot either. If it never becomes true we sync nothing and claim no flag,
	so the next login simply tries again - a first session with an item-less
	Appearance card, rather than a permanent record of the wrong clothes.
]]

---Wait until there is a stored appearance AND the ped agrees with it.
---@param records table<string, table> our own records, excluded from the match
---@return table? saved
local function waitForSettledAppearance(records)
	if GetResourceState(APPEARANCE_RESOURCE) ~= 'started' then return end

	local skip = occupiedComponents(records)
	local deadline = GetGameTimer() + SYNC_TIMEOUT
	local saved

	repeat
		-- Only polled while still missing: this is a database read on the
		-- server, so it is not something to hammer once we have an answer.
		if not saved then saved = fetchSavedAppearance() end

		if saved and pedMatches(saved, skip) then return saved end

		Wait(saved and SYNC_PED_INTERVAL or SYNC_SAVED_INTERVAL)
	until GetGameTimer() > deadline

	warn('gave up waiting for a settled character appearance; worn clothing was not synced to the inventory')
end

---Report what the ped is wearing in the given slots and adopt the records the
---server mints for them.
---@param keys string[] always-worn slot keys the server says are unsynced
local function syncCreatedClothing(keys)
	if not waitForSettledAppearance(Equipped) then return end

	local payload = {}

	for i = 1, #keys do
		local slot = Clothing.byKey[keys[i]]

		if slot and slot.kind == 'component' then
			payload[slot.key] = {
				drawable = GetPedDrawableVariation(cache.ped, slot.id),
				texture = GetPedTextureVariation(cache.ped, slot.id),
			}
		end
	end

	if not next(payload) then return end

	local ok, records = pcall(lib.callback.await, 'ox_inventory:clothing:syncStarterClothing', false, payload)

	if not ok or type(records) ~= 'table' then return end

	for key, record in pairs(records) do
		if Clothing.byKey[key] and type(record) == 'table' then
			Equipped[key] = record
		end
	end

	-- Deliberately no persistSlot here. A synced record describes clothing the
	-- ped is ALREADY wearing, and the values were taken from a ped we had just
	-- confirmed matches the stored appearance - so there is nothing to write
	-- back, and writing anyway would only add a database round trip to every
	-- character's first load.
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

	-- Asked every load, answered entirely from server state (the one-time flag
	-- plus which records exist). nil for every load after the first.
	local syncOk, pending = pcall(lib.callback.await, 'ox_inventory:clothing:needsStarterSync', false)

	pending = syncOk and type(pending) == 'table' and pending[1] and pending or nil

	if not next(Equipped) and not pending then
		return refreshAppearance()
	end

	if next(Equipped) then
		waitForBaseAppearance(Equipped)

		for _, record in pairs(Equipped) do
			applyRecord(record)
		end

		-- Push what we already know before the sync below, which waits on
		-- something unrelated to these records and can take a few seconds.
		if pending then refreshAppearance() end
	end

	if pending then
		syncCreatedClothing(pending)
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
