import React from 'react';
import { Icon, InventoryIconName } from '../utils/icons/InventoryIcons';

/**
 * ---------------------------------------------------------------------------
 * KNOWN INCOMPLETE FEATURE - the data below is placeholder, on purpose.
 * ---------------------------------------------------------------------------
 * ox_inventory has an equip/unequip mechanic (`Item('clothing', ...)` in
 * modules/items/client.lua) but it does NOT expose "what is this ped currently
 * wearing" to the NUI in any form. There is no NUI event, no field on
 * leftInventory, and nothing in the ItemData payload that answers it.
 *
 * So this card is built as visual structure only: the six slots below are
 * hardcoded placeholders with a fixed `filled` flag, purely so the layout,
 * spacing and empty/filled treatments can be reviewed against the mockup.
 *
 * Deliberately NOT wired to anything: faking a data pipeline here (e.g.
 * scanning the player's item list for things whose name looks like clothing)
 * would produce a card that lies about the ped. When the equipped-items bridge
 * is added Lua-side, replace APPEARANCE_SLOTS with that real state and delete
 * this comment.
 */
type AppearanceSlot = {
  key: string;
  label: string;
  icon: InventoryIconName;
  /** PLACEHOLDER - no real data source exists for this yet. */
  filled: boolean;
};

const APPEARANCE_SLOTS: AppearanceSlot[] = [
  { key: 'head', label: 'Head', icon: 'head', filled: false },
  { key: 'mask', label: 'Mask', icon: 'mask', filled: true },
  { key: 'torso', label: 'Torso', icon: 'jacket', filled: true },
  { key: 'armour', label: 'Armour', icon: 'armor', filled: true },
  { key: 'legs', label: 'Legs', icon: 'legs', filled: true },
  { key: 'feet', label: 'Feet', icon: 'boots', filled: false },
];

const AppearanceCard: React.FC<{ characterName: string }> = ({ characterName }) => {
  const equipped = APPEARANCE_SLOTS.filter((slot) => slot.filled).length;

  return (
    <div className="panel appearance-card">
      <div className="band block-head">
        <h2 className="t-display">{characterName}</h2>
        <span className="t-eyebrow">
          Appearance · {`0${equipped}`.slice(-2)} / {`0${APPEARANCE_SLOTS.length}`.slice(-2)}
        </span>
      </div>
      <div className="band-underline" />
      <div className="accessories">
        {APPEARANCE_SLOTS.map((slot) => (
          <div key={slot.key} className="acc-slot" data-filled={slot.filled} title={slot.label}>
            <Icon name={slot.icon} />
          </div>
        ))}
      </div>
    </div>
  );
};

export default AppearanceCard;
