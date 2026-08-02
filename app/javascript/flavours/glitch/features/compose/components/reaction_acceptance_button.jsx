import { useCallback, useMemo } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import AddReactionIcon from '@/material-icons/400-24px/add_reaction.svg?react';
import { Dropdown } from '@/flavours/glitch/components/dropdown_menu';
import { Icon } from '@/flavours/glitch/components/icon';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';
import { changeReactionAcceptance } from 'flavours/glitch/sharlayan/compose/state';

const messages = defineMessages({
  title: { id: 'compose.reaction_acceptance', defaultMessage: 'Reaction acceptance' },
  all: { id: 'compose.reaction_acceptance.all', defaultMessage: 'Accept all' },
  likeOnly: { id: 'compose.reaction_acceptance.like_only', defaultMessage: 'Likes only' },
  likeOnlyForRemote: { id: 'compose.reaction_acceptance.like_only_remote', defaultMessage: 'Remote users: likes only' },
  nonSensitiveOnly: { id: 'compose.reaction_acceptance.non_sensitive', defaultMessage: 'Exclude sensitive emojis' },
  mixed: { id: 'compose.reaction_acceptance.non_sensitive_local_like_remote', defaultMessage: 'Exclude sensitive emojis and remote users' },
});

const REACTION_ACCEPTANCE_OPTIONS = [
  ['all', messages.all],
  ['likeOnly', messages.likeOnly],
  ['likeOnlyForRemote', messages.likeOnlyForRemote],
  ['nonSensitiveOnly', messages.nonSensitiveOnly],
  ['nonSensitiveOnlyForLocalLikeOnlyForRemote', messages.mixed],
];

export const ReactionAcceptanceButton = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const visible = useAppSelector((state) =>
    state.getIn(['local_settings', 'show_reaction_acceptance'], false),
  );
  const acceptance =
    useAppSelector((state) => state.getIn(['compose', 'reaction_acceptance'])) ||
    'all';
  const handleChange = useCallback(
    (value) => dispatch(changeReactionAcceptance(value === 'all' ? null : value)),
    [dispatch],
  );
  const options = useMemo(
    () =>
      REACTION_ACCEPTANCE_OPTIONS.map(([value, message]) => ({
        text: intl.formatMessage(message),
        action: () => handleChange(value),
      })),
    [handleChange, intl],
  );

  if (!visible) return null;

  const label = intl.formatMessage(
    REACTION_ACCEPTANCE_OPTIONS.find(([value]) => value === acceptance)?.[1] || messages.all,
  );

  return (
    <Dropdown items={options} scrollKey='compose-reaction-acceptance'>
      <button
        type='button'
        title={intl.formatMessage(messages.title)}
        className={classNames('dropdown-button', { active: acceptance !== 'all' })}
      >
        <Icon id='face' icon={AddReactionIcon} />
        <span className='dropdown-button__label'>{label}</span>
      </button>
    </Dropdown>
  );
};
