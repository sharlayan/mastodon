import { useCallback, useState } from 'react';

import { Map as ImmutableMap } from 'immutable';

import { hideStatus } from '@/flavours/glitch/actions/statuses';
import type { ExpandedStatusShape } from '@/flavours/glitch/models/status';
import {
  isLengthyStatus,
  parseCharacterLimit,
} from '@/flavours/glitch/sharlayan/post_collapsing';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import type { StatusContextType } from './types';

export function shouldAutoCollapseStatus({
  status,
  settings,
  contentHeight,
  boosted,
  contextType,
  unread,
}: {
  status: ExpandedStatusShape;
  settings: ImmutableMap<string, unknown>;
  contentHeight: number;
  boosted: boolean;
  contextType?: StatusContextType;
  unread?: boolean;
}) {
  if (contextType === 'notifications' && unread !== false) return false;
  const characterLimit = settings.get('character_limit');
  const hasMedia = status.media_attachments.length > 0;
  const heightLimit =
    (Number.parseInt(String(settings.get('height')), 10) || 400) +
    (parseCharacterLimit(characterLimit) === null &&
    hasMedia &&
    contextType !== 'notifications'
      ? 210
      : 0);

  return (
    settings.get('all') === true ||
    (settings.get('notifications') === true &&
      contextType === 'notifications') ||
    (settings.get('lengthy') === true &&
      isLengthyStatus(
        ImmutableMap({ contentHtml: status.contentHtml }),
        characterLimit,
        contentHeight,
        heightLimit,
      )) ||
    (settings.get('reblogs') === true && boosted) ||
    (settings.get('replies') === true && !!status.in_reply_to_id) ||
    (settings.get('media') === true && !status.spoiler_text && hasMedia) ||
    (settings.get('quotes') === true && !!status.quote)
  );
}

export function usePostCollapse({
  status,
  contextType,
  unread,
  boosted,
  disabled,
  collapsed,
}: {
  status?: ExpandedStatusShape;
  contextType?: StatusContextType;
  unread?: boolean;
  boosted: boolean;
  disabled: boolean;
  collapsed?: boolean;
}) {
  const settings = useAppSelector(
    (state) =>
      state.local_settings.get('collapsed') as
        | ImmutableMap<string, unknown>
        | undefined,
  );
  const sharedCw = useAppSelector(
    (state) =>
      state.local_settings.getIn(['content_warnings', 'shared_state']) === true,
  );
  const dispatch = useAppDispatch();
  const statusId = status?.id;
  const statusHidden = status?.hidden;
  const sharedCwRevealed = !!(
    sharedCw &&
    status?.spoiler_text &&
    !statusHidden
  );
  const [manual, setManual] = useState<{
    id?: string;
    hidden?: boolean;
    prop?: boolean;
    value?: boolean;
  }>({ id: statusId, hidden: statusHidden, prop: collapsed });
  let manualValue = manual.value;
  if (manual.id !== statusId) manualValue = undefined;
  else if (manual.prop !== collapsed) manualValue = collapsed;
  if (sharedCwRevealed && manual.hidden !== false) manualValue = false;
  if (
    manual.id !== statusId ||
    manual.hidden !== statusHidden ||
    manual.prop !== collapsed
  ) {
    setManual({
      id: statusId,
      hidden: statusHidden,
      prop: collapsed,
      value: manualValue,
    });
  }
  const [measured, setMeasured] = useState<{ id: string; height: number }>();
  const enabled = !disabled && settings?.get('enabled') === true;
  const isCollapsed =
    enabled &&
    !!status &&
    !sharedCwRevealed &&
    (manualValue ??
      collapsed ??
      shouldAutoCollapseStatus({
        status,
        settings: settings.get('auto', ImmutableMap()) as ImmutableMap<
          string,
          unknown
        >,
        contentHeight: measured?.id === status.id ? measured.height : 0,
        boosted,
        contextType,
        unread,
      }));
  const onCollapsedChange = useCallback(
    (value: boolean) => {
      if (!enabled || !statusId) return;
      if (value && sharedCwRevealed) dispatch(hideStatus(statusId));
      setManual((previous) => ({ ...previous, value }));
    },
    [dispatch, enabled, sharedCwRevealed, statusId],
  );
  const onToggle = useCallback(() => {
    onCollapsedChange(!isCollapsed);
  }, [isCollapsed, onCollapsedChange]);
  const onMeasure = useCallback(
    (height: number) => {
      if (statusId)
        setMeasured((previous) =>
          previous?.id === statusId && previous.height === height
            ? previous
            : { id: statusId, height },
        );
    },
    [statusId],
  );

  return {
    enabled,
    isCollapsed,
    onCollapsedChange,
    onToggle,
    onMeasure,
    showActionBar: settings?.get('show_action_bar') !== false,
  };
}
