import React, { useEffect, useState } from 'react';
import { Inventory, Slot } from '../../typings';
import InventorySlot from './InventorySlot';
import { useIntersection } from '../../hooks/useIntersection';

const PAGE_SIZE = 30;

/**
 * A plain grid of slots.
 *
 * The header/capacity chrome that used to live here now belongs to the column
 * that owns the grid (LeftInventory / RightInventory), because the reskin has
 * one header per card rather than one per grid - the left column renders two
 * grids (Pockets, Backpack) under a single shared header and capacity bar.
 *
 * `paged` keeps the stock incremental-render behaviour for long lists (a stash
 * or trunk can be thousands of slots); short lists render in one go.
 */
const InventoryGrid: React.FC<{
  items: Slot[];
  inventory: Inventory;
  paged?: boolean;
  className?: string;
}> = ({ items, inventory, paged = false, className }) => {
  const [page, setPage] = useState(0);
  const { ref, entry } = useIntersection({ threshold: 0.5 });

  useEffect(() => {
    if (entry && entry.isIntersecting) setPage((prev) => prev + 1);
  }, [entry]);

  // Reset paging when the underlying container changes, otherwise opening a
  // small stash after a large one would render it fully expanded.
  useEffect(() => setPage(0), [inventory.id, inventory.type]);

  const limit = paged ? (page + 1) * PAGE_SIZE : items.length;
  const visible = paged ? items.slice(0, limit) : items;

  return (
    <div className={className ? `inv-grid ${className}` : 'inv-grid'}>
      {visible.map((item, index) => (
        <InventorySlot
          key={`${inventory.type}-${inventory.id}-${item.slot}`}
          item={item}
          ref={paged && index === limit - 1 ? ref : null}
          inventoryType={inventory.type}
          inventoryGroups={inventory.groups}
          inventoryId={inventory.id}
        />
      ))}
    </div>
  );
};

export default InventoryGrid;
