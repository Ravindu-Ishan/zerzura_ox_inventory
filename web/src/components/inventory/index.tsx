import React, { useState } from 'react';
import useNuiEvent from '../../hooks/useNuiEvent';
import InventoryControl from './InventoryControl';
import { useAppDispatch } from '../../store';
import { refreshSlots, setAdditionalMetadata, setAppearance, setupInventory } from '../../store/inventory';
import { useExitListener } from '../../hooks/useExitListener';
import type { Appearance, Inventory as InventoryProps } from '../../typings';
import RightInventory from './RightInventory';
import LeftInventory from './LeftInventory';
import Tooltip from '../utils/Tooltip';
import { closeTooltip } from '../../store/tooltip';
import InventoryContext from './InventoryContext';
import { closeContextMenu } from '../../store/contextMenu';
import Fade from '../utils/transitions/Fade';
import { InventoryIconSprite } from '../utils/icons/InventoryIcons';
import { fetchNui } from '../../utils/fetchNui';

/**
 * Report what the card actually received back to Lua, so it lands in the F8
 * console next to what modules/appearance/client.lua says it sent.
 *
 * This exists because "verified in the browser" has already been wrong about
 * this payload once: App.tsx's debugData hardcodes an appearance (catalog
 * included) in TypeScript, so a dev-server run never exercises the Lua that
 * builds and serialises the real one. The two ends now state their own version
 * of events and the console shows whether they agree.
 *
 * Reported once, plus again on any payload whose catalog is missing, empty or
 * array-shaped - i.e. exactly the states in which drag-to-equip would silently
 * refuse every named garment. fetchNui is a no-op in a plain browser.
 */
let reportedAppearance = false;

const reportAppearancePayload = (data?: Appearance) => {
  const catalog = data?.catalog;
  const catalogIsArray = Array.isArray(catalog);
  const catalogKeys = catalog && !catalogIsArray ? Object.keys(catalog) : [];

  if (reportedAppearance && catalogKeys.length > 0) return;

  reportedAppearance = true;

  fetchNui('clothingDebug', {
    available: !!data?.available,
    slots: Array.isArray(data?.slots) ? data!.slots.length : -1,
    catalogEntries: catalogKeys.length,
    catalogIsArray,
    catalogKeys,
  }).catch(() => {
    // A diagnostic must never be the thing that breaks the card.
  });
};

const Inventory: React.FC = () => {
  const [inventoryVisible, setInventoryVisible] = useState(false);
  const dispatch = useAppDispatch();

  useNuiEvent<boolean>('setInventoryVisible', setInventoryVisible);
  useNuiEvent<false>('closeInventory', () => {
    setInventoryVisible(false);
    dispatch(closeContextMenu());
    dispatch(closeTooltip());
  });
  useExitListener(setInventoryVisible);

  useNuiEvent<{
    leftInventory?: InventoryProps;
    rightInventory?: InventoryProps;
  }>('setupInventory', (data) => {
    dispatch(setupInventory(data));
    !inventoryVisible && setInventoryVisible(true);
  });

  useNuiEvent('refreshSlots', (data) => dispatch(refreshSlots(data)));

  // Real ped component/prop state for the Appearance card. Sent on inventory
  // open and again after any clothing item is used - see
  // modules/appearance/client.lua.
  useNuiEvent<Appearance>('setAppearance', (data) => {
    dispatch(setAppearance(data));
    reportAppearancePayload(data);
  });

  useNuiEvent('displayMetadata', (data: Array<{ metadata: string; value: string }>) => {
    dispatch(setAdditionalMetadata(data));
  });

  // The hotbar is gone on purpose. A separate radial menu resource owns quick-use
  // actions now, so the stock always-on-screen <InventoryHotbar /> overlay (which
  // rendered outside this fade wrapper, i.e. even with the bag closed) is not
  // rendered at all. InventoryHotbar.tsx is left in the tree, unreferenced.
  return (
    <Fade in={inventoryVisible}>
      <div className="inventory-wrapper">
        <InventoryIconSprite />
        {/* Edge-anchored 3-piece frame. The centre grid cell is left empty on
            purpose: that is where the player's ped is framed in-game. */}
        <div className="hud-frame">
          <LeftInventory />
          <div className="frame-center" />
          <RightInventory />
          <InventoryControl />
        </div>
        <Tooltip />
        <InventoryContext />
      </div>
    </Fade>
  );
};

export default Inventory;
