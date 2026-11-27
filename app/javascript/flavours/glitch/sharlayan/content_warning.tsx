import type { MouseEventHandler } from 'react';
import { useCallback, useId, useRef } from 'react';

import { FormattedMessage } from 'react-intl';

import { AnimateEmojiProvider } from '@/flavours/glitch/components/emoji/context';
import { EmojiHTML } from '@/flavours/glitch/components/emoji/html';
import { useStatus } from '@/flavours/glitch/hooks/useStatus';

const stopPropagation: MouseEventHandler = (e) => {
  e.stopPropagation();
};

export const ContentWarning: React.FC<{
  statusId: string;
  expanded?: boolean;
  onClick?: () => void;
}> = ({ statusId, expanded, onClick }) => {
  const status = useStatus(statusId);
  const descriptionId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const forwardClick = useCallback<MouseEventHandler>((e) => {
    if (
      buttonRef.current &&
      e.target !== buttonRef.current &&
      !buttonRef.current.contains(e.target as Node)
    ) {
      buttonRef.current.click();
      buttonRef.current.focus();
    }
  }, []);

  const text = status?.translation?.spoilerHtml ?? status?.spoilerHtml;
  if (!status?.spoiler_text || !text) {
    return null;
  }

  return (
    <AnimateEmojiProvider
      className='content-warning'
      onClick={forwardClick}
      onMouseUp={stopPropagation}
    >
      <p id={descriptionId}>
        <EmojiHTML as='span' htmlString={text} extraEmojis={status.emojis} />
      </p>

      <button
        ref={buttonRef}
        type='button'
        className='link-button'
        onClick={onClick}
        aria-describedby={descriptionId}
      >
        {expanded ? (
          <FormattedMessage
            id='content_warning.hide'
            defaultMessage='Hide post'
          />
        ) : (
          <FormattedMessage
            id='content_warning.show_more'
            defaultMessage='Show more'
          />
        )}
      </button>
    </AnimateEmojiProvider>
  );
};
