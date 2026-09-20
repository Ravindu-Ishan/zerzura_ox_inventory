import React from 'react';

/**
 * The single capacity readout for an inventory.
 *
 * Deliberately ONE bar per inventory, showing weight and slot count together:
 * an inventory has exactly one capacity pool, so splitting it into per-section
 * numbers (a separate "Pockets" and "Backpack" allowance) would be inventing
 * limits the server does not enforce.
 *
 * Weights arrive from Lua in grams.
 */
const CapacityBar: React.FC<{
  weight: number;
  maxWeight?: number;
  usedSlots: number;
  totalSlots: number;
}> = ({ weight, maxWeight, usedSlots, totalSlots }) => {
  const percent = maxWeight ? Math.min((weight / maxWeight) * 100, 100) : 0;
  const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);

  return (
    <div className="capacity">
      <div className="capacity-row">
        <span className="t-label">Capacity</span>
        <span className="cap-slots t-num">
          {pad(usedSlots)} / {totalSlots} slots
        </span>
        {maxWeight !== undefined && maxWeight > 0 && (
          <span className="cap-weight t-num">
            <b>{(weight / 1000).toFixed(1)}</b> / {(maxWeight / 1000).toFixed(1)} kg
          </span>
        )}
      </div>
      <div className="capacity-track">
        <span
          className="capacity-fill"
          data-level={percent >= 95 ? 'full' : undefined}
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  );
};

export default React.memo(CapacityBar);
