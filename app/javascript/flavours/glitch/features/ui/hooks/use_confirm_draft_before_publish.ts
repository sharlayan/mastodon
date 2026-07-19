import { useCallback } from 'react';

import { openModal } from 'flavours/glitch/actions/modal';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { useBreakpoint } from './useBreakpoint';

const hasItems = (value: unknown) =>
  typeof value === 'object' &&
  value !== null &&
  'size' in value &&
  typeof value.size === 'number' &&
  value.size > 0;

export const useConfirmDraftBeforePublish = () => {
  const dispatch = useAppDispatch();
  const isMobileLayout = useBreakpoint('full');
  const hasDraft = useAppSelector((state) => {
    const compose = state.compose;

    return Boolean(
      compose.get('id') ||
      compose.get('in_reply_to') ||
      compose.get('quoted_status_id') ||
      compose.get('scheduled_at') ||
      compose.get('poll') ||
      compose.get('text') ||
      compose.get('spoiler_text') ||
      hasItems(compose.get('media_attachments')) ||
      hasItems(compose.get('clip_ids')),
    );
  });

  return useCallback<React.MouseEventHandler>(
    (event) => {
      if (isMobileLayout && hasDraft) {
        event.preventDefault();
        dispatch(
          openModal({ modalType: 'CONFIRM_RESUME_DRAFT', modalProps: {} }),
        );
      }
    },
    [dispatch, hasDraft, isMobileLayout],
  );
};
