import { useEffect, useCallback, useRef } from 'react';

import { useIntl } from 'react-intl';

import { showAlert } from 'mastodon/actions/alerts';
import { apiGetLinkedNotifications } from 'mastodon/api/account_switches';
import type { ApiLinkedNotificationItemJSON } from 'mastodon/api_types/account_switches';
import { getLinkedNotifPrefs } from 'mastodon/features/account_switcher';
import { me } from 'mastodon/initial_state';
import { useAppDispatch } from 'mastodon/store';

const POLL_INTERVAL_MS = 30_000;
const MAX_MSG_LENGTH = 120;

const getLastSeenId = (linkedAccountId: string): string | null =>
  me
    ? localStorage.getItem(`linked_notif_last_id_${me}_${linkedAccountId}`)
    : null;

const setLastSeenId = (linkedAccountId: string, id: string) => {
  if (!me) return;
  localStorage.setItem(`linked_notif_last_id_${me}_${linkedAccountId}`, id);
};

const buildSinceIds = (): Record<string, string> => {
  if (!me) return {};
  const prefs = getLinkedNotifPrefs(me);
  const result: Record<string, string> = {};
  for (const [accountId, pref] of Object.entries(prefs)) {
    if (!pref.inApp) continue;
    const lastId = getLastSeenId(accountId);
    if (lastId) result[accountId] = lastId;
  }
  return result;
};

const hasAnyInAppEnabled = (): boolean => {
  if (!me) return false;
  const prefs = getLinkedNotifPrefs(me);
  return Object.values(prefs).some((p) => p.inApp);
};

export const LinkedNotificationsPoller: React.FC = () => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const pollingRef = useRef(false);

  const poll = useCallback(async () => {
    if (!me || pollingRef.current) return;
    if (!hasAnyInAppEnabled()) return;

    pollingRef.current = true;
    try {
      const sinceIds = buildSinceIds();
      const items: ApiLinkedNotificationItemJSON[] =
        await apiGetLinkedNotifications(sinceIds);

      if (items.length === 0) return;

      const sorted = [...items].sort(
        (a, b) => Number(a.notification.id) - Number(b.notification.id),
      );

      const latestPerAccount: Record<string, string> = {};

      for (const item of sorted) {
        const { linked_account_id, linked_account_acct, notification } = item;

        const prefs = getLinkedNotifPrefs(me);
        if (!prefs[linked_account_id]?.inApp) continue;

        const lastSeen = getLastSeenId(linked_account_id);
        if (lastSeen && Number(notification.id) <= Number(lastSeen)) continue;

        const fromName =
          notification.account.display_name || notification.account.username;

        const msgTemplate = intl.messages[`notification.${notification.type}`];
        let rawMessage: string;
        if (typeof msgTemplate === 'string') {
          rawMessage = msgTemplate.replace(/\{name\}/g, fromName);
        } else {
          rawMessage = fromName;
        }

        const message =
          rawMessage.length > MAX_MSG_LENGTH
            ? rawMessage.slice(0, MAX_MSG_LENGTH - 1) + '…'
            : rawMessage;

        dispatch(
          showAlert({
            title: `@${linked_account_acct}`,
            message,
          }),
        );

        latestPerAccount[linked_account_id] = notification.id;
      }

      for (const [accountId, latestId] of Object.entries(latestPerAccount)) {
        setLastSeenId(accountId, latestId);
      }
    } catch {
      // Silently swallow polling errors – network may be offline, etc.
    } finally {
      pollingRef.current = false;
    }
  }, [dispatch, intl]);

  useEffect(() => {
    if (!me) return;

    const initialTimer = setTimeout(() => void poll(), 3_000);
    const intervalId = setInterval(() => void poll(), POLL_INTERVAL_MS);

    return () => {
      clearTimeout(initialTimer);
      clearInterval(intervalId);
    };
  }, [poll]);

  return null;
};
