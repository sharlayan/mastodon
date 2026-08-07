import { useCallback, useEffect } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { fetchClips } from '@/flavours/glitch/actions/clips';
import { openModal } from '@/flavours/glitch/actions/modal';
import { Icon } from '@/flavours/glitch/components/icon';
import { clipsEnabled, me } from '@/flavours/glitch/initial_state';
import { getOrderedAccountClips } from '@/flavours/glitch/selectors/clips';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';

const messages = defineMessages({
  clip: { id: 'compose_form.clip.label', defaultMessage: 'Add to clip' },
  select: { id: 'compose_form.clip.select', defaultMessage: 'Select clip' },
});

interface ClipButtonProps {
  disabled?: boolean;
}

export const ClipButton: FC<ClipButtonProps> = ({ disabled = false }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const clips = useAppSelector((state) => getOrderedAccountClips(state, me));
  const selectedCount = useAppSelector(
    (state) => (state.compose.get('clip_ids') as ImmutableList<string>).size,
  );
  const showClipChoice = useAppSelector(
    (state) =>
      (state.local_settings as ImmutableMap<string, unknown>).get(
        'show_clip_choice',
        true,
      ) as boolean,
  );

  useEffect(() => {
    if (clipsEnabled) {
      void dispatch(fetchClips());
    }
  }, [dispatch]);

  const handleClick = useCallback(() => {
    dispatch(openModal({ modalType: 'CLIP_ADD', modalProps: {} }));
  }, [dispatch]);

  if (!clipsEnabled || !showClipChoice || clips.length === 0) {
    return null;
  }

  const label =
    selectedCount > 0
      ? intl.formatMessage(
          { id: 'compose_form.clip.count', defaultMessage: '{count} clips' },
          { count: selectedCount },
        )
      : intl.formatMessage(messages.select);

  return (
    <button
      type='button'
      title={intl.formatMessage(messages.clip)}
      disabled={disabled}
      onClick={handleClick}
      className={classNames('dropdown-button', { active: selectedCount > 0 })}
    >
      <Icon id='note_stack_add' icon={NoteStackAddIcon} />
      <span className='dropdown-button__label'>{label}</span>
    </button>
  );
};
