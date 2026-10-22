import { useCallback, useEffect, useRef, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { CaretRightIcon } from '@phosphor-icons/react';

import { useAccount } from '@/flavours/glitch/hooks/useAccount';
import { useResizeObserver } from '@/flavours/glitch/hooks/useObserver';
import type {
  ExpandedStatusShape,
  StatusShape,
} from '@/flavours/glitch/models/status';
import { useSharlayanEmojiInfoTooltip } from '@/flavours/glitch/sharlayan/emoji_info_tooltip';
import {
  catSpeakVisibleFor,
  nyaifyHtml,
} from '@/flavours/glitch/sharlayan/nyaify';
import { useRedesignMfmContent } from '@/flavours/glitch/sharlayan/status_redesign_content';
import { useAppSelector } from '@/flavours/glitch/store';

import { Button } from '../button/redesign';
import { EmojiHTML } from '../emoji/html';

import classes from './content.module.scss';
import { useHandlersForStatus } from './hooks';

const MAX_LINES = 35;

export const StatusContent: React.FC<
  {
    status: StatusShape | ExpandedStatusShape;
    statusContent?: string;
    onTranslate?: () => void;
    onReadMore?: () => void;
    collapsible?: boolean;
    postCollapsed?: boolean;
    onTogglePostCollapse?: () => void;
    onMeasureContent?: (height: number) => void;
  } & React.ComponentPropsWithRef<'div'>
> = ({
  status,
  statusContent,
  onTranslate,
  onReadMore,
  collapsible,
  postCollapsed = false,
  onTogglePostCollapse,
  onMeasureContent,
  children,
  className,
  onClick,
  ...props
}) => {
  const { setContainerElement, tooltip } = useSharlayanEmojiInfoTooltip();
  const contentBodyRef = useRef<HTMLDivElement | null>(null);
  const collapseEnabled = useAppSelector(
    (state) =>
      state.local_settings.getIn(['collapsed', 'enabled'], false) as boolean,
  );
  // Determines if a long post should show the read more button.
  const [collapsed, setCollapsed] = useState(false);
  const onResize: ResizeObserverCallback = useCallback(
    (entries) => {
      for (const { target } of entries) {
        setCollapsed(isElementOverflowing(target));
        onMeasureContent?.(target.clientHeight);
      }
    },
    [onMeasureContent],
  );
  const observer = useResizeObserver(onResize);
  const onRef = useCallback(
    (node: HTMLDivElement | null) => {
      contentBodyRef.current = node;
      if (!node) {
        return;
      }

      observer.observe(node);
      setCollapsed(isElementOverflowing(node));
      onMeasureContent?.(node.clientHeight);
    },
    [observer, onMeasureContent],
  );
  useEffect(() => {
    if (postCollapsed) {
      contentBodyRef.current
        ?.querySelectorAll<HTMLMediaElement>('video, audio')
        .forEach((media) => {
          media.pause();
        });
    }
  }, [postCollapsed, children]);
  const handleMediaPlay = useCallback(
    (event: React.SyntheticEvent<HTMLDivElement>) => {
      if (postCollapsed && event.target instanceof HTMLMediaElement)
        event.target.pause();
    },
    [postCollapsed],
  );

  const htmlHandlers = useHandlersForStatus(status);

  const accountInStore = useAccount(
    typeof status.account === 'string' ? status.account : undefined,
  );
  const account =
    typeof status.account === 'string' ? accountInStore : status.account;
  const originalText =
    statusContent ?? status.translation?.contentHtml ?? status.contentHtml;
  const text = catSpeakVisibleFor(account?.acct, account?.is_cat)
    ? nyaifyHtml(originalText)
    : originalText;
  const language = status.translation?.language ?? status.language;
  const mfmContent = useRedesignMfmContent(status, text);

  const isCollapsed =
    !collapseEnabled && !!onReadMore && collapsible && collapsed;
  const handleClick: React.MouseEventHandler<HTMLDivElement> = useCallback(
    (event) => {
      if (
        collapseEnabled &&
        onTogglePostCollapse &&
        event.button === 0 &&
        !event.ctrlKey &&
        !event.metaKey &&
        (postCollapsed || event.shiftKey) &&
        !(
          event.target instanceof Element &&
          event.target.closest('a, button, summary')
        ) &&
        window.getSelection()?.type !== 'Range'
      ) {
        event.preventDefault();
        event.stopPropagation();
        onTogglePostCollapse();
        return;
      }
      onClick?.(event);
    },
    [collapseEnabled, onTogglePostCollapse, postCollapsed, onClick],
  );

  const style = {
    '--max-height': `${MAX_LINES}lh`,
    ...props.style,
  } as React.CSSProperties;

  return (
    <>
      <div
        {...props}
        className={classNames(
          className,
          classes.content,
          isCollapsed && classes.collapsed,
          postCollapsed && classes.postCollapsed,
        )}
        style={style}
        ref={setContainerElement}
        onClick={handleClick}
        role='presentation'
      >
        <div
          className={classes.contentBody}
          ref={onRef}
          inert={postCollapsed}
          onPlayCapture={handleMediaPlay}
        >
          {mfmContent ? (
            <div
              className={classNames(classes.contentText, 'translate')}
              lang={language}
            >
              {mfmContent}
            </div>
          ) : (
            text.trim().length > 0 && (
              <EmojiHTML
                className={classNames(classes.contentText, 'translate')}
                lang={language}
                htmlString={text}
                extraEmojis={status.emojis}
                {...htmlHandlers}
              />
            )
          )}

          {children}
        </div>
      </div>

      {tooltip}

      {isCollapsed && (
        <Button
          size='sm'
          onClick={onReadMore}
          trailingIcon={CaretRightIcon}
          className={classes.contentReadMore}
        >
          <FormattedMessage
            id='status.view_post'
            defaultMessage='View full post'
          />
        </Button>
      )}
    </>
  );
};

function isElementOverflowing(node: Element) {
  const { lineHeight } = getComputedStyle(node);
  const lineHeightPx = parseFloat(lineHeight);
  const maxHeight = lineHeightPx * MAX_LINES;

  return node.clientHeight > maxHeight || node.scrollWidth > node.clientWidth;
}
