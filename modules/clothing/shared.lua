if not lib then return end

--[[
	Shared definitions for item-backed clothing.

	Worn clothing is a PHYSICAL item: using a clothing item removes it from the
	player's inventory (it is now on them, not in their bag) and unequipping puts
	the same item back. The server owns both halves of that trade - see
	modules/clothing/server.lua. This file only holds the data both sides agree
	on, so the client, the server and the Appearance card cannot drift apart.

	The six slots below are the canonical mapping, moved here verbatim from
	modules/appearance/client.lua (which now requires this file) so there is
	exactly one definition of "which slots does the inventory care about".
]]

local Clothing = {}

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
---resolves to *some* torso, legs and feet drawable - drawable 0 there is a valid
---garment, not an absence. So unequipping one of those cannot "clear" the slot;
---it has to put back whatever the ped was wearing immediately BEFORE the item
---went on. That reading is captured at equip time and stored with the equipped
---record (see server.lua), which is the same reason qbx_radialmenu keeps its own
---`LastEquipped` table.
---
---`bare` is only a last-resort fallback for when that remembered value is
---missing (e.g. a record written before this field existed, or a client that
---failed to report one). The values are the confirmed "nothing worn" drawables
---this server already uses for mp_m_freemode_01, read from
---qbx_radialmenu/client/clothing.lua: Extras.Shirt male = 252 (bare torso),
---Extras.Pants male = 61 (bare legs), drawables.Shoes male = 34 (barefoot).
---They are MALE values - see the female note on CATALOG below.
---
---NOT ONE OF THEM IS GUARANTEED TO EXIST ON A GIVEN CLIENT. The same numbers
---appear in z-player-charcreation's UNDRESS_DRAWABLES (main server repo,
---client/main.lua), sourced from illenium-appearance's own
---constants.DATA_CLOTHES, and that table carries a comment written after the
---resource was debugged in game: "male torso2 252 in particular only exists if
---the DLC that ships it is streaming", and separately that one of those bare
---drawables "is DLC-dependent and can silently fail to apply on a different
---client than the one that created the character". That is the documented cause
---of a "character has no body" bug over there.
---
---The numbers are kept - they came from a verified source and they are right on
---a client that has the DLC - but they are no longer applied on faith.
---revertSlot in modules/clothing/client.lua now runs every fallback through
---IsPedComponentVariationValid first (the same check Module.equip has always
---done), falls through to the next candidate if one is rejected, and leaves the
---ped untouched rather than writing a value the engine will not honour. Do not
---"fix" a torso problem by swapping this number for a different guess; the
---validation and the F8 logging in revertSlot are there to say what the ped
---actually accepted.
---
---AND THEY HAVE SAID SO, for torso, on this server's own client: 252 validated
---and read back cleanly there, so the DLC caveat above - while still true of
---some other client - was NOT the cause of the torso-revert bug here. 252 is
---not a whole bare torso on its own; it is one of a set of three that
---DATA_CLOTHES writes together (11 = 252 with 3 = 15 and 8 = 15 for male), and
---writing it against whatever 3 and 8 happened to be is what produced the
---wrong-looking character. That pairing lives in client.lua's TORSO_BARE_SET
---rather than here, because it is a property of this one fallback value and not
---of the slot: only the bare torso needs it, and only when it is the value
---actually applied.
Clothing.slots = {
	{ key = 'head',   kind = 'prop',      id = 0,  canBeEmpty = true,  emptyValue = -1 },
	{ key = 'mask',   kind = 'component', id = 1,  canBeEmpty = true,  emptyValue = 0 },
	{ key = 'torso',  kind = 'component', id = 11, canBeEmpty = false, bare = 252 },
	{ key = 'armour', kind = 'component', id = 9,  canBeEmpty = true,  emptyValue = 0 },
	{ key = 'legs',   kind = 'component', id = 4,  canBeEmpty = false, bare = 61 },
	{ key = 'feet',   kind = 'component', id = 6,  canBeEmpty = false, bare = 34 },
}

Clothing.byKey = {}

--[[
	The always-worn slots, DERIVED from the table above rather than listed again.

	These are exactly the slots with `canBeEmpty = false` and `kind =
	'component'`: torso (11), legs (4) and feet (6). A freemode ped always has
	SOME drawable there, and straight out of character creation that drawable is
	backed by no item at all - there is nothing to hand back if the player takes
	it off, and nothing in the bag to interact with the system.

	That is what the first-load sync in modules/clothing/server.lua fixes, by
	reading what the ped is ACTUALLY wearing and minting an equipped record for
	those exact numbers. It does not hand out garments of its own choosing.

	head / mask / armour are absent because they have a genuine "nothing worn"
	state, so a new character starting with an empty head is correct rather than
	broken.
]]
Clothing.alwaysWorn = {}

local byComponent = {}
local byProp = {}

for i = 1, #Clothing.slots do
	local slot = Clothing.slots[i]

	Clothing.byKey[slot.key] = slot
	;(slot.kind == 'prop' and byProp or byComponent)[slot.id] = slot

	if slot.kind == 'component' and not slot.canBeEmpty then
		Clothing.alwaysWorn[#Clothing.alwaysWorn + 1] = slot.key
	end
end

--[[
	Named clothing catalog - MALE ONLY, deliberately.

	Every drawable/texture pair below is a value this server (or ox_inventory
	itself) already uses on mp_m_freemode_01, so none of them are guesses:

	  clothing_beanie    prop 0 / 2 / 1    ox_inventory's own comment in
	                                       modules/items/client.lua: "grey beanie"
	  clothing_balaclava comp 1 / 52 / 0   illenium-appearance Config.Outfits,
	                                       police "SWAT" Male -> mask
	  clothing_bomber    comp 11 / 29 / 0  qbx_radialmenu variations.jackets.male,
	                                       confirmed open/closed pair 29 <-> 30
	  clothing_vest      comp 9 / 15 / 2   illenium-appearance Config.Outfits,
	                                       police "SWAT" Male -> vest
	  clothing_jeans     comp 4 / 4 / 1    ox_inventory's own comment in
	                                       modules/items/client.lua: "jeans w/ belt"
	  clothing_boots     comp 6 / 51 / 0   illenium-appearance Config.Outfits,
	                                       police "Short Sleeve" Male -> shoes

	FEMALE VARIANTS ARE A KNOWN FOLLOW-UP AND ARE NOT ATTEMPTED HERE. Drawable
	indices are per-model: the same number is a different garment (or does not
	exist) on mp_f_freemode_01, and there is no trustworthy female source for
	these particular garments in this repo or in the resources it reads from.
	Inventing them would produce confidently wrong clothes. Equipping one of
	these on a female ped is blocked at runtime rather than guessed at - the
	client checks IsPedComponentVariationValid / SetPedPreloadPropData before
	the server is ever asked to take the item, so a bad pairing fails cleanly
	with the item still in the player's bag.

	There is no shop or vendor for these; they are admin-give / testing only
	(`/giveitem <id> clothing_beanie`). A purchase flow is separate future work.

	NOTHING here is ever given out automatically. A character's starting clothes
	come from character creation, and the inventory syncs itself to those (see
	Clothing.alwaysWorn above); it does not replace them with items from this
	list.
]]
Clothing.catalog = {
	clothing_beanie    = { prop = 0,      drawable = 2,  texture = 1 },
	clothing_balaclava = { component = 1, drawable = 52, texture = 0 },
	clothing_bomber    = { component = 11, drawable = 29, texture = 0 },
	clothing_vest      = { component = 9, drawable = 15, texture = 2 },
	clothing_jeans     = { component = 4, drawable = 4,  texture = 1 },
	clothing_boots     = { component = 6, drawable = 51, texture = 0 },
}

---Work out what a given item puts on the ped, and in which slot.
---
---Item metadata wins over the catalog, so the stock generic `clothing` item
---(whose drawable/texture/component live entirely in metadata, set by whatever
---created it) keeps working untouched. The catalog is the fallback for our own
---named items, which carry no metadata and therefore survive `/giveitem`.
---
---@param itemName string
---@param metadata table?
---@return { key: string, kind: 'prop'|'component', id: number, drawable: number, texture: number }?
function Clothing.getVariation(itemName, metadata)
	local kind, id, drawable, texture

	if type(metadata) == 'table' and type(metadata.drawable) == 'number' and type(metadata.texture) == 'number' then
		if type(metadata.prop) == 'number' then
			kind, id = 'prop', metadata.prop
		elseif type(metadata.component) == 'number' then
			kind, id = 'component', metadata.component
		end

		drawable, texture = metadata.drawable, metadata.texture
	end

	if not kind then
		local entry = Clothing.catalog[itemName]

		if not entry then return end

		if entry.prop then
			kind, id = 'prop', entry.prop
		else
			kind, id = 'component', entry.component
		end

		drawable, texture = entry.drawable, entry.texture
	end

	local slot = (kind == 'prop' and byProp or byComponent)[id]

	-- Deliberately nil for anything outside the six slots the Appearance card
	-- knows about (bags, gloves, neckwear...). Those would be equippable but
	-- invisible and un-unequippable in the UI, which is worse than refusing.
	if not slot then return end

	return { key = slot.key, kind = kind, id = id, drawable = drawable, texture = texture }
end

return Clothing
