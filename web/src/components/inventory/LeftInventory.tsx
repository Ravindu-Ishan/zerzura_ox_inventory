import React, { useMemo, useState } from 'react';
import InventoryGrid from './InventoryGrid';
import AppearanceCard from './AppearanceCard';
import CapacityBar from './CapacityBar';
import { useAppSelector } from '../../store';
import { selectLeftInventory } from '../../store/inventory';
import { getTotalWeight, isSlotWithItem } from '../../helpers';
import { filterSlots, InventoryCategory } from '../../helpers/categories';
import { Icon, InventoryIconName } from '../utils/icons/InventoryIcons';

/**
 * How many of the player's slots are drawn in the always-visible "Pockets"
 * section before the rest spills into the scrolling "Backpack" section.
 *
 * This is a PRESENTATION split only - there is one real capacity pool (see
 * CapacityBar) and the server enforces nothing per-section. 8 matches the
 * approved mockup.
 */
const POCKET_SLOTS = 8;

const CATEGORIES: { id: InventoryCategory; label: string; icon: InventoryIconName }[] = [
  { id: 'all', label: 'All', icon: 'grid' },
  { id: 'weapons', label: 'Weapons', icon: 'pistol' },
  { id: 'clothing', label: 'Clothing', icon: 'jacket' },
  { id: 'consumables', label: 'Consumables', icon: 'droplet' },
  { id: 'misc', label: 'Misc', icon: 'cube' },
];

const LeftInventory: React.FC = () => {
  const inventory = useAppSelector(selectLeftInventory);
  const [category, setCategory] = useState<InventoryCategory>('all');
  const [search, setSearch] = useState('');

  const weight = useMemo(
    () => (inventory.maxWeight !== undefined ? Math.floor(getTotalWeight(inventory.items) * 1000) / 1000 : 0),
    [inventory.maxWeight, inventory.items]
  );

  const usedSlots = useMemo(() => inventory.items.filter((slot) => isSlotWithItem(slot)).length, [inventory.items]);

  const isFiltering = category !== 'all' || search.trim().length > 0;

  // Unfiltered, the grid keeps its real shape: first POCKET_SLOTS slots on top,
  // the remainder below. Filtering collapses to a single result list, because a
  // filtered view split across two headed sections reads as two containers.
  const { pockets, backpack } = useMemo(() => {
    if (isFiltering) {
      return { pockets: [], backpack: filterSlots(inventory.items, category, search) };
    }

    return {
      pockets: inventory.items.slice(0, POCKET_SLOTS),
      backpack: inventory.items.slice(POCKET_SLOTS),
    };
  }, [inventory.items, category, search, isFiltering]);

  const countFilled = (slots: typeof inventory.items) => slots.filter((slot) => isSlotWithItem(slot)).length;
  const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);

  return (
    <div className="frame-left">
      {/* "who you are" - identity + equipped strip */}
      <AppearanceCard characterName={inventory.label || 'Character'} />

      {/* "what you're carrying" - filters, search, capacity and the grid as one unit */}
      <div className="panel body-block">
        <div className="band block-head">
          <h2 className="t-display">Inventory</h2>
          <span className="t-eyebrow">On Foot · {inventory.slots} Slots</span>
        </div>
        <div className="band-underline" />

        <div className="categories">
          {CATEGORIES.map((cat) => (
            <button
              key={cat.id}
              type="button"
              className="cat-btn"
              data-active={category === cat.id}
              title={cat.label}
              onClick={() => setCategory(cat.id)}
            >
              <Icon name={cat.icon} />
            </button>
          ))}
        </div>

        <div className="search-row">
          <label className="search-field">
            <Icon name="search" />
            <input
              type="text"
              placeholder="Search inventory"
              value={search}
              spellCheck={false}
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
        </div>

        <CapacityBar
          weight={weight}
          maxWeight={inventory.maxWeight}
          usedSlots={usedSlots}
          totalSlots={inventory.slots}
        />

        {isFiltering ? (
          // Filtered: one flat result list, and it is the part that scrolls.
          <div className="col-scroll">
            <div className="grid-band">
              <span className="t-label">Results</span>
              <span className="band-meta t-num">{backpack.length}</span>
            </div>
            {backpack.length > 0 ? (
              <InventoryGrid items={backpack} inventory={inventory} paged />
            ) : (
              <p className="empty-note">No matching items</p>
            )}
          </div>
        ) : (
          <>
            {/* Pockets sits OUTSIDE .col-scroll - it is always fully visible. */}
            <div className="grid-band static">
              <span className="t-label">Pockets</span>
              <span className="band-meta t-num">
                {pad(countFilled(pockets))} / {pad(pockets.length)}
              </span>
            </div>
            <InventoryGrid items={pockets} inventory={inventory} />

            {/* Backpack is the only scrolling region, and only when it does not
                fit: .col-scroll is flex:1 + min-height:0 inside a flex column,
                so on a tall screen it simply grows and never scrolls. */}
            <div className="col-scroll">
              <div className="grid-band">
                <span className="t-label">Backpack</span>
                <span className="band-meta t-num">
                  {pad(countFilled(backpack))} / {backpack.length}
                </span>
              </div>
              <InventoryGrid items={backpack} inventory={inventory} paged />
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default LeftInventory;
