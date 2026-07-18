import { showAlert } from 'flavours/glitch/actions/alerts';
import { updateStatusReaction } from 'flavours/glitch/actions/statuses';
import { fillAntennaTimelineGaps } from 'flavours/glitch/actions/timelines';
import { me } from 'flavours/glitch/initial_state';

const linkedNotificationPreferenceKey = (accountId) => `linked_notif_prefs_${accountId}`;
const linkedNotificationLastSeenKey = (accountId, linkedAccountId) => `linked_notif_last_id_${accountId}_${linkedAccountId}`;

export const getLinkedNotificationAlert = ({ activeAccountId, linked, messages, rootAccountId, storage }) => {
  if (String(linked.linked_account_id) === String(activeAccountId)) {
    return null;
  }

  let inAppEnabled = false;
  try {
    const preferences = JSON.parse(storage.getItem(linkedNotificationPreferenceKey(rootAccountId)) ?? '{}');
    inAppEnabled = preferences[String(linked.linked_account_id)]?.inApp ?? false;
  } catch {
    return null;
  }

  if (!inAppEnabled) {
    return null;
  }

  const fromName = linked.notification.account.display_name || linked.notification.account.username;
  const template = messages[`notification.${linked.notification.type}`];
  const rawMessage = typeof template === 'string' ? template.replace(/\{name\}/g, fromName) : fromName;
  const message = rawMessage.length > 120 ? `${rawMessage.slice(0, 119)}…` : rawMessage;

  return { title: `@${linked.linked_account_acct}`, message };
};

export const updateLinkedNotificationLastSeen = ({ activeAccountId, linked, storage }) => {
  if (!activeAccountId) {
    return;
  }

  const key = linkedNotificationLastSeenKey(activeAccountId, linked.linked_account_id);
  const previousId = storage.getItem(key);

  if (!previousId || Number(linked.notification.id) > Number(previousId)) {
    storage.setItem(key, linked.notification.id);
  }
};

export const handleSharlayanStreamingEvent = ({
  bogusQuotePolicy,
  data,
  dispatch,
  getState,
  messages,
  storage = localStorage,
  updateReaction = updateStatusReaction,
}) => {
  if (data.event === 'status.reaction') {
    dispatch(updateReaction(JSON.parse(data.payload), { bogusQuotePolicy }));
    return true;
  }

  if (data.event !== 'linked_notification') {
    return false;
  }

  const linked = JSON.parse(data.payload);
  const rootAccountId = getState().accountSwitches?.get('rootAccountId') ?? me;
  const alert = getLinkedNotificationAlert({ activeAccountId: me, linked, messages, rootAccountId, storage });

  if (alert) {
    dispatch(showAlert(alert));
  }

  updateLinkedNotificationLastSeen({ activeAccountId: me, linked, storage });
  return true;
};

export const createAntennaStreamConnector = ({ connectTimeline, fillGaps = fillAntennaTimelineGaps }) => antennaId =>
  connectTimeline(`antenna:${antennaId}`, 'antenna', { antenna: antennaId }, {
    fillGaps: () => fillGaps(antennaId),
  });
