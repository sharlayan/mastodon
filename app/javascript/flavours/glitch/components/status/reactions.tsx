import type { ComponentProps } from 'react';
import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import type { EmojiData } from 'emoji-mart';

import {
  addReaction,
  removeReaction,
} from '@/flavours/glitch/actions/interactions';
import { ComposeEmojiButton } from '@/flavours/glitch/features/compose/redesign/emoji';
import { useIdentity } from '@/flavours/glitch/identity_context';
import {
  reactionsEnabled,
  visibleReactions,
} from '@/flavours/glitch/initial_state';
import {
  createAppSelector,
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch/store';

import { StatusReactions } from '../status_reactions';

import classes from './styles.module.scss';

type Reactions = ComponentProps<typeof StatusReactions>['reactions'];

export const selectRedesignReactions = createAppSelector(
  [
    (state, statusId: string) =>
      state.statuses.getIn([statusId, 'reactions']) as Reactions | undefined,
    (state) => state.accounts,
  ],
  (reactions, accounts) =>
    reactions?.map((reaction) => {
      const users = reaction.get('users');
      if (!users || typeof users !== 'object') {
        return reaction;
      }
      return reaction.set(
        'users',
        users.map(
          (user) =>
            (accounts.get(user.get('id') ?? '') as unknown as
              | typeof user
              | undefined) ?? user,
        ),
      );
    }),
);

export const StatusRedesignReactions: React.FC<{ statusId: string }> = ({
  statusId,
}) => {
  const reactions = useAppSelector((state) =>
    selectRedesignReactions(state, statusId),
  );
  const { signedIn } = useIdentity();
  const dispatch = useAppDispatch();
  const canReact = signedIn && reactionsEnabled;
  const handleAdd = useCallback(
    (id: string, name: string) => {
      if (canReact) dispatch(addReaction(id, name));
    },
    [canReact, dispatch],
  );
  const handleRemove = useCallback(
    (id: string, name: string) => {
      if (signedIn) dispatch(removeReaction(id, name));
    },
    [dispatch, signedIn],
  );

  if (!reactions || visibleReactions === 0) return null;

  return (
    <div className={classes.reactions}>
      <StatusReactions
        statusId={statusId}
        reactions={reactions}
        numVisible={visibleReactions ?? undefined}
        canReact={canReact}
        addReaction={handleAdd}
        removeReaction={handleRemove}
      />
    </div>
  );
};

export const StatusReactionPicker: React.FC<{ statusId: string }> = ({
  statusId,
}) => {
  const { signedIn } = useIdentity();
  const dispatch = useAppDispatch();
  const handlePick = useCallback(
    (emoji: EmojiData) => {
      if (!signedIn || !reactionsEnabled) return;
      const name = ('native' in emoji && emoji.native) || emoji.id;
      if (!name) return;
      const url = 'imageUrl' in emoji ? emoji.imageUrl : undefined;
      dispatch(addReaction(statusId, name.replaceAll(':', ''), url));
    },
    [dispatch, signedIn, statusId],
  );

  if (!reactionsEnabled) return null;

  return (
    <ComposeEmojiButton
      onPick={handlePick}
      disabled={!signedIn}
      variant='ghost'
      label={<FormattedMessage id='status.react' defaultMessage='React' />}
    />
  );
};
