import { useCallback, useEffect } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { List as ImmutableList } from 'immutable';

import { fetchClips } from '@/flavours/glitch-classic/actions/clips';
import { openModal } from '@/flavours/glitch-classic/actions/modal';
import { Icon } from '@/flavours/glitch-classic/components/icon';
import { clipsEnabled, me } from '@/flavours/glitch-classic/initial_state';
import { getOrderedAccountClips } from '@/flavours/glitch-classic/selectors/clips';
import {
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch-classic/store';
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
    (state) => state.local_settings.get('show_clip_choice', true) as boolean,
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
          {
            id: 'compose_form.clip.count',
            defaultMessage: '{count, plural, one {# clip} other {# clips}}',
          },
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
