import React from 'react';
import { useDrag, useDrop } from 'react-dnd';
import { Icon, InventoryIconName } from '../utils/icons/InventoryIcons';
import { useAppDispatch, useAppSelector } from '../../store';
import { selectAppearance } from '../../store/inventory';
import { openAppearanceContextMenu } from '../../store/contextMenu';
import { closeTooltip } from '../../store/tooltip';
import { equipFromSlot } from '../../dnd/onClothing';
import { getItemUrl } from '../../helpers';
import type { Appearance, AppearanceDragSource, AppearanceSlot, AppearanceSlotKey, DragSource } from '../../typings';

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
 *     INVENTORY filled also carries the real item name, and can be taken off to
 *     put that item back in the bag.
 *
 * The distinction matters and is preserved rather than smoothed over:
 *
 *  - A slot with `unequippable` shows the item's label and is interactive.
 *  - A slot that is `filled` with no item was dressed by character creation, an
 *    admin command or qbx_radialmenu's separate clothing toggle. There is no
 *    item to give back, so it stays "Worn" and is inert.
 *  - Torso / Legs / Feet still have no empty state (canBeEmpty: false): a
 *    freemode ped always resolves to some drawable on components 11, 4 and 6.
 *    Taking our garment off there restores the drawable the ped had immediately
 *    before it went on, not a made-up "bare" constant.
 *
 * ---------------------------------------------------------------------------
 * Interaction: three deliberate gestures, no bare clicks.
 * ---------------------------------------------------------------------------
 * A plain left-click used to unequip. It does not any more, and should not be
 * reinstated: this card sits next to the grid, and a stray click that silently
 * strips a garment (and can fail on a full bag) is not something the player
 * asked for. Taking something off now needs intent:
 *
 *  - EQUIP:   drag the item from the grid onto its tile. Accepted only when the
 *             catalog says that item belongs on that tile; a mismatched garment
 *             is not a valid drop target at all, so the drag simply will not
 *             land. This fires the same `useItem` message as right-click ->
 *             Use, which is still there and still works.
 *  - UNEQUIP: right-click the tile -> "Unequip", or drag the tile onto an
 *             inventory square. Both end in the same `unequipClothing`
 *             callback; the drag just names a preferred destination square.
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
  if (!slot.filled) return `${label} · Empty — drag a garment here to wear it`;

  const variation =
    slot.drawable !== undefined && slot.texture !== undefined
      ? ` (${slot.kind} ${slot.id}, drawable ${slot.drawable}, texture ${slot.texture})`
      : '';

  // A real item behind the slot: name it, and say what takes it off.
  if (slot.unequippable) return `${slot.label ?? slot.item} · Right-click to unequip, or drag it out${variation}`;

  // Honest about the three slots that can never report empty.
  const caveat = slot.canBeEmpty ? '' : ' — this slot has no "nothing worn" state';

  return `${label} · Worn${variation}${caveat}`;
};

/**
 * One tile.
 *
 * Its own component purely because it needs hooks (useDrag / useDrop) and those
 * cannot live inside a .map() callback.
 */
const AppearanceTile: React.FC<{ slot: AppearanceSlot; catalog: Appearance['catalog'] }> = ({ slot, catalog }) => {
  const dispatch = useAppDispatch();
  const meta = SLOT_META[slot.key];
  const interactive = !!slot.unequippable;

  // --- drop target: equip -------------------------------------------------
  const [{ isOver }, drop] = useDrop<DragSource, void, { isOver: boolean }>(
    () => ({
      accept: 'SLOT',
      collect: (monitor) => ({ isOver: monitor.isOver() && monitor.canDrop() }),
      // Only a garment that actually belongs on THIS tile, and only out of the
      // player's own inventory - you cannot dress yourself straight out of a
      // trunk or a shop any more than you could before.
      canDrop: (source) => source.inventory === 'player' && catalog?.[source.item.name] === slot.key,
      drop: (source) => {
        dispatch(closeTooltip());
        equipFromSlot(source.item.slot);
      },
    }),
    [slot.key, catalog, dispatch]
  );

  // --- drag source: unequip ----------------------------------------------
  const [{ isDragging }, drag] = useDrag<AppearanceDragSource, void, { isDragging: boolean }>(
    () => ({
      type: 'APPEARANCE',
      collect: (monitor) => ({ isDragging: monitor.isDragging() }),
      canDrag: () => interactive,
      item: () =>
        slot.item
          ? {
              key: slot.key,
              name: slot.item,
              image: `url(${getItemUrl(slot.item) || 'none'})`,
            }
          : null,
    }),
    [slot.key, slot.item, interactive]
  );

  const handleContext = (event: React.MouseEvent<HTMLDivElement>) => {
    event.preventDefault();
    if (!interactive) return;

    dispatch(openAppearanceContextMenu({ slot, coords: { x: event.clientX, y: event.clientY } }));
  };

  return (
    <div
      ref={(element) => {
        drag(drop(element));
      }}
      className="acc-slot"
      data-filled={slot.filled}
      data-clickable={interactive}
      data-over={isOver || undefined}
      style={{ opacity: isDragging ? 0.4 : 1.0 }}
      title={describe(slot, meta.label)}
      onContextMenu={handleContext}
    >
      <Icon name={meta.icon} />
      {slot.label && <span className="acc-slot-label">{slot.label}</span>}
    </div>
  );
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
          ? slots.map((slot) => <AppearanceTile key={slot.key} slot={slot} catalog={appearance?.catalog} />)
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
