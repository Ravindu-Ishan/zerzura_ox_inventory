if not lib then return end

--[[
	Feeds the NUI "Appearance" card with what the ped is ACTUALLY wearing, and -
	where we put it there ourselves - which inventory item put it there.

	Two sources, deliberately:

	1. Ground truth about the ped, via illenium-appearance's getPedAppearance
	   export (game/util.lua -> getPedComponents/getPedProps, i.e.
	   GetPedDrawableVariation/GetPedTextureVariation/GetPedPropIndex over
	   constants.PED_COMPONENTS_IDS = {0..11} and PED_PROPS_IDS = {0,1,2,6,7}).
	   This is what makes the worn/not-worn state honest for anyone dressed by
	   character creation, an admin command, qbx_radialmenu's clothing toggle or
	   any other script.

	2. The equipped-item read-model from modules/clothing/client.lua, which
	   mirrors the server's records. This is what supplies a real item label, and
	   marks the tile as unequippable.

	The two can disagree, and the payload says so rather than papering over it: a
	slot is `filled` if the PED says something is worn, and only carries
	`item`/`label`/`unequippable` if we also hold a server-side record whose
	drawable/texture still match the ped. If another script has since changed
	that component the record is stale, so the card falls back to "Worn" instead
	of naming a garment the player is demonstrably not wearing.
]]

local Clothing = require 'modules.clothing.shared'
local ClothingClient = require 'modules.clothing.client'

local Appearance = {}

local APPEARANCE_RESOURCE = 'illenium-appearance'

---The canonical six-slot mapping now lives in modules/clothing/shared.lua, so
---the client, the server and this card cannot drift apart. See that file for
---why only head/mask/armour have a trustworthy "nothing worn" signal.
local SLOTS = Clothing.slots

--[[
	Which named clothing item belongs to which tile, resolved ONCE here and sent
	to the NUI with every payload.

	The card needs this to decide whether a dragged inventory item may be
	dropped on a given tile. That question is already answered authoritatively
	by Clothing.getVariation, and this is that same function's answer - not a
	second implementation of it in TypeScript. The NUI only ever uses it to
	decide what to highlight and what to refuse locally; equipping still goes
	through the normal use -> ox_inventory:useItem -> clothing:equip path, where
	getVariation is consulted again on both the client and the server.

	The stock generic `clothing` item is absent because it CANNOT be here: its
	slot comes from per-instance metadata, not its name, so there is nothing to
	put in a name-keyed map.

	That is a real limit of this table rather than a limit of the feature, and
	the NUI is where the two are reconciled - resolveClothingSlot
	(web/src/helpers/itemIcon.ts) reads the dragged item's own metadata first and
	consults this map second, the same precedence Clothing.getVariation uses
	here. It matters more than it looks: the always-worn slots on every real
	character are backed by the generic item (see the first-load sync in
	modules/clothing/server.lua), so a drop target built on this map alone
	refuses every garment a normal player actually owns while still accepting the
	admin-give named ones.
]]
local CATALOG = {}

for name in pairs(Clothing.catalog) do
	local variation = Clothing.getVariation(name)

	if variation then
		CATALOG[name] = variation.key
	end
end

--[[
	Diagnostics for the CATALOG, deliberately left in.

	This table is the one part of the Appearance payload that has no
	browser-testable equivalent: web/src/App.tsx's debugData hardcodes a catalog
	in TypeScript, so a dev-server test proves the CARD can read one and proves
	nothing whatsoever about what this file builds and serialises. Drag-to-equip
	has already been reported broken in game after passing exactly that kind of
	test, so the payload now says what it contains out loud.

	Both a count and the encoded form are printed. The encoding is the
	interesting half: an empty Lua table serialises as `[]`, not `{}`, and an
	array-shaped catalog would make every drag invalid while looking fine in a
	`print` of the table itself.
]]
local function describeCatalog()
	local count = 0

	for _ in pairs(CATALOG) do count = count + 1 end

	local ok, encoded = pcall(json.encode, CATALOG)

	return count, ok and encoded or ('<not encodable: %s>'):format(encoded)
end

do
	local count, encoded = describeCatalog()
	local expected = 0

	for _ in pairs(Clothing.catalog) do expected = expected + 1 end

	print(('[clothing] appearance catalog resolved %d of %d named items: %s'):format(count, expected, encoded))

	if count ~= expected then
		warn(('%d named clothing items did not resolve to an Appearance slot and cannot be drag-equipped')
			:format(expected - count))
	end
end

---Whether the NUI has been told about the catalog yet, so the first payload can
---be logged in full without every later refresh repeating it.
local loggedPayload = false

--[[
	What the NUI says it actually received.

	The NUI's own console is not reliably visible from the client console, and
	"the Lua sent it" is not the same claim as "the card can use it" - the
	payload crosses a JSON boundary and a redux reducer on the way. So the card
	reports back once, and that report is printed here, in the F8 console,
	next to what this file thinks it sent.

	Data only: nothing here decides anything, it just prints.
]]
RegisterNUICallback('clothingDebug', function(data, cb)
	cb(1)

	if type(data) ~= 'table' then return end

	print(('[clothing] NUI reports: available=%s slots=%s catalogEntries=%s catalogIsArray=%s keys=%s'):format(
		tostring(data.available), tostring(data.slots), tostring(data.catalogEntries),
		tostring(data.catalogIsArray), type(data.catalogKeys) == 'table' and table.concat(data.catalogKeys, ',') or 'none'))

	if data.catalogEntries == 0 then
		warn('the inventory UI received an EMPTY clothing catalog - named garments cannot be drag-equipped in this state')
	end
end)

local warned = false

---@return table? appearance illenium-appearance's getPedAppearance result
local function getPedAppearance()
	if GetResourceState(APPEARANCE_RESOURCE) ~= 'started' then
		if not warned then
			warned = true
			warn(('%s is not started - the inventory Appearance card will show as unavailable'):format(APPEARANCE_RESOURCE))
		end

		return
	end

	local ok, result = pcall(function()
		return exports[APPEARANCE_RESOURCE]:getPedAppearance(cache.ped)
	end)

	if not ok then
		if not warned then
			warned = true
			warn(('failed to read ped appearance from %s: %s'):format(APPEARANCE_RESOURCE, result))
		end

		return
	end

	return type(result) == 'table' and result or nil
end

---Turn the export's flat arrays into id -> { drawable, texture } lookups.
---@param entries table[]?
---@param idKey string
local function indexById(entries, idKey)
	local lookup = {}

	if type(entries) ~= 'table' then return lookup end

	for i = 1, #entries do
		local entry = entries[i]

		if type(entry) == 'table' and entry[idKey] then
			lookup[entry[idKey]] = entry
		end
	end

	return lookup
end

---Read the ped and push the six Appearance slots to the NUI.
---Safe to call at any time; it no-ops until the UI exists.
function Appearance.refresh()
	if not client.uiLoaded then return end

	local appearance = getPedAppearance()

	if not appearance then
		-- Explicitly unavailable, rather than "everything is empty" - the card
		-- renders an unknown state instead of claiming the ped is undressed.
		return SendNUIMessage({
			action = 'setAppearance',
			data = { available = false, slots = {} }
		})
	end

	local components = indexById(appearance.components, 'component_id')
	local props = indexById(appearance.props, 'prop_id')
	local equipped = ClothingClient.getEquipped()
	local slots = table.create(#SLOTS, 0)

	for i = 1, #SLOTS do
		local slot = SLOTS[i]
		local entry = (slot.kind == 'prop' and props or components)[slot.id]
		local drawable = entry and entry.drawable or nil
		local texture = entry and entry.texture or nil

		local filled

		if not entry then
			-- The export did not report this id at all (shouldn't happen with
			-- the ids above, but a different ped model set could change that).
			filled = false
		elseif slot.canBeEmpty then
			filled = drawable ~= slot.emptyValue
		else
			-- No reliable "nothing worn" value exists for this slot - see
			-- modules/clothing/shared.lua.
			filled = true
		end

		local record = equipped[slot.key]

		-- Only name the item if the ped still agrees with the record. A stale
		-- record (another script changed the component behind our back) shows
		-- as a plain worn slot rather than a confident lie.
		local matches = record ~= nil
			and drawable == record.drawable
			and texture == record.texture

		slots[i] = {
			key = slot.key,
			kind = slot.kind,
			id = slot.id,
			drawable = drawable,
			texture = texture,
			filled = filled,
			canBeEmpty = slot.canBeEmpty,
			item = matches and record.item or nil,
			label = matches and record.label or nil,
			-- Clickable only when there is a real item to give back.
			unequippable = matches or nil,
		}
	end

	SendNUIMessage({
		action = 'setAppearance',
		data = { available = true, slots = slots, catalog = CATALOG }
	})

	-- Once per session: the exact catalog that went over the wire, so the F8
	-- console can be compared against what the card reports receiving
	-- (RegisterNUICallback('clothingDebug') above).
	if not loggedPayload then
		loggedPayload = true

		local count, encoded = describeCatalog()

		print(('[clothing] sent setAppearance with %d slots and a %d-entry catalog: %s'):format(#slots, count, encoded))
	end
end

return Appearance
