if not lib then return end

--[[
	Feeds the NUI "Appearance" card with what the ped is ACTUALLY wearing.

	Why ped state and not item tracking:
	`Item('clothing', ...)` in modules/items/client.lua flips native ped
	variations and forgets. Remembering "which item was last used" there would
	report a naked ped for anyone dressed by character creation, an admin
	command or any other script - i.e. almost everyone. So we read ground truth
	off the ped instead, via illenium-appearance's getPedAppearance export
	(game/util.lua -> getPedComponents/getPedProps), which is just
	GetPedDrawableVariation/GetPedTextureVariation/GetPedPropIndex over
	constants.PED_COMPONENTS_IDS = {0..11} and PED_PROPS_IDS = {0,1,2,6,7}.

	The trade-off, stated plainly: we learn numbers, not items. A drawable of
	`12` on component 11 cannot be mapped back to "Leather Jacket" - nothing on
	the client holds that mapping, and guessing one would make the card lie. So
	the card shows worn/not-worn per slot and the raw numbers in the tooltip,
	and never an item label. See AppearanceCard.tsx for the UI half of this.
]]

local Appearance = {}

local APPEARANCE_RESOURCE = 'illenium-appearance'

---Per-slot definition for the six tiles on the Appearance card.
---
---`canBeEmpty` is the honest part. Only three of these six slots have a
---trustworthy "nothing is worn" signal:
---
---  * head   - PROP 0. GetPedPropIndex returns -1 with no hat/helmet. This is a
---             real, engine-level absence, not a convention.
---  * mask   - COMPONENT 1. Freemode convention is drawable 0 = bare face.
---  * armour - COMPONENT 9. Freemode convention is drawable 0 = no vest overlay.
---             (This is the visual overlay only - it is NOT the numeric armour
---             stat from GetPedArmour, which `Item('armour', ...)` sets.)
---
---The other three genuinely have no "empty" in the game. A freemode ped always
---resolves to *some* torso, legs and feet drawable - drawable 0 there is a
---valid garment (and on some models an underwear/bare-arms variant), not an
---absence. Rather than invent a heuristic that would call a real outfit
---"empty", these are reported as permanently worn and flagged canBeEmpty=false
---so the UI can be honest about it.
local SLOTS = {
	{ key = 'head',   kind = 'prop',      id = 0,  canBeEmpty = true,  emptyValue = -1 },
	{ key = 'mask',   kind = 'component', id = 1,  canBeEmpty = true,  emptyValue = 0 },
	{ key = 'torso',  kind = 'component', id = 11, canBeEmpty = false },
	{ key = 'armour', kind = 'component', id = 9,  canBeEmpty = true,  emptyValue = 0 },
	{ key = 'legs',   kind = 'component', id = 4,  canBeEmpty = false },
	{ key = 'feet',   kind = 'component', id = 6,  canBeEmpty = false },
}

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
			-- No reliable "nothing worn" value exists for this slot - see SLOTS.
			filled = true
		end

		slots[i] = {
			key = slot.key,
			kind = slot.kind,
			id = slot.id,
			drawable = drawable,
			texture = texture,
			filled = filled,
			canBeEmpty = slot.canBeEmpty,
		}
	end

	SendNUIMessage({
		action = 'setAppearance',
		data = { available = true, slots = slots }
	})
end

return Appearance
