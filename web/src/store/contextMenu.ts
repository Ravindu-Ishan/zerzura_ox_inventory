import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import { AppearanceSlot, SlotWithItem } from '../typings';

/**
 * One menu, two possible subjects. `item` is an inventory square (Use / Give /
 * Drop / ...), `appearance` is a worn Appearance tile (Unequip). They are
 * mutually exclusive - opening one clears the other - so InventoryContext never
 * has to guess which set of actions applies.
 */
interface ContextMenuState {
  coords: {
    x: number;
    y: number;
  } | null;
  item: SlotWithItem | null;
  appearance: AppearanceSlot | null;
}

const initialState: ContextMenuState = {
  coords: null,
  item: null,
  appearance: null,
};

export const contextMenuSlice = createSlice({
  name: 'contextMenu',
  initialState,
  reducers: {
    openContextMenu(state, action: PayloadAction<{ item: SlotWithItem; coords: { x: number; y: number } }>) {
      state.coords = action.payload.coords;
      state.item = action.payload.item;
      state.appearance = null;
    },
    openAppearanceContextMenu(
      state,
      action: PayloadAction<{ slot: AppearanceSlot; coords: { x: number; y: number } }>
    ) {
      state.coords = action.payload.coords;
      state.item = null;
      state.appearance = action.payload.slot;
    },
    closeContextMenu(state) {
      state.coords = null;
    },
  },
});

export const { openContextMenu, openAppearanceContextMenu, closeContextMenu } = contextMenuSlice.actions;

export default contextMenuSlice.reducer;
