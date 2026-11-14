import { apiRequestGet, apiRequestPut } from 'flavours/glitch-classic/api';
import type { NotificationPolicyJSON } from 'flavours/glitch-classic/api_types/notification_policies';

export const apiGetNotificationPolicy = () =>
  apiRequestGet<NotificationPolicyJSON>('v2/notifications/policy');

export const apiUpdateNotificationsPolicy = (
  policy: Partial<NotificationPolicyJSON>,
) => apiRequestPut<NotificationPolicyJSON>('v2/notifications/policy', policy);
