import React, { useState, useRef, useEffect } from 'react';
import { useDrop } from 'react-dnd';
import { useAppDispatch, useAppSelector } from '../../store';
import { selectItemAmount, setItemAmount } from '../../store/inventory';
import { DragSource } from '../../typings';
import { onUse } from '../../dnd/onUse';
import { onGive } from '../../dnd/onGive';
import { fetchNui } from '../../utils/fetchNui';
import { Locale } from '../../store/locale';
import UsefulControls from './UsefulControls';
import { Icon } from '../utils/icons/InventoryIcons';

const formatAmount = (n: number) => (n > 0 ? n.toLocaleString('en-US') : '0');
const digitsOnly = (s: string) => s.replace(/\D/g, '');
const countDigitsBefore = (s: string, index: number) => digitsOnly(s.substring(0, index)).length;

/**
 * Bottom action bar.
 *
 * Styled as GTA-style keybind badges rather than buttons, but every badge maps
 * to something that actually exists in this resource - no invented keys:
 *
 *   ALT + LMB    -> onUse            (InventorySlot.handleClick)
 *   CTRL + LMB   -> onDrop, no target (InventorySlot.handleClick)
 *   SHIFT + drag -> half-stack split  (store shiftPressed, read in onDrop)
 *   RMB          -> item context menu (InventorySlot.handleContext)
 *   ESC          -> exit              (useExitListener)
 *
 * USE and GIVE stay react-dnd drop targets exactly as before - you drag an item
 * onto them - so they carry a DRAG badge instead of a key. There is no "Pick Up"
 * key binding on the NUI side, so the mockup's E · Pick Up badge is not here.
 */
const InventoryControl: React.FC = () => {
  const itemAmount = useAppSelector(selectItemAmount);
  const dispatch = useAppDispatch();

  const [infoVisible, setInfoVisible] = useState(false);
  const [value, setValue] = useState(formatAmount(itemAmount));
  const inputRef = useRef<HTMLInputElement>(null);
  const cursorRef = useRef<number | null>(null);

  const [{ overUse }, use] = useDrop<DragSource, void, { overUse: boolean }>(() => ({
    accept: 'SLOT',
    collect: (monitor) => ({ overUse: monitor.isOver() }),
    drop: (source) => {
      source.inventory === 'player' && onUse(source.item);
    },
  }));

  const [{ overGive }, give] = useDrop<DragSource, void, { overGive: boolean }>(() => ({
    accept: 'SLOT',
    collect: (monitor) => ({ overGive: monitor.isOver() }),
    drop: (source) => {
      source.inventory === 'player' && onGive(source.item);
    },
  }));

  const commitValue = (raw: string, cursorIndex: number) => {
    const digitsBefore = countDigitsBefore(raw, cursorIndex);
    const num = parseInt(digitsOnly(raw), 10) || 0;

    setValue(formatAmount(num));
    dispatch(setItemAmount(num));
    cursorRef.current = digitsBefore;
  };

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) =>
    commitValue(event.target.value, event.target.selectionStart ?? 0);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    const el = event.currentTarget;
    const pos = el.selectionStart ?? 0;

    if (pos !== el.selectionEnd) return;

    if (event.key === 'Backspace' && el.value[pos - 1] === ',') {
      event.preventDefault();
      commitValue(el.value.slice(0, pos - 2) + el.value.slice(pos), pos - 2);
    } else if (event.key === 'Delete' && el.value[pos] === ',') {
      event.preventDefault();
      commitValue(el.value.slice(0, pos) + el.value.slice(pos + 2), pos);
    }
  };

  useEffect(() => {
    if (!inputRef.current || cursorRef.current === null) return;
    let newPos = 0;
    let count = 0;

    for (let i = 0; i < value.length && count < cursorRef.current; i++) {
      if (/\d/.test(value[i])) count++;
      newPos++;
    }

    inputRef.current.setSelectionRange(newPos, newPos);
    cursorRef.current = null;
  }, [value]);

  return (
    <>
      <UsefulControls infoVisible={infoVisible} setInfoVisible={setInfoVisible} />

      <div className="frame-bottom panel">
        <div className="action-bar">
          <label className="amount-field" title="Quantity moved per drag - 0 moves the whole stack">
            <span className="t-label">Amount</span>
            <input
              className="amount-input t-num"
              type="text"
              ref={inputRef}
              value={value}
              onChange={handleChange}
              onKeyDown={handleKeyDown}
              min={0}
            />
          </label>

          <div className="action-divider" />

          {/* drop target - drag an item here to use it */}
          <div
            className="action-item"
            data-primary="true"
            data-over={overUse || undefined}
            ref={(el) => {
              use(el);
            }}
          >
            <span className="key">ALT · LMB</span>
            <span className="label">{Locale.ui_use || 'Use'}</span>
          </div>

          <div className="action-divider" />

          {/* drop target - drag an item here to give it to a nearby player */}
          <div
            className="action-item"
            data-over={overGive || undefined}
            ref={(el) => {
              give(el);
            }}
          >
            <span className="key">DRAG</span>
            <span className="label">{Locale.ui_give || 'Give'}</span>
          </div>

          <div className="action-divider" />

          <div className="action-item">
            <span className="key">CTRL · LMB</span>
            <span className="label">{Locale.ui_drop || 'Drop'}</span>
          </div>

          <div className="action-divider" />

          <div className="action-item">
            <span className="key">RMB</span>
            <span className="label">Options</span>
          </div>

          <div className="action-divider" />

          <div className="action-item action-clickable" onClick={() => fetchNui('exit')}>
            <span className="key">ESC</span>
            <span className="label">{Locale.ui_close || 'Close'}</span>
          </div>

          <button
            type="button"
            className="action-info"
            title={Locale.ui_usefulcontrols || 'Useful controls'}
            onClick={() => setInfoVisible(true)}
          >
            <Icon name="info" />
          </button>
        </div>
      </div>
    </>
  );
};

export default InventoryControl;
