import React from 'react';
import { Icon, InventoryIconName } from '../utils/icons/InventoryIcons';
import { useAppSelector } from '../../store';
import { selectAppearance } from '../../store/inventory';
import { fetchNui } from '../../utils/fetchNui';
import type { AppearanceSlot, AppearanceSlotKey } from '../../typings';

/**
 * ---------------------------------------------------------------------------
 * Item-backed. Read this before "fixing" it.
 * ---------------------------------------------------------------------------
 * Driven by the `setAppearance` NUI event from modules/appearance/client.lua,
 * which combines two sources:
 *
 *  1. The ped's live component/prop variations (via illenium-appearance's
 *     getPedAppearance export) - so worn/not-worn is honest no matter what put
 *     the clothes there.
 *  2. The equipped-item records the inventory owns server-side - so a slot the
 *     INVENTORY filled also carries the real item name, and can be clicked to
 *     take it off and put the item back in the bag.
 *
 * The distinction matters and is preserved rather than smoothed over:
 *
 *  - A slot with `unequippable` shows the item's label and is a button. Clicking
 *    it asks the server to return that item; the server can refuse (no room),
 *    in which case nothing changes and the player is notified in game.
 *  - A slot that is `filled` with no item was dressed by character creation, an
 *    admin command or qbx_radialmenu's separate clothing toggle. There is no
 *    item to give back, so it stays "Worn" and is not clickable.
 *  - Torso / Legs / Feet still have no empty state (canBeEmpty: false): a
 *    freemode ped always resolves to some drawable on components 11, 4 and 6.
 *    Taking our garment off there restores the drawable the ped had immediately
 *    before it went on, not a made-up "bare" constant.
 *
 * If the client never sends the event, or illenium-appearance is missing, the
 * card renders an explicit "unknown" state instead of pretending the ped is
 * undressed.
 */
const SLOT_META: Record<AppearanceSlotKey, { label: string; icon: InventoryIconName }> = {
  head: { label: 'Head', icon: 'head' },
  mask: { label: 'Mask', icon: 'mask' },
  torso: { label: 'Torso', icon: 'jacket' },
  armour: { label: 'Armour', icon: 'armor' },
  legs: { label: 'Legs', icon: 'legs' },
  feet: { label: 'Feet', icon: 'boots' },
};

/** Display order, and the fallback layout when no data has arrived yet. */
const SLOT_ORDER: AppearanceSlotKey[] = ['head', 'mask', 'torso', 'armour', 'legs', 'feet'];

const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);

const describe = (slot: AppearanceSlot, label: string) => {
  if (!slot.filled) return `${label} · Empty`;

  const variation =
    slot.drawable !== undefined && slot.texture !== undefined
      ? ` (${slot.kind} ${slot.id}, drawable ${slot.drawable}, texture ${slot.texture})`
      : '';

  // A real item behind the slot: name it, and say the click does something.
  if (slot.unequippable) return `${slot.label ?? slot.item} · Click to take off${variation}`;

  // Honest about the three slots that can never report empty.
  const caveat = slot.canBeEmpty ? '' : ' — this slot has no "nothing worn" state';

  return `${label} · Worn${variation}${caveat}`;
};

const AppearanceCard: React.FC<{ characterName: string }> = ({ characterName }) => {
  const appearance = useAppSelector(selectAppearance);

  // Only trust slots we have a tile for; anything else is ignored rather than
  // rendered as a nameless square.
  const slots = (appearance?.available ? appearance.slots : []).filter((slot) => SLOT_META[slot.key]);
  const hasData = slots.length > 0;
  const equipped = slots.filter((slot) => slot.filled).length;

  const unequip = (slot: AppearanceSlot) => {
    if (!slot.unequippable) return;

    // Fire and forget: the client applies the revert only once the server has
    // confirmed the item is back in the inventory, and pushes a fresh
    // setAppearance either way. Nothing is optimistically mutated here.
    fetchNui('unequipClothing', { key: slot.key });
  };

  return (
    <div className="panel appearance-card">
      <div className="band block-head">
        <h2 className="t-display">{characterName}</h2>
        <span className="t-eyebrow">
          Appearance · {hasData ? pad(equipped) : '--'} / {pad(hasData ? slots.length : SLOT_ORDER.length)}
        </span>
      </div>
      <div className="band-underline" />
      <div className="accessories">
        {hasData
          ? slots.map((slot) => {
              const meta = SLOT_META[slot.key];
              const clickable = !!slot.unequippable;

              return (
                <div
                  key={slot.key}
                  className="acc-slot"
                  data-filled={slot.filled}
                  data-clickable={clickable}
                  title={describe(slot, meta.label)}
                  role={clickable ? 'button' : undefined}
                  tabIndex={clickable ? 0 : undefined}
                  onClick={clickable ? () => unequip(slot) : undefined}
                  onKeyDown={
                    clickable
                      ? (event) => {
                          if (event.key === 'Enter' || event.key === ' ') {
                            event.preventDefault();
                            unequip(slot);
                          }
                        }
                      : undefined
                  }
                >
                  <Icon name={meta.icon} />
                  {slot.label && <span className="acc-slot-label">{slot.label}</span>}
                </div>
              );
            })
          : SLOT_ORDER.map((key) => (
              <div
                key={key}
                className="acc-slot"
                data-filled={false}
                title={`${SLOT_META[key].label} · Unknown — appearance data unavailable`}
              >
                <Icon name={SLOT_META[key].icon} />
              </div>
            ))}
      </div>
    </div>
  );
};

export default AppearanceCard;
