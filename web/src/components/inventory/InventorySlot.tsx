import React, { useCallback, useRef } from 'react';
import { AppearanceDragSource, DragSource, Inventory, InventoryType, Slot, SlotWithItem } from '../../typings';
import { useDrag, useDragDropManager, useDrop } from 'react-dnd';
import { useAppDispatch, useAppSelector } from '../../store';
import { onDrop } from '../../dnd/onDrop';
import { onBuy } from '../../dnd/onBuy';
import { canCraftItem, canPurchaseItem, getItemUrl, isSlotWithItem } from '../../helpers';
import { getFallbackIcon } from '../../helpers/itemIcon';
import { onUse } from '../../dnd/onUse';
import { unequipSlot } from '../../dnd/onClothing';
import { Locale } from '../../store/locale';
import { onCraft } from '../../dnd/onCraft';
import useNuiEvent from '../../hooks/useNuiEvent';
import { useImageAvailable } from '../../hooks/useImageAvailable';
import { ItemsPayload } from '../../reducers/refreshSlots';
import { closeTooltip, openTooltip } from '../../store/tooltip';
import { openContextMenu } from '../../store/contextMenu';
import { selectAppearance } from '../../store/inventory';
import { useMergeRefs } from '@floating-ui/react';
import Icon from '../utils/icons/InventoryIcons';

interface SlotProps {
  inventoryId: Inventory['id'];
  inventoryType: Inventory['type'];
  inventoryGroups: Inventory['groups'];
  item: Slot;
}

const InventorySlot: React.ForwardRefRenderFunction<HTMLDivElement, SlotProps> = (
  { item, inventoryId, inventoryType, inventoryGroups },
  ref
) => {
  const manager = useDragDropManager();
  const dispatch = useAppDispatch();
  const timerRef = useRef<number | null>(null);

  const canDrag = useCallback(() => {
    return canPurchaseItem(item, { type: inventoryType, groups: inventoryGroups }) && canCraftItem(item, inventoryType);
  }, [item, inventoryType, inventoryGroups]);

  const [{ isDragging }, drag] = useDrag<DragSource, void, { isDragging: boolean }>(
    () => ({
      type: 'SLOT',
      collect: (monitor) => ({
        isDragging: monitor.isDragging(),
      }),
      item: () =>
        isSlotWithItem(item, inventoryType !== InventoryType.SHOP)
          ? {
              inventory: inventoryType,
              item: {
                name: item.name,
                slot: item.slot,
                // Carried so an Appearance tile can tell whether this garment
                // belongs on it. A generic `clothing` item is not in the
                // name-keyed catalog - its slot is in here - and that item is
                // what every character's starter garments are made of.
                metadata: item.metadata,
              },
              image: item?.name && `url(${getItemUrl(item) || 'none'}`,
            }
          : null,
      canDrag,
    }),
    [inventoryType, item]
  );

  /**
   * Two kinds of drag can land on a square.
   *
   * 'SLOT' is stock: another inventory square, resolved by onDrop/onBuy/onCraft.
   *
   * 'APPEARANCE' is a worn garment being dragged off the Appearance card. It is
   * routed to the same `unequipClothing` callback the card's right-click menu
   * uses - this square is passed along as the preferred landing spot, which is
   * why it is handled per-slot here rather than as one big "anywhere in the
   * grid" target. It is only ever valid over an empty square of the player's
   * OWN inventory: the server puts the item back in the player's bag, so
   * offering a trunk or a stash square would be a lie.
   */
  const [{ isOver }, drop] = useDrop<DragSource | AppearanceDragSource, void, { isOver: boolean }>(
    () => ({
      accept: ['SLOT', 'APPEARANCE'],
      collect: (monitor) => ({
        // canDrop is folded in so a square that would refuse the drag does not
        // light up as if it would take it.
        isOver: monitor.isOver() && monitor.canDrop(),
      }),
      drop: (source, monitor) => {
        dispatch(closeTooltip());

        if (monitor.getItemType() === 'APPEARANCE') {
          return unequipSlot((source as AppearanceDragSource).key, item.slot);
        }

        const dragged = source as DragSource;

        switch (dragged.inventory) {
          case InventoryType.SHOP:
            onBuy(dragged, { inventory: inventoryType, item: { slot: item.slot } });
            break;
          case InventoryType.CRAFTING:
            onCraft(dragged, { inventory: inventoryType, item: { slot: item.slot } });
            break;
          default:
            onDrop(dragged, { inventory: inventoryType, item: { slot: item.slot } });
            break;
        }
      },
      canDrop: (source, monitor) => {
        if (monitor.getItemType() === 'APPEARANCE') {
          return inventoryType === InventoryType.PLAYER && !isSlotWithItem(item);
        }

        const dragged = source as DragSource;

        return (
          (dragged.item.slot !== item.slot || dragged.inventory !== inventoryType) &&
          inventoryType !== InventoryType.SHOP &&
          inventoryType !== InventoryType.CRAFTING
        );
      },
    }),
    [inventoryType, item]
  );

  useNuiEvent('refreshSlots', (data: { items?: ItemsPayload | ItemsPayload[] }) => {
    if (!isDragging && !data.items) return;
    if (!Array.isArray(data.items)) return;

    const itemSlot = data.items.find(
      (dataItem) => dataItem.item.slot === item.slot && dataItem.inventory === inventoryId
    );

    if (!itemSlot) return;

    manager.dispatch({ type: 'dnd-core/END_DRAG' });
  });

  const connectRef = (element: HTMLDivElement | null) => {
    if (!element) return;
    drag(drop(element));
  };

  const handleContext = (event: React.MouseEvent<HTMLDivElement>) => {
    event.preventDefault();
    if (inventoryType !== 'player' || !isSlotWithItem(item)) return;

    dispatch(openContextMenu({ item, coords: { x: event.clientX, y: event.clientY } }));
  };

  const handleClick = (event: React.MouseEvent<HTMLDivElement>) => {
    dispatch(closeTooltip());
    if (timerRef.current) clearTimeout(timerRef.current);
    if (event.ctrlKey && isSlotWithItem(item) && inventoryType !== 'shop' && inventoryType !== 'crafting') {
      onDrop({ item: item, inventory: inventoryType });
    } else if (event.altKey && isSlotWithItem(item) && inventoryType === 'player') {
      onUse(item);
    }
  };

  const refs = useMergeRefs([connectRef, ref]);

  const hasItem = isSlotWithItem(item);
  const unavailable =
    !canPurchaseItem(item, { type: inventoryType, groups: inventoryGroups }) || !canCraftItem(item, inventoryType);

  // CSS background-image has no onError, so a missing web/images/<name>.png
  // would otherwise just render as an empty square forever. This probes the
  // same URL separately and swaps to a category/slot icon when it 404s - see
  // useImageAvailable for why that has to be a real network check, not a guess.
  const imageUrl = hasItem ? getItemUrl(item as SlotWithItem) : undefined;
  const imageAvailable = useImageAvailable(imageUrl);
  const appearance = useAppSelector(selectAppearance);

  return (
    <div
      ref={refs}
      onContextMenu={handleContext}
      onClick={handleClick}
      className={hasItem ? 'slot' : 'slot empty'}
      data-over={isOver || undefined}
      data-unavailable={unavailable || undefined}
      style={{
        opacity: isDragging ? 0.4 : 1.0,
        backgroundImage: hasItem && imageAvailable ? `url(${imageUrl})` : undefined,
      }}
    >
      {hasItem && !imageAvailable && (
        <Icon name={getFallbackIcon(item as SlotWithItem, appearance?.catalog)} className="slot-fallback-icon" />
      )}

      {hasItem && (
        <div
          className="item-slot-wrapper"
          onMouseEnter={() => {
            timerRef.current = window.setTimeout(() => {
              dispatch(openTooltip({ item, inventoryType }));
            }, 500) as unknown as number;
          }}
          onMouseLeave={() => {
            dispatch(closeTooltip());
            if (timerRef.current) {
              clearTimeout(timerRef.current);
              timerRef.current = null;
            }
          }}
        >
          {/* Count reads top-right, clear of the durability bar along the bottom.
              Weight moved into the tooltip - two stacked numbers on a 46px tile
              was the noise the reskin set out to remove. */}
          {item.count !== undefined && item.count > 1 && (
            <span className="slot-count">{item.count.toLocaleString('en-us')}</span>
          )}

          {inventoryType === 'shop' && item?.price !== undefined && item.price > 0 && (
            <span className="slot-price">
              {item.currency && item.currency !== 'money' && item.currency !== 'black_money' ? (
                <>
                  <img src={getItemUrl(item.currency)} alt="" />
                  {item.price.toLocaleString('en-us')}
                </>
              ) : (
                <span data-dirty={item.currency === 'black_money' || undefined}>
                  {Locale.$ || '$'}
                  {item.price.toLocaleString('en-us')}
                </span>
              )}
            </span>
          )}

          {inventoryType !== 'shop' && item?.durability !== undefined && (
            <div className="slot-dur">
              <span
                className={item.durability < 25 ? 'low' : undefined}
                style={{ width: `${Math.max(0, Math.min(item.durability, 100))}%` }}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default React.memo(React.forwardRef(InventorySlot));
