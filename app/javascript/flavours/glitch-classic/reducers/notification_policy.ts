import { createReducer, isAnyOf } from '@reduxjs/toolkit';

import {
  fetchNotificationPolicy,
  decreasePendingRequestsCount,
  updateNotificationsPolicy,
} from 'flavours/glitch-classic/actions/notification_policies';
import type { NotificationPolicy } from 'flavours/glitch-classic/models/notification_policy';

export const notificationPolicyReducer =
  createReducer<NotificationPolicy | null>(null, (builder) => {
    builder
      .addCase(decreasePendingRequestsCount, (state, action) => {
        if (state) {
          state.summary.pending_requests_count -= action.payload;
        }
      })
      .addMatcher(
        isAnyOf(
          fetchNotificationPolicy.fulfilled,
          updateNotificationsPolicy.fulfilled,
        ),
        (_state, action) => action.payload,
      );
  });
