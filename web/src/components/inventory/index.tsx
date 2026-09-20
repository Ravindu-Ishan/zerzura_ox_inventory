import React, { useState } from 'react';
import useNuiEvent from '../../hooks/useNuiEvent';
import InventoryControl from './InventoryControl';
import { useAppDispatch } from '../../store';
import { refreshSlots, setAdditionalMetadata, setupInventory } from '../../store/inventory';
import { useExitListener } from '../../hooks/useExitListener';
import type { Inventory as InventoryProps } from '../../typings';
import RightInventory from './RightInventory';
import LeftInventory from './LeftInventory';
import Tooltip from '../utils/Tooltip';
import { closeTooltip } from '../../store/tooltip';
import InventoryContext from './InventoryContext';
import { closeContextMenu } from '../../store/contextMenu';
import Fade from '../utils/transitions/Fade';
import { InventoryIconSprite } from '../utils/icons/InventoryIcons';

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
