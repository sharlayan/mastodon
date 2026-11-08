import { useCallback, useEffect, useRef } from 'react';
import type { MouseEvent, TouchEvent } from 'react';

const LONG_PRESS_MS = 500;
const LONG_PRESS_MOVE_PX = 10;

// Android Chrome reveals the toolbar by itself on a long press, and iOS Safari does not. Nothing else there would
// answer the finger now that the text cannot be selected, so a long press opens it on every browser.
// A picture keeps its browser menu: it is left alone.
export const useLongPressOpensToolbar = () => {
  const press = useRef<{ timer: number; x: number; y: number } | null>(null);
  const longPressedBubble = useRef<HTMLElement | null>(null);
  const touchedControl = useRef<{ element: Element; endedAt?: number } | null>(
    null,
  );

  const cancel = useCallback(() => {
    if (press.current) window.clearTimeout(press.current.timer);
    press.current = null;
  }, []);

  const clearLongPress = useCallback(() => {
    longPressedBubble.current?.removeAttribute('data-chat-long-pressed');
    longPressedBubble.current = null;
  }, []);

  useEffect(
    () => () => {
      cancel();
      clearLongPress();
    },
    [cancel, clearLongPress],
  );

  const inLongPressedToolbar = useCallback((target: Element) => {
    const toolbar = target.closest('.chat-native__actions');
    return Boolean(
      toolbar && longPressedBubble.current?.parentElement?.contains(toolbar),
    );
  }, []);

  const onTouchStart = useCallback(
    (event: TouchEvent<HTMLElement>) => {
      cancel();
      const touch = event.touches[0];
      const target = event.target as Element;
      if (!inLongPressedToolbar(target)) clearLongPress();
      const bubble = target.closest<HTMLElement>('.chat-native__bubble');
      const control = target.closest('button, a[href]');
      touchedControl.current =
        touch &&
        event.touches.length === 1 &&
        bubble &&
        control &&
        bubble.contains(control)
          ? { element: control }
          : null;
      if (
        !touch ||
        event.touches.length > 1 ||
        !bubble ||
        target.closest('.chat-native__gallery, .chat-native__attachment')
      )
        return;

      press.current = {
        x: touch.clientX,
        y: touch.clientY,
        timer: window.setTimeout(() => {
          press.current = null;
          longPressedBubble.current = bubble;
          bubble.setAttribute('data-chat-long-pressed', '');
          bubble.focus({ preventScroll: true });
        }, LONG_PRESS_MS),
      };
    },
    [cancel, clearLongPress, inLongPressedToolbar],
  );

  const onTouchMove = useCallback(
    (event: TouchEvent<HTMLElement>) => {
      const touch = event.touches[0];
      if (
        press.current &&
        touch &&
        Math.hypot(
          touch.clientX - press.current.x,
          touch.clientY - press.current.y,
        ) > LONG_PRESS_MOVE_PX
      ) {
        touchedControl.current = null;
        cancel();
      }
    },
    [cancel],
  );

  const onTouchEnd = useCallback(
    (event: TouchEvent<HTMLElement>) => {
      if (touchedControl.current)
        touchedControl.current.endedAt = event.timeStamp;
      cancel();
    },
    [cancel],
  );
  const onTouchCancel = useCallback(() => {
    touchedControl.current = null;
    cancel();
  }, [cancel]);
  const onMouseDown = useCallback(
    (event: MouseEvent<HTMLElement>) => {
      const touched = touchedControl.current;
      touchedControl.current = null;
      const target = event.target as Element;
      if (inLongPressedToolbar(target)) return;
      if (
        touched?.endedAt === undefined ||
        event.timeStamp - touched.endedAt < 0 ||
        event.timeStamp - touched.endedAt > 1000 ||
        target.closest('button, a[href]') !== touched.element
      ) {
        clearLongPress();
        return;
      }

      // Safari can focus the bubble between a quote's touchend and click. The sticky toolbar then appears over the
      // finger and takes the click. Keep that default focus from moving while allowing the click itself to go through.
      event.preventDefault();
      const active = document.activeElement;
      if (
        active instanceof HTMLElement &&
        active.closest('.chat-native__composer')
      )
        active.blur();
    },
    [clearLongPress, inLongPressedToolbar],
  );

  return {
    onTouchStart,
    onTouchMove,
    onTouchEnd,
    onTouchCancel,
    onMouseDown,
  };
};
