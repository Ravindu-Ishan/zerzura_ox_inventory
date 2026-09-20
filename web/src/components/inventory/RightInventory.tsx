import React, { useMemo } from 'react';
import { useDrop } from 'react-dnd';
import InventoryGrid from './InventoryGrid';
import CapacityBar from './CapacityBar';
import { useAppSelector } from '../../store';
import { selectRightInventory } from '../../store/inventory';
import { getTotalWeight, isSlotWithItem } from '../../helpers';
import { onDrop } from '../../dnd/onDrop';
import { DragSource } from '../../typings';
import { Icon } from '../utils/icons/InventoryIcons';

/**
 * Is there a real container on the right, or nothing?
 *
 * ox_inventory always sends a secondary inventory with `setupInventory`, even
 * when the player has nothing open: client.lua's `defaultInventory` is a
 * `newdrop` placeholder with no id, which exists only as a staging area for
 * "drop this on the ground". A `drop` (an actual bag already lying there),
 * a trunk, glovebox, stash, shop, crafting bench etc. are all real.
 *
 * `type === ''` is the pre-first-event redux initial state.
 */
const hasRealContainer = (type: string, id: string) => type !== '' && type !== 'newdrop' && id !== '';

/** Human label for the card subtitle when the server sends no better one. */
const TYPE_LABELS: Record<string, string> = {
  drop: 'Ground',
  trunk: 'Vehicle',
  glovebox: 'Vehicle',
  stash: 'Stash',
  shop: 'Shop',
  crafting: 'Crafting',
  container: 'Container',
  player: 'Player',
  dumpster: 'Dumpster',
  policeevidence: 'Evidence',
};

const RightInventory: React.FC = () => {
  const inventory = useAppSelector(selectRightInventory);
  const isOpen = hasRealContainer(inventory.type, inventory.id);

  const weight = useMemo(
    () => (inventory.maxWeight !== undefined ? Math.floor(getTotalWeight(inventory.items) * 1000) / 1000 : 0),
    [inventory.maxWeight, inventory.items]
  );

  const usedSlots = useMemo(() => inventory.items.filter((slot) => isSlotWithItem(slot)).length, [inventory.items]);

  // The collapsed tab has to stay a drop target: with no container open, this
  // column IS "drop it on the ground". onDrop with no explicit target slot
  // resolves to the first free slot of the newdrop staging inventory, which is
  // exactly what dropping onto one of its slots used to do.
  const [{ isOver }, dropGround] = useDrop<DragSource, void, { isOver: boolean }>(
    () => ({
      accept: 'SLOT',
      collect: (monitor) => ({ isOver: monitor.isOver() }),
      drop: (source) => {
        if (source.inventory === 'player') onDrop(source);
      },
    }),
    [inventory.type]
  );

  if (!isOpen) {
    return (
      <div className="frame-right collapsed">
        <div
          className="panel ground-collapsed"
          data-over={isOver}
          ref={(el) => {
            dropGround(el);
          }}
        >
          <Icon name="drop" />
          <span>Ground · Drag To Drop</span>
        </div>
      </div>
    );
  }

  const subtitle = inventory.groups
    ? Object.keys(inventory.groups).join(' · ')
    : TYPE_LABELS[inventory.type] || inventory.type;

  return (
    <div className="frame-right">
      <div className="panel">
        <div className="band block-head">
          <h2 className="t-display">{inventory.label || TYPE_LABELS[inventory.type] || 'Container'}</h2>
          <span className="t-eyebrow">{subtitle}</span>
        </div>
        <div className="band-underline" />

        <CapacityBar
          weight={weight}
          maxWeight={inventory.maxWeight}
          usedSlots={usedSlots}
          totalSlots={inventory.slots}
        />

        <div className="col-scroll">
          <InventoryGrid items={inventory.items} inventory={inventory} paged className="pad-top" />
        </div>
      </div>
    </div>
  );
};

export default RightInventory;
