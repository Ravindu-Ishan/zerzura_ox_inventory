import { fetchNui } from '../utils/fetchNui';
import { onUse } from './onUse';
import { AppearanceSlotKey } from '../typings';

/**
 * ---------------------------------------------------------------------------
 * The two ways the Appearance card talks to the game, and nothing else.
 * ---------------------------------------------------------------------------
 * Both of these are INPUT METHODS on top of paths that already existed and were
 * already reviewed. Neither adds a way to create or destroy an item:
 *
 *  - equipFromSlot is literally onUse. Dropping a garment on its tile sends the
 *    same `useItem` NUI message that right-click -> Use sends, so it lands in
 *    modules/items/client.lua's clothing handler, runs the full
 *    `ox_inventory:useItem` server validation, and only then reaches
 *    ClothingClient.equip -> the `ox_inventory:clothing:equip` callback. The
 *    drag decides WHICH slot is used, not what happens to it.
 *
 *  - unequipSlot is the same `unequipClothing` NUI callback the card has always
 *    fired, which calls ClothingClient.unequip -> the
 *    `ox_inventory:clothing:unequip` callback. The only new thing crossing is
 *    an optional destination slot, which the server range-checks and treats as
 *    a hint to AddItem.
 *
 * Nothing here is optimistic. No redux state is mutated, no tile is repainted:
 * the client applies a change only after the server has confirmed the item
 * moved, and pushes a fresh `setAppearance` either way.
 */

/**
 * Equip the garment sitting in `slot` of the player's inventory.
 *
 * @param slot inventory slot number the drag started from
 */
export const equipFromSlot = (slot: number) => {
  onUse({ slot });
};

/**
 * Take off whatever is worn on `key`, returning the item to the bag.
 *
 * @param key  the Appearance tile
 * @param slot the inventory square the tile was dropped on, if any. A
 *             preference only - the server ignores it when that square is
 *             already occupied, exactly as a normal drop would.
 */
export const unequipSlot = (key: AppearanceSlotKey, slot?: number) => {
  fetchNui('unequipClothing', { key, slot });
};
