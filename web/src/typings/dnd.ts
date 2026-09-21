import { AppearanceSlotKey } from './appearance';
import { Inventory } from './inventory';
import { Slot, SlotWithItem } from './slot';

export type DragSource = {
  /**
   * `metadata` rides along purely so a drop target can ask what the item IS
   * without reaching back into the store. It is the only per-instance answer to
   * "which Appearance tile does this garment belong on" for the generic
   * `clothing` item, whose slot lives in metadata rather than in its name (see
   * resolveClothingSlot in helpers/itemIcon.ts and Clothing.getVariation in
   * modules/clothing/shared.lua).
   *
   * Nothing authoritative reads it: onDrop/onBuy/onCraft still resolve the real
   * slot out of redux by `item.slot` and ignore everything else on the source,
   * and equipping still goes through useItem -> the Lua validation path, which
   * consults getVariation again on both the client and the server.
   */
  item: Pick<SlotWithItem, 'slot' | 'name'> & Partial<Pick<SlotWithItem, 'metadata'>>;
  inventory: Inventory['type'];
  image?: string;
};

/**
 * An equipped Appearance tile being dragged OUT of the card, to take it off.
 *
 * Deliberately carried under its own react-dnd type ('APPEARANCE') rather than
 * as a 'SLOT' with invented numbers: `onDrop` resolves a 'SLOT' source by
 * indexing straight into a real inventory's items array, and a worn garment has
 * no slot in any inventory to index - that is the whole point of the feature.
 * A separate type means the two flows can never be mistaken for each other.
 */
export type AppearanceDragSource = {
  key: AppearanceSlotKey;
  /** Item name, for the drag preview image only. */
  name?: string;
  image?: string;
};

export type DropTarget = {
  item: Pick<Slot, 'slot'>;
  inventory: Inventory['type'];
};
