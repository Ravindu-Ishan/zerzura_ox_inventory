export type AppearanceSlotKey = 'head' | 'mask' | 'torso' | 'armour' | 'legs' | 'feet';

/**
 * One tile of the Appearance card, as sent by modules/appearance/client.lua.
 *
 * `drawable`/`texture` are raw GTA ped variation numbers - they identify a
 * variation, NOT an inventory item, and cannot be mapped back to an item label.
 *
 * `canBeEmpty` says whether `filled === false` is even reachable for this slot.
 * Head (prop 0, -1 means nothing), Mask (component 1) and Armour (component 9)
 * have a real empty state. Torso, Legs and Feet do not - a freemode ped always
 * resolves to some drawable there - so they report filled: true permanently.
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
};

export type Appearance = {
  /** false when illenium-appearance could not be read; slots is then empty. */
  available: boolean;
  slots: AppearanceSlot[];
};
