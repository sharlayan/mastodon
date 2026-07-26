import { useCallback, useMemo, useRef, useState } from 'react';
import type { FC, HTMLAttributes } from 'react';

import classNames from 'classnames';

import type { AnimatedProps } from '@react-spring/web';
import { animated, useTransition } from '@react-spring/web';

import {
  addBoardAnnouncementReaction,
  removeBoardAnnouncementReaction,
} from '@/flavours/glitch/actions/board_announcements';
import type { ApiBoardAnnouncementReactionJSON } from '@/flavours/glitch/api_types/board_announcements';
import { AnimatedNumber } from '@/flavours/glitch/components/animated_number';
import { Emoji } from '@/flavours/glitch/components/emoji';
import {
  AnimateEmojiProvider,
  LocalCustomEmojiProvider,
} from '@/flavours/glitch/components/emoji/context';
import { EmojiReactionOverlay } from '@/flavours/glitch/components/emoji_info_tooltip';
import { Icon } from '@/flavours/glitch/components/icon';
import EmojiPickerDropdown from '@/flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import { isUnicodeEmoji } from '@/flavours/glitch/features/emoji/utils';
import { autoPlayGif } from '@/flavours/glitch/initial_state';
import { useAppDispatch } from '@/flavours/glitch/store';
import AddIcon from '@/material-icons/400-24px/add.svg?react';

export const ReactionsBar: FC<{
  reactions: ApiBoardAnnouncementReactionJSON[];
  id: string;
}> = ({ reactions, id }) => {
  const visibleReactions = useMemo(
    () => reactions.filter((x) => x.count > 0),
    [reactions],
  );

  const dispatch = useAppDispatch();
  const handleEmojiPick = useCallback(
    (emoji: { native: string }) => {
      void dispatch(
        addBoardAnnouncementReaction({
          id,
          name: emoji.native.replaceAll(/:/g, ''),
        }),
      );
    },
    [dispatch, id],
  );

  const transitions = useTransition(visibleReactions, {
    from: {
      scale: 0,
    },
    enter: {
      scale: 1,
    },
    leave: {
      scale: 0,
    },
    keys: visibleReactions.map((x) => x.name),
  });

  return (
    <LocalCustomEmojiProvider>
      <AnimateEmojiProvider
        className={classNames('reactions-bar', {
          'reactions-bar--empty': visibleReactions.length === 0,
        })}
      >
        {transitions(({ scale }, reaction) => (
          <Reaction
            key={reaction.name}
            reaction={reaction}
            style={{ transform: scale.to((s) => `scale(${s})`) }}
            id={id}
          />
        ))}

        {visibleReactions.length < 8 && (
          <EmojiPickerDropdown
            onPickEmoji={handleEmojiPick}
            button={<Icon id='plus' icon={AddIcon} />}
          />
        )}
      </AnimateEmojiProvider>
    </LocalCustomEmojiProvider>
  );
};

const Reaction: FC<{
  reaction: ApiBoardAnnouncementReactionJSON;
  id: string;
  style: AnimatedProps<HTMLAttributes<HTMLButtonElement>>['style'];
}> = ({ id, reaction, style }) => {
  const dispatch = useAppDispatch();
  const [hovered, setHovered] = useState(false);
  const targetRef = useRef<HTMLButtonElement>(null);

  const handleClick = useCallback(() => {
    if (reaction.me) {
      void dispatch(
        removeBoardAnnouncementReaction({ id, name: reaction.name }),
      );
    } else {
      void dispatch(addBoardAnnouncementReaction({ id, name: reaction.name }));
    }
  }, [dispatch, id, reaction.me, reaction.name]);

  const handleMouseEnter = useCallback(() => {
    setHovered(true);
  }, []);
  const handleMouseLeave = useCallback(() => {
    setHovered(false);
  }, []);
  const getTarget = useCallback(() => targetRef.current, []);

  const isCustom = !isUnicodeEmoji(reaction.name) && !!reaction.url;
  const shortCode = `:${reaction.name}:`;
  const fallbackCode = isUnicodeEmoji(reaction.name)
    ? reaction.name
    : shortCode;
  const customSrc =
    autoPlayGif || hovered
      ? reaction.url
      : (reaction.static_url ?? reaction.url);

  return (
    <>
      <animated.button
        className={classNames('reactions-bar__item', {
          active: reaction.me,
        })}
        onClick={handleClick}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        ref={targetRef}
        style={style}
      >
        <span className='reactions-bar__item__emoji'>
          {isCustom ? (
            <img
              draggable='false'
              className={`emojione custom-emoji${reaction.is_sensitive ? ' sensitive-custom-emoji' : ''}`}
              alt={shortCode}
              src={customSrc}
            />
          ) : (
            <Emoji code={fallbackCode} />
          )}
        </span>
        <span className='reactions-bar__item__count'>
          <AnimatedNumber value={reaction.count} />
        </span>
      </animated.button>
      {isCustom && customSrc && (
        <EmojiReactionOverlay
          show={hovered}
          target={getTarget}
          emojiUrl={customSrc}
          shortCode={shortCode}
          placement='bottom'
        />
      )}
    </>
  );
};
