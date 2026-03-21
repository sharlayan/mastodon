import type { RefObject, FC } from 'react';
import type React from 'react';
import { useState, useEffect, useCallback } from 'react';

import Overlay from 'react-overlays/Overlay';

interface EmojiInfoTooltipProps {
  containerRef: RefObject<HTMLElement>;
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
    <Overlay
      show={hovered}
      offset={[0, 5]}
      placement={isAboveCenter(img) ? 'bottom' : 'top'}
      flip
      target={emojiElement}
      popperConfig={{ strategy: 'fixed' }}
    >
      {({
        props,
        placement,
      }: {
        props: React.HTMLAttributes<HTMLDivElement>;
        placement: string;
      }) => (
        <div className='emoji-magnify-overlay' {...props}>
          <div className={`dropdown-animation ${placement}`}>
            <div className='reactions-bar__item__users'>
              <div className='reactions-bar__item__users__emoji'>
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
            </div>
          </div>
        </div>
      )}
    </Overlay>
  );
};
