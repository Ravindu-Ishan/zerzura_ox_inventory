import { Items } from '../store/items';
import { Slot } from '../typings';
import { isSlotWithItem } from '.';

/**
 * Category filter for the left column's icon-filter row.
 *
 * ---------------------------------------------------------------------------
 * DATA AVAILABILITY - read this before "improving" the heuristics below.
 * ---------------------------------------------------------------------------
 * ox_inventory does not classify items. The only item metadata the NUI ever
 * receives is what client.lua packs into `ItemData` and ships with the `init`
 * event:
 *
 *     label, stack, close, count, description, buttons, ammoName, image
 *
 * There is no `category`, no `type`, and no `weapon` boolean. So:
 *
 *  - ALL      -> fully real, no guessing involved.
 *  - WEAPONS  -> real. ox_inventory registers weapons under an uppercase
 *                `WEAPON_*` name (see `getItem` in modules/items/client.lua,
 *                which uppercases any `weapon_` prefix) and ammo under
 *                `ammo-*` (data/weapons.lua). Both are load-bearing engine
 *                conventions, not cosmetic naming, so matching on them is
 *                sound. `ammoName` being present is a second real signal.
 *  - CLOTHING -> BEST EFFORT ONLY. The only clothing item ox ships is literally
 *                named `clothing`; the equip mechanic (`Item('clothing', ...)`)
 *                tags nothing. Everything else here is a name-keyword guess and
 *                will miss server-specific item names.
 *  - CONSUMABLES -> BEST EFFORT ONLY. What actually makes an item consumable
 *                lives in `client.status` / `consume` in data/items.lua, and
 *                neither field is sent to the NUI. Name keywords again.
 *  - MISC     -> real by construction: whatever the three above did not claim.
 *
 * The honest fix is Lua-side (add a `category` field to the ItemData payload),
 * which is out of scope for this frontend-only reskin.
 */

export type InventoryCategory = 'all' | 'weapons' | 'clothing' | 'consumables' | 'misc';

/** Real: engine-level naming conventions, safe to rely on. */
const isWeaponLike = (name: string): boolean => {
  const upper = name.toUpperCase();
  return upper.startsWith('WEAPON_') || upper.startsWith('AMMO-') || upper.startsWith('AMMO_');
};

/** Best effort: name keywords, no real data source. See the note above. */
const CLOTHING_HINT = /(cloth|shirt|pant|jean|jacket|hoodie|coat|vest|armou?r|mask|hat|cap|helmet|glove|shoe|boot|sneaker|bag|backpack|watch|glasses|earring|necklace|bracelet)/i;

/** Best effort: name keywords, no real data source. See the note above. */
const CONSUMABLE_HINT = /(water|cola|sprunk|beer|wine|whisk|coffee|juice|milk|drink|burger|sandwich|taco|pizza|donut|food|snack|chocolate|bandage|medkit|firstaid|painkill|pill|meds?$|cigar|joint|energy)/i;

export const getItemCategory = (name: string): Exclude<InventoryCategory, 'all'> => {
  if (isWeaponLike(name)) return 'weapons';
  if (Items[name]?.ammoName) return 'weapons';

  const label = Items[name]?.label ?? '';

  if (CLOTHING_HINT.test(name) || CLOTHING_HINT.test(label)) return 'clothing';
  if (CONSUMABLE_HINT.test(name) || CONSUMABLE_HINT.test(label)) return 'consumables';

  return 'misc';
};

/**
 * Filters a slot list by category + search text.
 *
 * Empty slots are kept when no filter is active so the grid still reads as a
 * fixed-size container. Once the player is filtering they want a result list,
 * not a mostly-empty grid, so empty slots drop out.
 */
export const filterSlots = (items: Slot[], category: InventoryCategory, search: string): Slot[] => {
  const query = search.trim().toLowerCase();
  const filtering = category !== 'all' || query.length > 0;

  if (!filtering) return items;

  return items.filter((slot) => {
    if (!isSlotWithItem(slot)) return false;

    if (category !== 'all' && getItemCategory(slot.name) !== category) return false;

    if (query) {
      const label = (slot.metadata?.label || Items[slot.name]?.label || slot.name).toLowerCase();
      if (!label.includes(query) && !slot.name.toLowerCase().includes(query)) return false;
    }

    return true;
  });
};
