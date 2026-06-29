import type { RefObject, FC, ReactNode } from 'react';
import { useState, useEffect, useCallback } from 'react';

import { Popover } from '@/flavours/glitch/components/popover';

const noop = () => undefined;

interface EmojiReactionOverlayProps {
  show: boolean;
  target: HTMLElement | (() => HTMLElement | null) | null;
  emojiUrl: string;
  shortCode: string;
  placement?: 'top' | 'bottom';
  emojiClassName?: string;
  children?: ReactNode;
}

export const EmojiReactionOverlay: FC<EmojiReactionOverlayProps> = ({
  show,
  target,
  emojiUrl,
  shortCode,
  placement = 'bottom',
  emojiClassName,
  children,
}) => {
  const resolvedTarget = typeof target === 'function' ? target() : target;

  if (!show || !resolvedTarget) {
    return null;
  }

  return (
    <Popover
      isOpen={show}
      reference={resolvedTarget}
      offset={5}
      placement={placement}
      onClose={noop}
      closeOnClickOutside={false}
    >
      {({ props, placement: currentPlacement }) => (
        <div className='emoji-magnify-overlay' {...props}>
          <div className={`dropdown-animation ${currentPlacement}`}>
            <div className='reactions-bar__item__users'>
              <div
                className={
                  emojiClassName ?? 'reactions-bar__item__users__emoji'
                }
              >
                <span>
                  <img
                    src={emojiUrl}
                    alt={shortCode}
                    className='emojione custom-emoji'
                    loading='lazy'
                  />
                </span>
                <span className='reactions-bar__item__users__emoji__code'>
                  {shortCode}
                </span>
              </div>
              {children}
            </div>
          </div>
        </div>
      )}
    </Popover>
  );
};

interface EmojiInfoTooltipProps {
  containerRef: RefObject<HTMLElement | null>;
  enabled?: boolean;
  callPosition?: string;
}

export const EmojiInfoTooltip: FC<EmojiInfoTooltipProps> = ({
  containerRef,
  enabled = true,
}) => {
  const [hovered, setHovered] = useState<boolean>(false);
  const [emojiElement, setEmojiElement] = useState<HTMLElement | null>(null);

  const handleEmojiEnter = useCallback((event: Event): void => {
    const target = event.currentTarget as HTMLElement;
    setHovered(true);
    setEmojiElement(target);
  }, []);

  const handleEmojiLeave = useCallback((): void => {
    setHovered(false);
    setEmojiElement(null);
  }, []);

  const attachEmojiListeners = useCallback((): void => {
    const container = containerRef.current;
    if (!container) return;

    const customEmojis = container.querySelectorAll<HTMLElement>(
      '.emojione.custom-emoji',
    );
    customEmojis.forEach((el) => {
      el.addEventListener('mouseenter', handleEmojiEnter);
      el.addEventListener('mouseleave', handleEmojiLeave);
      el.removeAttribute('title');
    });
  }, [containerRef, handleEmojiEnter, handleEmojiLeave]);

  const detachEmojiListeners = useCallback((): void => {
    const container = containerRef.current;
    if (!container) return;

    const customEmojis = container.querySelectorAll<HTMLElement>(
      '.emojione.custom-emoji',
    );
    customEmojis.forEach((el) => {
      el.removeEventListener('mouseenter', handleEmojiEnter);
      el.removeEventListener('mouseleave', handleEmojiLeave);
    });
  }, [containerRef, handleEmojiEnter, handleEmojiLeave]);

  useEffect(() => {
    if (!enabled) return;

    attachEmojiListeners();

    const container = containerRef.current;
    if (!container) return;

    const observer = new MutationObserver(() => {
      detachEmojiListeners();
      attachEmojiListeners();
    });

    observer.observe(container, {
      childList: true,
      subtree: true,
    });

    return () => {
      observer.disconnect();
      detachEmojiListeners();
    };
  }, [enabled, attachEmojiListeners, detachEmojiListeners, containerRef]);

  const isAboveCenter = (element: HTMLElement | null): boolean => {
    if (!element) return false;

    const rect = element.getBoundingClientRect();
    const viewportHeight =
      window.innerHeight || document.documentElement.clientHeight;
    const elementMiddle = rect.top + rect.height / 2;
    const viewportMiddle = viewportHeight / 2;

    return elementMiddle < viewportMiddle;
  };

  if (!hovered || !emojiElement) {
    return null;
  }

  const img = emojiElement;
  const shortCode = img.getAttribute('alt') ?? '';
  const emojiUrl = img.getAttribute('src') ?? '';

  return (
    <EmojiReactionOverlay
      show={hovered}
      target={emojiElement}
      emojiUrl={emojiUrl}
      shortCode={shortCode}
      placement={isAboveCenter(img) ? 'bottom' : 'top'}
    />
  );
};
