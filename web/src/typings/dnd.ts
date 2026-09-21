import { AppearanceSlotKey } from './appearance';
import { Inventory } from './inventory';
import { Slot, SlotWithItem } from './slot';

export type DragSource = {
  item: Pick<SlotWithItem, 'slot' | 'name'>;
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
