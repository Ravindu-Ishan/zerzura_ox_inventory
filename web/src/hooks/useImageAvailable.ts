import { useEffect, useState } from 'react';

/**
 * Does this image URL actually load?
 *
 * Item art is painted as a CSS `background-image`, not an `<img>` - which
 * means there is no `onError` to hook: a missing background image just
 * renders as nothing, silently, forever. This probes the same URL with a
 * throwaway `Image()` instead, so a slot can tell "no thumbnail for this
 * item" apart from "still loading" and fall back to a category icon instead
 * of a blank square.
 *
 * Module-level cache because the same URL is requested by every slot holding
 * that item - a stack of 12 waters should not fire 12 loads, and once an item
 * is known-good or known-missing that answer never changes for the session.
 */
const cache = new Map<string, boolean>();

/** @returns true (assume available) until proven otherwise, so a slot never
 *  flashes a fallback icon before the real thumbnail has had a chance to load. */
export const useImageAvailable = (url: string | undefined): boolean => {
  const [available, setAvailable] = useState(() => (url ? (cache.get(url) ?? true) : true));

  useEffect(() => {
    if (!url) {
      setAvailable(true);
      return;
    }

    const cached = cache.get(url);

    if (cached !== undefined) {
      setAvailable(cached);
      return;
    }

    let cancelled = false;
    const image = new Image();

    image.onload = () => {
      cache.set(url, true);
      if (!cancelled) setAvailable(true);
    };
    image.onerror = () => {
      cache.set(url, false);
      if (!cancelled) setAvailable(false);
    };
    image.src = url;

    return () => {
      cancelled = true;
    };
  }, [url]);

  return available;
};
