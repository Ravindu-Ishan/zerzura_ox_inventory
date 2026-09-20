import React from 'react';

/**
 * Filled icon sprite for the inventory HUD.
 *
 * Ported from design-mock/index-polish.html. Two deliberate decisions carried over
 * from the mockup:
 *
 *  1. FILLED glyphs, not stroke/outline ones. This overrides the stroke-only icon
 *     convention used by the character-creator NUI: at ~46px inside a busy item grid
 *     a 1.5px stroke icon visually disappears, a filled silhouette does not.
 *  2. Inline SVG paths in the bundle, never a hosted icon font. There is no live
 *     network once this page runs as FiveM NUI, so anything fetched at runtime
 *     silently fails in-game while working fine in the browser.
 *
 * Knockout details inside a glyph paint `var(--icon-bg)` rather than a fixed colour,
 * so the cut-outs match whatever surface the icon sits on (tile, active tab, selected
 * slot). Every container that renders an icon sets --icon-bg in index.scss.
 */

export type InventoryIconName =
  | 'grid'
  | 'search'
  | 'drop'
  | 'cube'
  | 'droplet'
  | 'pistol'
  | 'head'
  | 'mask'
  | 'jacket'
  | 'armor'
  | 'legs'
  | 'boots'
  | 'info'
  | 'close';

const bg: React.CSSProperties = { fill: 'var(--icon-bg)' };

export const InventoryIconSprite: React.FC = () => (
  <svg className="icon-defs" aria-hidden="true" focusable="false">
    <defs>
      {/* ui / category */}
      <symbol id="i-grid" viewBox="0 0 24 24" fill="currentColor">
        <rect x="3" y="3" width="7.5" height="7.5" />
        <rect x="13.5" y="3" width="7.5" height="7.5" />
        <rect x="3" y="13.5" width="7.5" height="7.5" />
        <rect x="13.5" y="13.5" width="7.5" height="7.5" />
      </symbol>
      <symbol id="i-search" viewBox="0 0 24 24" fill="currentColor">
        <path
          fillRule="evenodd"
          d="M10.5 3.5a7 7 0 1 0 4.5 12.4l4.8 4.8 1.4-1.4-4.8-4.8a7 7 0 0 0-5.9-11Zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10Z"
        />
      </symbol>
      <symbol id="i-drop" viewBox="0 0 24 24" fill="currentColor">
        <path d="M10.4 2.6h3.2v8.6h4.4L12 18.2 6 11.2h4.4Z" />
        <rect x="3.6" y="19.6" width="16.8" height="2" />
      </symbol>
      <symbol id="i-cube" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2 21.5 7.1v9.8L12 22 2.5 16.9V7.1Z" />
        <path style={bg} d="M12 12.1 21.5 7.1v1.7L12.9 13.4v8.1h-1.8v-8.1L2.5 8.8V7.1Z" />
      </symbol>
      <symbol id="i-droplet" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2.4s7.4 8 7.4 12A7.4 7.4 0 1 1 4.6 14.4c0-4 7.4-12 7.4-12Z" />
        <path style={bg} d="M12 18.6a4.2 4.2 0 0 1-4.2-4.2h1.8A2.4 2.4 0 0 0 12 16.8Z" />
      </symbol>
      <symbol id="i-pistol" viewBox="0 0 24 24" fill="currentColor">
        <path d="M2 6.2h20v4.6h-4.1l-.7 2H13l-1.5 8.6H7.1l1.5-8.6H4.4A2.4 2.4 0 0 1 2 9.8Z" />
      </symbol>

      {/* appearance */}
      <symbol id="i-head" viewBox="0 0 24 24" fill="currentColor">
        <circle cx="12" cy="7.6" r="4.2" />
        <path d="M3.6 21.4c0-4.6 3.8-7.6 8.4-7.6s8.4 3 8.4 7.6v.2H3.6Z" />
      </symbol>
      <symbol id="i-mask" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2.6c4.2 0 7.3 3.4 7.3 7.6 0 2.7-1 4.2-1 6.6 0 1.8-1.6 2.6-3.1 2.6H8.8c-1.5 0-3.1-.8-3.1-2.6 0-2.4-1-3.9-1-6.6C4.7 6 7.8 2.6 12 2.6Z" />
        <ellipse style={bg} cx="9.3" cy="11.4" rx="1.4" ry="1.7" />
        <ellipse style={bg} cx="14.7" cy="11.4" rx="1.4" ry="1.7" />
        <rect style={bg} x="10" y="15.6" width="4" height="1.4" />
      </symbol>
      <symbol id="i-jacket" viewBox="0 0 24 24" fill="currentColor">
        <path d="M8.3 2.6 3.6 6.7l2.8 3.2 1.5-1V21.4h8.2V8.9l1.5 1 2.8-3.2-4.7-4.1c-.9 1.4-2.2 2.2-3.7 2.2S9.2 4 8.3 2.6Z" />
        <rect style={bg} x="11.4" y="8.6" width="1.2" height="12.8" />
      </symbol>
      <symbol id="i-armor" viewBox="0 0 24 24" fill="currentColor">
        <path d="M8 2.6 3.6 4.8l1.1 5.1-2.1 1.1 1.1 10.4h16.6l1.1-10.4-2.1-1.1 1.1-5.1-4.4-2.2L12 4.8Z" />
        <rect style={bg} x="9.8" y="8.8" width="4.4" height="4.4" />
      </symbol>
      <symbol id="i-legs" viewBox="0 0 24 24" fill="currentColor">
        <path d="M6.4 2.4h11.2l.9 19.2h-5L12 11.8l-1.5 9.8h-5Z" />
        <rect style={bg} x="6.5" y="6.2" width="11" height="1.4" />
      </symbol>
      <symbol id="i-boots" viewBox="0 0 24 24" fill="currentColor">
        <path d="M5.4 2.4h5.4v10.6h4.4a4.8 4.8 0 0 1 4.8 4.8v2H5.4Z" />
        <rect x="3.6" y="19.8" width="17.8" height="2.2" />
        <rect style={bg} x="5.5" y="12.4" width="5.2" height="1.3" />
      </symbol>

      {/* chrome */}
      <symbol id="i-info" viewBox="0 0 24 24" fill="currentColor">
        <path
          fillRule="evenodd"
          d="M12 1.8a10.2 10.2 0 1 0 0 20.4 10.2 10.2 0 0 0 0-20.4Zm-1.5 8.1h3.3v7.2h-3.3Zm1.6-4.6a1.9 1.9 0 1 1 0 3.8 1.9 1.9 0 0 1 0-3.8Z"
        />
      </symbol>
      <symbol id="i-close" viewBox="0 0 24 24" fill="currentColor">
        <path d="M5.1 3.3 3.3 5.1 10.2 12l-6.9 6.9 1.8 1.8L12 13.8l6.9 6.9 1.8-1.8L13.8 12l6.9-6.9-1.8-1.8L12 10.2Z" />
      </symbol>
    </defs>
  </svg>
);

/** Renders one glyph from the sprite. Size/colour come from CSS. */
export const Icon: React.FC<{ name: InventoryIconName; className?: string }> = ({ name, className }) => (
  <svg className={className} aria-hidden="true" focusable="false">
    <use href={`#i-${name}`} />
  </svg>
);

export default Icon;
