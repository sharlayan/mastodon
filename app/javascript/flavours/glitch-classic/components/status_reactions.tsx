import type { FC } from 'react';
import { useState, useCallback, useRef } from 'react';

import classNames from 'classnames';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { unicodeHexToUrl } from '../features/emoji/normalize';
import { emojiToUnicodeHex } from '../features/emoji/utils';
import { useIdentity } from '../identity_context';
import {
  autoPlayGif,
  reactionCustomEmojiSize,
  reactionLocalEmojiOnly,
} from '../initial_state';
import { useAppSelector } from '../store';
import { assetHost } from '../utils/config';
import { isCustomEmojiMuted } from '../utils/custom_emoji_mutes';

import { AnimatedNumber } from './animated_number';
import { Avatar } from './avatar';
import { DisplayName } from './display_name';
import { EmojiReactionOverlay } from './emoji_info_tooltip';

type ReactionUser = ImmutableMap<string, string>;
type ReactionMap = ImmutableMap<
  string,
  string | number | boolean | ImmutableList<ReactionUser>
>;

interface StatusReactionsProps {
  statusId: string;
  reactions: ImmutableList<ReactionMap>;
  numVisible?: number;
  addReaction?: (statusId: string, name: string) => void;
  removeReaction?: (statusId: string, name: string) => void;
  canReact: boolean;
}

function unicodeEmojiUrl(emoji: string): string {
  return unicodeHexToUrl({ unicodeHex: emojiToUnicodeHex(emoji), assetHost });
}

const Emoji: FC<{
  emoji: string;
  hovered: boolean;
  url?: string;
  staticUrl?: string;
  isSensitive?: boolean;
}> = ({ emoji, hovered, url, staticUrl, isSensitive }) => {
  if (!url) {
    return (
      <img
        draggable='false'
        className='emojione'
        alt={emoji}
        src={unicodeEmojiUrl(emoji)}
      />
    );
  } else {
    const src = autoPlayGif || hovered ? url : staticUrl;
    const shortCode = `:${emoji}:`;
    const classes = `emojione custom-emoji${isSensitive ? ' sensitive-custom-emoji' : ''}${reactionCustomEmojiSize ? ' horizontal-origin-custom-emoji' : ''}`;

    return (
      <img draggable='false' className={classes} alt={shortCode} src={src} />
    );
  }
};

const Reaction: FC<{
  statusId: string;
  reaction: ReactionMap;
  addReaction?: (statusId: string, name: string) => void;
  removeReaction?: (statusId: string, name: string) => void;
  canReact: boolean;
}> = ({ statusId, reaction, addReaction, removeReaction, canReact }) => {
  const { signedIn } = useIdentity();
  const [hovered, setHovered] = useState(false);
  const targetRef = useRef<HTMLSpanElement>(null);

  const handleClick = useCallback(() => {
    const name = reaction.get('name') as string;

    if (reaction.get('me')) {
      removeReaction?.(statusId, name);
    } else {
      addReaction?.(statusId, name);
    }
  }, [reaction, statusId, addReaction, removeReaction]);

  const handleMouseEnter = useCallback(() => {
    setHovered(true);
  }, []);
  const handleMouseLeave = useCallback(() => {
    setHovered(false);
  }, []);
  const getTarget = useCallback(() => targetRef.current, []);

  const name = reaction.get('name') as string;
  const count = reaction.get('count') as number;
  const users = reaction.get('users') as
    | ImmutableList<ReactionUser>
    | undefined;
  const url = reaction.get('url') as string | undefined;
  const staticUrl = reaction.get('static_url') as string | undefined;
  const me = reaction.get('me') as boolean | undefined;
  const domain = reaction.get('domain') as string | undefined;
  const isSensitive = reaction.get('is_sensitive') as boolean | undefined;

  const unreactable =
    signedIn && reactionLocalEmojiOnly && !!url && !!domain && !me;

  let validUsers: ImmutableList<ReactionUser> | undefined;
  let hasValidUsers = false;

  if (hovered && users) {
    validUsers = users.filter((user) => user.get('acct'));
    hasValidUsers = validUsers.size > 0;
  }

  const title = `:${name}:`;
  const emojiClasses = `reactions-bar__item__users__emoji${reactionCustomEmojiSize ? ' horizontal-origin' : ''}`;

  return (
    <>
      <span
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        ref={targetRef}
      >
        <button
          type='button'
          className={classNames('reactions-bar__item', {
            active: reaction.get('me'),
            'reactions-bar__item--unreactable': unreactable,
          })}
          onClick={handleClick}
          disabled={!canReact || unreactable}
        >
          <span className={emojiClasses}>
            <Emoji
              hovered={hovered}
              emoji={name}
              url={url}
              staticUrl={staticUrl}
              isSensitive={isSensitive}
            />
          </span>
          <span className='reactions-bar__item__count'>
            <AnimatedNumber value={count} />
          </span>
        </button>
      </span>
      {hasValidUsers && validUsers && (
        <EmojiReactionOverlay
          show={hovered}
          target={getTarget}
          emojiUrl={
            url
              ? autoPlayGif || hovered
                ? url
                : (staticUrl ?? url)
              : unicodeEmojiUrl(name)
          }
          shortCode={title}
          placement='bottom'
          emojiClassName={emojiClasses}
        >
          <div className='reactions-bar__item__users__list'>
            {validUsers.map((user) => (
              <span
                className='reactions-bar__item__users__item'
                key={user.get('acct')}
              >
                <Avatar account={user as never} size={24} />
                <DisplayName account={user as never} />
              </span>
            ))}
            {count > 11 && (
              <span className='reactions-bar__item__users__item'>
                +{count - 11}
              </span>
            )}
          </div>
        </EmojiReactionOverlay>
      )}
    </>
  );
};

const StatusReactions: FC<StatusReactionsProps> = ({
  statusId,
  reactions,
  numVisible,
  addReaction,
  removeReaction,
  canReact,
}) => {
  const customEmojiMutes = useAppSelector(
    (state) => state.custom_emoji_mutes.items,
  );

  let visibleReactions = reactions
    .filter((x) => (x.get('count') as number) > 0)
    .filter((x) => {
      if (!x.get('url')) {
        return true;
      }

      const shortcode = (x.get('name') as string).split('@')[0] ?? '';
      const domain = x.get('domain') as string | undefined;

      return !isCustomEmojiMuted(shortcode, domain, customEmojiMutes);
    })
    .sort((a, b) => (b.get('count') as number) - (a.get('count') as number));

  if (numVisible !== undefined && numVisible >= 0) {
    visibleReactions = visibleReactions.filter((_, i) => i < numVisible);
  }

  return (
    <div
      className={classNames('reactions-bar', {
        'reactions-bar--empty': visibleReactions.isEmpty(),
      })}
    >
      {visibleReactions.map((reaction) => (
        <Reaction
          key={reaction.get('name') as string}
          statusId={statusId}
          reaction={reaction}
          addReaction={addReaction}
          removeReaction={removeReaction}
          canReact={canReact}
        />
      ))}
    </div>
  );
};

export { StatusReactions };
