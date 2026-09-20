import { Inventory, SlotWithItem } from '../../typings';
import React, { useMemo } from 'react';
import { Items } from '../../store/items';
import { Locale } from '../../store/locale';
import { useAppSelector } from '../../store';
import ClockIcon from '../utils/icons/ClockIcon';
import { getItemUrl } from '../../helpers';
import Markdown from '../utils/Markdown';
import { getItemCategory } from '../../helpers/categories';

const CATEGORY_LABEL: Record<string, string> = {
  weapons: 'Weapon',
  clothing: 'Clothing',
  consumables: 'Consumable',
  misc: 'Item',
};

const formatWeight = (weight: number) =>
  weight >= 1000 ? `${(weight / 1000).toLocaleString('en-us', { minimumFractionDigits: 2 })} kg` : `${weight} g`;

const SlotTooltip: React.ForwardRefRenderFunction<
  HTMLDivElement,
  { item: SlotWithItem; inventoryType: Inventory['type']; style: React.CSSProperties }
> = ({ item, inventoryType, style }, ref) => {
  const additionalMetadata = useAppSelector((state) => state.inventory.additionalMetadata);
  const itemData = useMemo(() => Items[item.name], [item]);
  const ingredients = useMemo(() => {
    if (!item.ingredients) return null;
    return Object.entries(item.ingredients).sort((a, b) => a[1] - b[1]);
  }, [item]);

  const description = item.metadata?.description || itemData?.description;
  const ammoName = itemData?.ammoName && Items[itemData.ammoName]?.label;
  const isCrafting = inventoryType === 'crafting';

  // The eyebrow prefers whatever the item's own metadata says; the derived
  // category is only a fallback (see helpers/categories.ts on how coarse it is).
  const eyebrow = item.metadata?.type || CATEGORY_LABEL[getItemCategory(item.name)] || 'Item';

  if (!itemData) {
    return (
      <div className="panel tooltip-wrapper" ref={ref} style={style}>
        <div className="band tip-head">
          <h3 className="t-display">{item.name}</h3>
        </div>
        <div className="band-underline thin" />
      </div>
    );
  }

  const stats: { key: string; value: React.ReactNode }[] = [];

  if (!isCrafting) {
    if (item.weight !== undefined && item.weight > 0) stats.push({ key: 'Weight', value: formatWeight(item.weight) });
    if (item.metadata?.ammo !== undefined) stats.push({ key: Locale.ui_ammo || 'Ammo', value: item.metadata.ammo });
    if (ammoName) stats.push({ key: Locale.ammo_type || 'Ammo type', value: ammoName });
    if (item.metadata?.serial) stats.push({ key: Locale.ui_serial || 'Serial', value: item.metadata.serial });
    if (item.metadata?.weapontint) stats.push({ key: Locale.ui_tint || 'Tint', value: item.metadata.weapontint });
    if (item.metadata?.components && item.metadata.components[0])
      stats.push({
        key: Locale.ui_components || 'Components',
        value: item.metadata.components.map((c: string) => Items[c]?.label || c).join(', '),
      });

    for (const data of additionalMetadata) {
      if (item.metadata && item.metadata[data.metadata])
        stats.push({ key: data.value, value: item.metadata[data.metadata] });
    }
  }

  return (
    <div style={style} className="panel tooltip-wrapper" ref={ref}>
      <div className="band tip-head">
        <span className="t-eyebrow">{eyebrow}</span>
        <h3 className="t-display">{item.metadata?.label || itemData.label || item.name}</h3>
      </div>
      <div className="band-underline thin" />

      {description && (
        <div className="tip-description">
          <Markdown content={description} className="tooltip-markdown" />
        </div>
      )}

      {(stats.length > 0 || !isCrafting) && (
        <div className="tip-body">
          <div className="tip-art" style={{ backgroundImage: `url(${getItemUrl(item)})` }} />
          <dl className="tip-stats">
            {isCrafting && (
              <div>
                <dt>Duration</dt>
                <dd className="t-num tooltip-crafting-duration">
                  <ClockIcon />
                  {(item.duration !== undefined ? item.duration : 3000) / 1000}s
                </dd>
              </div>
            )}
            {stats.map((stat, index) => (
              <div key={`tip-stat-${index}`}>
                <dt>{stat.key}</dt>
                <dd className="t-num">{stat.value}</dd>
              </div>
            ))}
          </dl>
        </div>
      )}

      {isCrafting && ingredients && (
        <div className="tip-ingredients">
          {ingredients.map((ingredient) => {
            const [name, count] = [ingredient[0], ingredient[1]];
            return (
              <div className="tip-ingredient" key={`ingredient-${name}`}>
                <span className="tip-ingredient-art" style={{ backgroundImage: `url(${getItemUrl(name)})` }} />
                <p>
                  {count >= 1
                    ? `${count}x ${Items[name]?.label || name}`
                    : count === 0
                      ? `${Items[name]?.label || name}`
                      : `${count * 100}% ${Items[name]?.label || name}`}
                </p>
              </div>
            );
          })}
        </div>
      )}

      {!isCrafting && item.durability !== undefined && (
        <div className="tip-dur">
          <div className="capacity-row">
            <span className="t-label">{Locale.ui_durability || 'Condition'}</span>
            <span className="cap-weight t-num">
              <b>{Math.trunc(item.durability)}</b>%
            </span>
          </div>
          <div className="capacity-track">
            <span
              className="capacity-fill"
              data-level={item.durability < 25 ? 'full' : undefined}
              style={{ width: `${Math.max(0, Math.min(item.durability, 100))}%` }}
            />
          </div>
        </div>
      )}
    </div>
  );
};

export default React.forwardRef(SlotTooltip);
