import React from 'react';
import { Icon, InventoryIconName } from '../utils/icons/InventoryIcons';
import { useAppSelector } from '../../store';
import { selectAppearance } from '../../store/inventory';
import type { AppearanceSlot, AppearanceSlotKey } from '../../typings';

/**
 * ---------------------------------------------------------------------------
 * Real data now - but still a PARTIAL feature. Read this before "fixing" it.
 * ---------------------------------------------------------------------------
 * This card is driven by the `setAppearance` NUI event from
 * modules/appearance/client.lua, which reads the ped's live component/prop
 * variations (via illenium-appearance's getPedAppearance export) on inventory
 * open and after every clothing item use. So the worn/not-worn state below is
 * the real ped, regardless of whether the clothes came from an inventory item,
 * character creation, an admin command or another script.
 *
 * What it still CANNOT do, and why:
 *
 *  1. No item labels. The client only learns numbers - "component 11, drawable
 *     12, texture 2". Nothing on the client maps a drawable/texture pair back
 *     to the inventory item that set it, and reverse-guessing one would make
 *     the card confidently wrong. So a worn slot says "Worn" plus the raw
 *     numbers, never "Leather Jacket".
 *
 *  2. No empty state for Torso / Legs / Feet. A freemode ped always resolves to
 *     some drawable on components 11, 4 and 6 - drawable 0 is a real garment
 *     there, not an absence. Those three are reported permanently worn
 *     (canBeEmpty: false) rather than given a made-up "looks empty" heuristic.
 *     Only Head (prop 0, where -1 genuinely means nothing), Mask (component 1)
 *     and Armour (component 9) have a trustworthy empty signal.
 *
 *  3. Display only. Click-to-unequip is deliberately absent: with no slot ->
 *     item mapping (see 1) there is nothing to unequip.
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

              return (
                <div
                  key={slot.key}
                  className="acc-slot"
                  data-filled={slot.filled}
                  title={describe(slot, meta.label)}
                >
                  <Icon name={meta.icon} />
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
