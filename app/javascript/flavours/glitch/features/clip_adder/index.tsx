import { useCallback, useEffect, useId, useState } from 'react';

import { FormattedMessage, useIntl, defineMessages } from 'react-intl';

import { Link } from 'react-router-dom';

import type { List as ImmutableList } from 'immutable';

import { EmptyState } from '@/flavours/glitch/components/empty_state';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { NavigationFocusTarget } from '@/flavours/glitch/components/navigation_focus_target';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { fetchClips } from 'flavours/glitch/actions/clips';
import { toggleComposeClip } from 'flavours/glitch/actions/compose_typed';
import {
  apiGetStatusClips,
  apiAddStatusToClip,
  apiRemoveStatusFromClip,
} from 'flavours/glitch/api/clips';
import { Toggle } from 'flavours/glitch/components/form_fields';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { me } from 'flavours/glitch/initial_state';
import type { Clip } from 'flavours/glitch/models/clip';
import { getOrderedAccountClips } from 'flavours/glitch/selectors/clips';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

const ClipRow: React.FC<{
  clip: Clip;
  statusId: string;
  initialChecked: boolean;
}> = ({ clip, statusId, initialChecked }) => {
  const [checked, setChecked] = useState(initialChecked);
  const [updating, setUpdating] = useState(false);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const shouldAdd = e.target.checked;
      setUpdating(true);
      setChecked(shouldAdd);

      const request = shouldAdd
        ? apiAddStatusToClip(clip.id, statusId)
        : apiRemoveStatusFromClip(clip.id, statusId);

      request
        .catch(() => {
          setChecked(!shouldAdd);
        })
        .finally(() => {
          setUpdating(false);
        });
    },
    [clip.id, statusId],
  );

  return (
    <label className='clip-adder__list__item'>
      <span className='clip-adder__list__item__title'>{clip.title}</span>
      <Toggle checked={checked} disabled={updating} onChange={handleChange} />
    </label>
  );
};

const ComposeClipRow: React.FC<{
  clip: Clip;
}> = ({ clip }) => {
  const dispatch = useAppDispatch();
  const checked = useAppSelector((state) =>
    (state.compose.get('clip_ids') as ImmutableList<string>).includes(clip.id),
  );

  const handleChange = useCallback(() => {
    dispatch(toggleComposeClip(clip.id));
  }, [dispatch, clip.id]);

  return (
    <label className='clip-adder__list__item'>
      <span className='clip-adder__list__item__title'>{clip.title}</span>
      <Toggle checked={checked} onChange={handleChange} />
    </label>
  );
};

export const ClipAdder: React.FC<{
  statusId?: string;
  onClose: () => void;
}> = ({ statusId, onClose }) => {
  const intl = useIntl();
  const titleId = useId();
  const dispatch = useAppDispatch();
  const clips = useAppSelector((state) => getOrderedAccountClips(state, me));
  const [loading, setLoading] = useState(true);
  const [memberClipIds, setMemberClipIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    let active = true;

    void Promise.all([
      dispatch(fetchClips()),
      statusId
        ? apiGetStatusClips(statusId).then((data) => {
            if (active) setMemberClipIds(new Set(data.map((clip) => clip.id)));
          })
        : Promise.resolve(),
    ])
      .catch(() => {
        // Nothing
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [dispatch, statusId]);

  return (
    <div className='modal-root__modal dialog-modal'>
      <div className='dialog-modal__header'>
        <IconButton
          className='dialog-modal__header__close'
          title={intl.formatMessage(messages.close)}
          icon='times'
          iconComponent={CloseIcon}
          onClick={onClose}
        />

        <NavigationFocusTarget
          as='h1'
          id={titleId}
          className='dialog-modal__header__title'
        >
          <FormattedMessage
            id='clips.add_to_clip'
            defaultMessage='Add to clip'
          />
        </NavigationFocusTarget>
      </div>

      <div className='dialog-modal__content'>
        <div
          className='clip-adder__list'
          role='group'
          aria-labelledby={titleId}
        >
          {loading ? (
            <LoadingIndicator />
          ) : clips.length === 0 ? (
            <EmptyState
              title={
                <FormattedMessage
                  id='clips.no_clips_yet'
                  defaultMessage='No clips yet.'
                />
              }
              message={
                <FormattedMessage
                  id='clips.create_a_clip_to_organize'
                  defaultMessage='Create a clip to collect posts you want to keep'
                />
              }
            >
              <Link to='/clips/new' className='button' onClick={onClose}>
                <FormattedMessage
                  id='clips.create_clip'
                  defaultMessage='Create clip'
                />
              </Link>
            </EmptyState>
          ) : (
            clips.map((clip) =>
              statusId ? (
                <ClipRow
                  key={clip.id}
                  clip={clip}
                  statusId={statusId}
                  initialChecked={memberClipIds.has(clip.id)}
                />
              ) : (
                <ComposeClipRow key={clip.id} clip={clip} />
              ),
            )
          )}
        </div>
      </div>
    </div>
  );
};
