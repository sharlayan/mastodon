import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import {
  MenuItemDivider,
  MenuItemGroup,
  MenuItemRadio,
} from '@/flavours/glitch/components/menu';
import { changeReactionAcceptance } from '@/flavours/glitch/sharlayan/compose/state';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

const messages = defineMessages({
  all: { id: 'compose.reaction_acceptance.all', defaultMessage: 'Accept all' },
  likeOnly: {
    id: 'compose.reaction_acceptance.like_only',
    defaultMessage: 'Likes only',
  },
  likeOnlyForRemote: {
    id: 'compose.reaction_acceptance.like_only_remote',
    defaultMessage: 'Remote users: likes only',
  },
  nonSensitiveOnly: {
    id: 'compose.reaction_acceptance.non_sensitive',
    defaultMessage: 'Exclude sensitive emojis',
  },
  nonSensitiveOnlyForLocalLikeOnlyForRemote: {
    id: 'compose.reaction_acceptance.non_sensitive_local_like_remote',
    defaultMessage: 'Exclude sensitive emojis and remote users',
  },
});

const reactionOptions = [
  'all',
  'likeOnly',
  'likeOnlyForRemote',
  'nonSensitiveOnly',
  'nonSensitiveOnlyForLocalLikeOnlyForRemote',
] as const;

export const ComposeCustomSettings: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const showReactions = useAppSelector(
    (state) => !!state.local_settings.get('show_reaction_acceptance'),
  );
  const reactionAcceptance = useAppSelector(
    (state) =>
      (state.compose.get('reaction_acceptance') as string | null) ?? 'all',
  );

  const onReactionChange = useCallback(
    ({ value }: { value: string }) => {
      dispatch(changeReactionAcceptance(value === 'all' ? null : value));
    },
    [dispatch],
  );

  if (!showReactions) return null;

  return (
    <>
      <MenuItemDivider />
      <MenuItemGroup
        label={
          <FormattedMessage
            id='compose.reaction_acceptance'
            defaultMessage='Reaction acceptance'
          />
        }
      >
        {reactionOptions.map((value) => (
          <MenuItemRadio
            key={value}
            name='reaction_acceptance'
            value={value}
            checked={reactionAcceptance === value}
            onChange={onReactionChange}
            keepMenuOpenOnClick
          >
            {intl.formatMessage(messages[value])}
          </MenuItemRadio>
        ))}
      </MenuItemGroup>
    </>
  );
};
