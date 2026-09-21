export type AppearanceSlotKey = 'head' | 'mask' | 'torso' | 'armour' | 'legs' | 'feet';

/**
 * One tile of the Appearance card, as sent by modules/appearance/client.lua.
 *
 * `drawable`/`texture` are raw GTA ped variation numbers - they identify a
 * variation, not an item.
 *
 * `canBeEmpty` says whether `filled === false` is even reachable for this slot.
 * Head (prop 0, -1 means nothing), Mask (component 1) and Armour (component 9)
 * have a real empty state. Torso, Legs and Feet do not - a freemode ped always
 * resolves to some drawable there - so they report filled: true permanently.
 *
 * `item`/`label`/`unequippable` are only present when the inventory itself put
 * the garment on the ped AND the ped still matches that record. A slot filled by
 * character creation, an admin command or another script is `filled` with no
 * item, because there is nothing to hand back to the player.
 */
export type AppearanceSlot = {
  key: AppearanceSlotKey;
  kind: 'component' | 'prop';
  /** Component id or prop id this slot reads. */
  id: number;
  drawable?: number;
  texture?: number;
  filled: boolean;
  canBeEmpty: boolean;
  /** Inventory item name backing this slot, if the inventory equipped it. */
  item?: string;
  /** That item's label, as resolved server-side when it was equipped. */
  label?: string;
  /** True when clicking the tile will return the item to the inventory. */
  unequippable?: boolean;
};

export type Appearance = {
  /** false when illenium-appearance could not be read; slots is then empty. */
  available: boolean;
  slots: AppearanceSlot[];
};
