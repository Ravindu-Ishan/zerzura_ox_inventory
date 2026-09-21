---@todo separate module into smaller submodules to handle each framework
---starting to get bulky

---Checks whether the inventory player has a required group and rank
---@param inv table
---@param group string | table<string, number | number[]>
---@return string? groupName
---@return number? groupRank
function server.hasGroup(inv, group)
	if type(group) == 'table' then
		for name, requiredRank in pairs(group) do
			local groupRank = inv.player.groups[name]
			if groupRank then
				if type(requiredRank) == 'table' then
					if lib.table.contains(requiredRank, groupRank) then
						return name, groupRank
					end
				else
					if groupRank >= (requiredRank or 0) then
						return name, groupRank
					end
				end
			end
		end
	else
		local groupRank = inv.player.groups[group]
		if groupRank then
			return group, groupRank
		end
	end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
	if not player.groups then
		warn(("server.setPlayerData did not receive any groups for '%s'"):format(player?.name or GetPlayerName(player)))
	end

	return {
		source = player.source,
		name = player.name,
		groups = player.groups or {},
		sex = player.sex,
		dateofbirth = player.dateofbirth,
	}
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense()
	warn('Licenses are not supported for the current framework.')
end

---Equipped clothing (modules/clothing/server.lua) is stored as player metadata
---so it piggybacks on the framework's existing player save - no new table.
---Frameworks without a metadata store fall back to an in-memory record, which
---works for the session and is lost on relog.
---@diagnostic disable-next-line: duplicate-set-field
function server.getClothingMetadata() end

local warnedClothingMetadata = false

---@diagnostic disable-next-line: duplicate-set-field
function server.setClothingMetadata()
	if warnedClothingMetadata then return end

	warnedClothingMetadata = true

	warn('Equipped clothing cannot be saved for the current framework - it will be lost on relog.')
end

---One-time, persistent per-character flags.
---
---This is NOT the same kind of store as the clothing metadata above, and the
---difference matters: an in-memory fallback is acceptable for "what am I
---wearing" (worst case the player relogs and their hat is in their bag again),
---but it is NOT acceptable for "have I already been given free items". A flag
---that forgets itself on relog is an infinite item duplication exploit.
---
---So the contract is deliberately fail-closed: the default returns nil from the
---getter and `false` from the setter, meaning "this framework cannot promise
---me anything", and modules/clothing/server.lua refuses to grant rather than
---granting something it cannot record having granted.
---@diagnostic disable-next-line: duplicate-set-field
function server.getPlayerFlag() end

---@return boolean persisted false if the flag could not be stored durably
---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerFlag() return false end

local Inventory = require 'modules.inventory.server'

function server.playerDropped(source)
	local inv = Inventory(source) --[[@as OxInventory]]

	if inv?.player then
		inv:closeInventory()
		Inventory.Remove(inv)
	end
end

local success, result = pcall(lib.load, ('modules.bridge.%s.server'):format(shared.framework))

if not success then
    lib = nil
    error(result, 0)
end

if server.convertInventory then exports('ConvertItems', server.convertInventory) end