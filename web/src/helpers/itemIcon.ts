import { SlotWithItem } from '../typings';
import { Appearance, AppearanceSlotKey } from '../typings/appearance';
import { InventoryIconName } from '../components/utils/icons/InventoryIcons';
import { getItemCategory } from './categories';

/**
 * Fallback icon for an item with no real thumbnail (`web/images/<name>.png`
 * missing, or a metadata `image` that 404s). Shown instead of a broken image,
 * never alongside one - see the `useImageAvailable` hook in this file, which
 * is what actually detects the missing file and triggers the swap.
 *
 * Two tiers of honesty, matching helpers/categories.ts's own:
 *
 *  - Clothing gets a SPECIFIC slot icon (head/mask/jacket/armor/legs/boots)
 *    whenever the slot is actually known - i.e. a named catalog item (via
 *    Appearance.catalog, the real slot map modules/appearance/client.lua
 *    already resolves server-side) or a metadata-driven generic `clothing`
 *    item (component/prop read directly off its own metadata, the same
 *    values Clothing.getVariation reads Lua-side). Nothing here is guessed.
 *  - Everything else falls back to a generic per-CATEGORY icon
 *    (weapons/consumables/misc), or a generic torso silhouette for a
 *    clothing item whose specific slot isn't resolvable from what the NUI
 *    was given - still honest (it IS clothing), just not slot-specific.
 */

/** Mirrors modules/clothing/shared.lua's Clothing.slots id -> key mapping.
 *  Small and duplicated on purpose: this is the same category of unavoidable
 *  cross-boundary mirror as AppearanceSlot's own shape (see typings/appearance.ts) -
 *  there is no shared build step between the Lua and the NUI bundle. */
const COMPONENT_SLOT: Partial<Record<number, AppearanceSlotKey>> = {
  1: 'mask',
  4: 'legs',
  6: 'feet',
  9: 'armour',
  11: 'torso',
};
const PROP_SLOT: Partial<Record<number, AppearanceSlotKey>> = {
  0: 'head',
};

const SLOT_ICON: Record<AppearanceSlotKey, InventoryIconName> = {
  head: 'head',
  mask: 'mask',
  torso: 'jacket',
  armour: 'armor',
  legs: 'legs',
  feet: 'boots',
};

/**
 * Resolve a clothing item down to a specific Appearance slot, if we can.
 *
 * The precedence and the conditions are Clothing.getVariation's, deliberately:
 * per-instance metadata wins over the name-keyed catalog, and the metadata
 * branch is only taken when it carries a COMPLETE variation - a numeric
 * component/prop AND a numeric drawable AND a numeric texture. Lua requires all
 * three before it will look at metadata at all
 * (modules/clothing/shared.lua), so anything less has to fall through to the
 * catalog here too or the two sides disagree about the same item.
 *
 * Used for two things now, and it must stay one function for both: picking a
 * fallback icon, and deciding whether a dragged item may be dropped on an
 * Appearance tile (see AppearanceCard). The second one is the reason the
 * metadata branch matters - the generic `clothing` item has no catalog entry,
 * and it is what every real character's starter garments are made of.
 *
 * Only `name` and `metadata` are read, so a drag source carrying just those two
 * is enough.
 */
export const resolveClothingSlot = (
  item: Pick<SlotWithItem, 'name' | 'metadata'>,
  catalog?: Appearance['catalog']
): AppearanceSlotKey | undefined => {
  const metadata = item.metadata as
    | { component?: number; prop?: number; drawable?: number; texture?: number }
    | undefined;

  if (typeof metadata?.drawable === 'number' && typeof metadata?.texture === 'number') {
    if (typeof metadata.prop === 'number') return PROP_SLOT[metadata.prop];
    if (typeof metadata.component === 'number') return COMPONENT_SLOT[metadata.component];
  }

  return catalog?.[item.name];
};

/**
 * @param item     the slot to pick a fallback for
 * @param catalog  Appearance.catalog from the redux store (selectAppearance) -
 *                 optional so this stays callable from anywhere that doesn't
 *                 have it handy, at the cost of named-clothing-item icons
 *                 falling back to the generic torso glyph instead.
 */
export const getFallbackIcon = (item: SlotWithItem, catalog?: Appearance['catalog']): InventoryIconName => {
  const category = getItemCategory(item.name);

  if (category === 'weapons') return 'pistol';
  if (category === 'consumables') return 'droplet';

  if (category === 'clothing') {
    const slot = resolveClothingSlot(item, catalog);
    return slot ? SLOT_ICON[slot] : 'jacket';
  }

  return 'cube';
};
