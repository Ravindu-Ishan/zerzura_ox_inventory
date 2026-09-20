import { Appearance } from './appearance';
import { Inventory } from './inventory';
import { Slot } from './slot';

export type State = {
  leftInventory: Inventory;
  rightInventory: Inventory;
  /**
   * What the ped is actually wearing, pushed by the `setAppearance` NUI event.
   * null until the first push (or if the client never sends one).
   */
  appearance: Appearance | null;
  itemAmount: number;
  shiftPressed: boolean;
  isBusy: boolean;
  additionalMetadata: Array<{ metadata: string; value: string }>;
  history?: {
    leftInventory: Inventory;
    rightInventory: Inventory;
  };
};
