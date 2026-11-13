import { createAction } from '@reduxjs/toolkit';

import {
  apiGetNotificationPolicy,
  apiUpdateNotificationsPolicy,
} from 'flavours/glitch-classic/api/notification_policies';
import type { NotificationPolicy } from 'flavours/glitch-classic/models/notification_policy';
import { createDataLoadingThunk } from 'flavours/glitch-classic/store/typed_functions';

export const fetchNotificationPolicy = createDataLoadingThunk(
  'notificationPolicy/fetch',
  () => apiGetNotificationPolicy(),
);

export const updateNotificationsPolicy = createDataLoadingThunk(
  'notificationPolicy/update',
  (policy: Partial<NotificationPolicy>) => apiUpdateNotificationsPolicy(policy),
);

export const decreasePendingRequestsCount = createAction<number>(
  'notificationPolicy/decreasePendingRequestsCount',
);
