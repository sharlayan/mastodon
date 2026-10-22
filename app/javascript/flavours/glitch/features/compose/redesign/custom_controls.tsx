import { useCallback, useEffect } from 'react';

import { FormattedMessage } from 'react-intl';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  FloppyDiskIcon,
  StackPlusIcon,
  UsersThreeIcon,
} from '@phosphor-icons/react';

import { fetchCircles } from '@/flavours/glitch/actions/circles';
import { fetchClips } from '@/flavours/glitch/actions/clips';
import { changeComposeCircle } from '@/flavours/glitch/actions/compose_typed';
import { openModal } from '@/flavours/glitch/actions/modal';
import {
  fetchStatusDrafts,
  saveStatusDraft,
  setComposeToStatusDraft,
} from '@/flavours/glitch/actions/status_drafts';
import { Button } from '@/flavours/glitch/components/button/redesign';
import {
  Menu,
  MenuItem,
  MenuItemDivider,
  MenuItemGroup,
  MenuItemRadio,
  MenuList,
  MenuTrigger,
} from '@/flavours/glitch/components/menu';
import { RelativeTimestamp } from '@/flavours/glitch/components/relative_timestamp';
import {
  circlesEnabled,
  clipsEnabled,
  me,
} from '@/flavours/glitch/initial_state';
import { getOrderedCircles } from '@/flavours/glitch/selectors/circles';
import { getOrderedAccountClips } from '@/flavours/glitch/selectors/clips';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import { ComposeScheduleButton } from './schedule';
import classes from './styles.module.scss';

export const ComposeCustomControls: React.FC = () => (
  <div className={classes.customControls}>
    <ComposeCircleButton />
    <ComposeClipButton />
    <ComposeScheduleButton />
    <ComposeDraftButton />
  </div>
);

export const ComposeCircleButton: React.FC = () => {
  const dispatch = useAppDispatch();
  const circles = useAppSelector(getOrderedCircles);
  const circleId = useAppSelector(
    (state) => state.compose.get('circle_id') as string | null,
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  useEffect(() => {
    if (circlesEnabled) void dispatch(fetchCircles());
  }, [dispatch]);
  const onChange = useCallback(
    ({ value }: { value: string }) => {
      dispatch(changeComposeCircle(value || null));
    },
    [dispatch],
  );
  if (!circlesEnabled || circles.length === 0) return null;
  const selected = circles.find((circle) => circle.id === circleId);

  return (
    <Menu>
      <MenuTrigger
        as={Button}
        leadingIcon={UsersThreeIcon}
        size='sm'
        disabled={isEditing}
      >
        {selected?.title ?? (
          <FormattedMessage
            id='compose_form.circle.select'
            defaultMessage='Select circle'
          />
        )}
      </MenuTrigger>
      <MenuList placement='bottom-start' maxWidth={280}>
        <MenuItemRadio
          name='circle'
          value=''
          checked={!circleId}
          onChange={onChange}
        >
          <FormattedMessage
            id='compose_form.circle.none'
            defaultMessage='No circle'
          />
        </MenuItemRadio>
        {circles.map((circle) => (
          <MenuItemRadio
            key={circle.id}
            name='circle'
            value={circle.id}
            checked={circleId === circle.id}
            onChange={onChange}
          >
            {circle.title}
          </MenuItemRadio>
        ))}
      </MenuList>
    </Menu>
  );
};

export const ComposeClipButton: React.FC = () => {
  const dispatch = useAppDispatch();
  const clips = useAppSelector((state) => getOrderedAccountClips(state, me));
  const selectedCount = useAppSelector(
    (state) => (state.compose.get('clip_ids') as ImmutableList<string>).size,
  );
  const visible = useAppSelector(
    (state) => state.local_settings.get('show_clip_choice', true) as boolean,
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  useEffect(() => {
    if (clipsEnabled) void dispatch(fetchClips());
  }, [dispatch]);
  const onClick = useCallback(() => {
    dispatch(openModal({ modalType: 'CLIP_ADD', modalProps: {} }));
  }, [dispatch]);
  if (!clipsEnabled || !visible || clips.length === 0) return null;

  return (
    <Button
      size='sm'
      leadingIcon={StackPlusIcon}
      disabled={isEditing}
      onClick={onClick}
    >
      {selectedCount > 0 ? (
        <FormattedMessage
          id='compose_form.clip.count'
          defaultMessage='{count} clips'
          values={{ count: selectedCount }}
        />
      ) : (
        <FormattedMessage
          id='compose_form.clip.select'
          defaultMessage='Select clip'
        />
      )}
    </Button>
  );
};

type StatusDraft = ImmutableMap<string, unknown>;

export const ComposeDraftButton: React.FC = () => {
  const dispatch = useAppDispatch();
  const visible = useAppSelector(
    (state) => !!state.local_settings.get('show_draft_button'),
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  const busy = useAppSelector(
    (state) =>
      !!state.compose.get('is_submitting') ||
      !!state.compose.get('is_uploading'),
  );
  const drafts = useAppSelector(
    (state) =>
      (state.status_drafts as ImmutableMap<string, unknown>).get(
        'items',
      ) as ImmutableList<StatusDraft>,
  );
  const onOpen = useCallback(() => {
    void dispatch(fetchStatusDrafts());
  }, [dispatch]);
  const onSave = useCallback(() => {
    void dispatch(saveStatusDraft());
  }, [dispatch]);
  if (!visible || isEditing) return null;

  return (
    <Menu onOpen={onOpen}>
      <MenuTrigger
        as={Button}
        leadingIcon={FloppyDiskIcon}
        size='sm'
        disabled={busy}
      >
        <FormattedMessage
          id='compose_form.draft.label'
          defaultMessage='Draft'
        />
      </MenuTrigger>
      <MenuList placement='bottom-start' maxWidth={320}>
        <MenuItem onClick={onSave}>
          <FormattedMessage
            id='compose_form.draft.save'
            defaultMessage='Save'
          />
        </MenuItem>
        <MenuItemDivider />
        <MenuItemGroup
          label={
            <FormattedMessage
              id='compose_form.draft.load'
              defaultMessage='Load'
            />
          }
        >
          {drafts.size === 0 && (
            <MenuItem disabled>
              <FormattedMessage
                id='compose_form.draft.empty'
                defaultMessage='No saved drafts'
              />
            </MenuItem>
          )}
          {drafts.map((draft) => (
            <ComposeDraftItem key={draft.get('id') as string} draft={draft} />
          ))}
        </MenuItemGroup>
      </MenuList>
    </Menu>
  );
};

const ComposeDraftItem: React.FC<{ draft: StatusDraft }> = ({ draft }) => {
  const dispatch = useAppDispatch();
  const onClick = useCallback(() => {
    dispatch(setComposeToStatusDraft(draft));
  }, [dispatch, draft]);
  const params = draft.get('params') as ImmutableMap<string, string>;
  const spoiler = params.get('spoiler_text') ?? '';
  const text = (spoiler.length > 0 ? spoiler : (params.get('status') ?? ''))
    .replace(/\s+/g, ' ')
    .trim();
  return (
    <MenuItem
      onClick={onClick}
      description={
        <RelativeTimestamp timestamp={draft.get('updated_at') as string} />
      }
    >
      {text.slice(0, 60) || (
        <FormattedMessage
          id='compose_form.draft.untitled'
          defaultMessage='Empty draft'
        />
      )}
    </MenuItem>
  );
};

export const ComposeMfmHint: React.FC = () => {
  const dispatch = useAppDispatch();
  const contentType = useAppSelector(
    (state) => state.compose.get('content_type') as string,
  );
  const hidden = useAppSelector(
    (state) => !!state.local_settings.get('hide_mfm_compose_hint'),
  );
  const text = useAppSelector((state) => state.compose.get('text') as string);
  const onPreview = useCallback(() => {
    dispatch(openModal({ modalType: 'MFM_PREVIEW', modalProps: { text } }));
  }, [dispatch, text]);
  if (contentType !== 'text/x-mfm' || hidden) return null;

  return (
    <div className={classes.customControls}>
      <Button size='sm' onClick={onPreview}>
        <FormattedMessage
          id='compose_form.mfm.preview'
          defaultMessage='Preview'
        />
      </Button>
      <Button
        as='a'
        size='sm'
        href='https://misskey-hub.net/en/docs/for-users/features/mfm/'
        target='_blank'
        rel='noopener noreferrer'
      >
        <FormattedMessage
          id='compose_form.mfm.syntax_docs'
          defaultMessage='MFM syntax'
        />
      </Button>
    </div>
  );
};
