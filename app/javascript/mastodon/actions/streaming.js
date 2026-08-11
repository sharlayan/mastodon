// @ts-check

import { getLocale } from '../locales';
import { connectStream } from '../stream';

import { me } from '../initial_state';
import { incrementLinkedUnreadCount } from '../sharlayan/account_switcher/actions';

import { showAlert } from './alerts';
import {
  fetchAnnouncements,
  updateAnnouncements,
  updateReaction as updateAnnouncementsReaction,
  deleteAnnouncement,
} from './announcements';
import { updateConversations } from './conversations';
import { processNewNotificationForGroups, refreshStaleNotificationGroups, pollRecentNotifications as pollRecentGroupNotifications } from './notification_groups';
import { updateNotifications } from './notifications';
import { updateStatus, updateStatusReaction } from './statuses';
import {
  updateTimeline,
  deleteFromTimelines,
  expandHomeTimeline,
  connectTimeline,
  disconnectTimeline,
  fillHomeTimelineGaps,
  fillPublicTimelineGaps,
  fillCommunityTimelineGaps,
  fillListTimelineGaps,
} from './timelines';

/**
 * @param {number} max
 * @returns {number}
 */
const randomUpTo = max =>
  Math.floor(Math.random() * Math.floor(max));

/**
 * @typedef {import('mastodon/store').AppDispatch} Dispatch
 * @typedef {import('mastodon/store').GetState} GetState
 * @typedef {import('redux').UnknownAction} UnknownAction
 * @typedef {(dispatch: Dispatch, getState: GetState) => Promise<void>} FallbackFunction
 */

/**
 * @param {string} timelineId
 * @param {string} channelName
 * @param {Object.<string, string>} params
 * @param {Object} options
 * @param {FallbackFunction} [options.fallback]
 * @param {() => UnknownAction} [options.fillGaps]
 * @param {(status: object) => boolean} [options.accept]
 * @returns {() => void}
 */
export const connectTimelineStream = (timelineId, channelName, params = {}, options = {}) => {
  const { messages } = getLocale();

  // Public streams are currently not returning personalized quote policies
  const bogusQuotePolicy = channelName.startsWith('public') || channelName.startsWith('hashtag');

  return connectStream(channelName, params, (dispatch, getState) => {
    // @ts-ignore
    const locale = getState().getIn(['meta', 'locale']);

    // @ts-expect-error
    let pollingId;

    /**
     * @param {FallbackFunction} fallback
     */

    const useFallback = async fallback => {
      await fallback(dispatch, getState);
      // eslint-disable-next-line react-hooks/rules-of-hooks -- this is not a react hook
      pollingId = setTimeout(() => useFallback(fallback), 20000 + randomUpTo(20000));
    };

    return {
      onConnect() {
        dispatch(connectTimeline(timelineId));

        // @ts-expect-error
        if (pollingId) {
          // @ts-ignore
          clearTimeout(pollingId); pollingId = null;
        }

        if (options.fillGaps) {
          dispatch(options.fillGaps());
        }
      },

      onDisconnect() {
        const { fallback } = options;

        if (fallback) {
          pollingId = setTimeout(() => {
            dispatch(disconnectTimeline({ timeline: timelineId }));
            useFallback(fallback);
          }, randomUpTo(40000));
        } else {
          dispatch(disconnectTimeline({ timeline: timelineId }));
        }
      },

      onReceive(data) {
        try {
          switch (data.event) {
          case 'update':
            // @ts-expect-error
            dispatch(updateTimeline(timelineId, JSON.parse(data.payload), { accept: options.accept, bogusQuotePolicy }));
            break;
          case 'status.update':
            // @ts-expect-error
            dispatch(updateStatus(JSON.parse(data.payload), { bogusQuotePolicy }));
            break;
          case 'status.reaction':
            // @ts-expect-error
            dispatch(updateStatusReaction(JSON.parse(data.payload), { bogusQuotePolicy }));
            break;
          case 'delete':
            dispatch(deleteFromTimelines(data.payload));
            break;
          case 'notification': {
            // @ts-expect-error
            const notificationJSON = JSON.parse(data.payload);
            dispatch(updateNotifications(notificationJSON, messages, locale));
            dispatch(processNewNotificationForGroups(notificationJSON));
            break;
          }
          case 'linked_notification': {
            // @ts-expect-error
            const linked = JSON.parse(data.payload);

            if (String(linked.linked_account_id) !== String(me)) {
              dispatch(incrementLinkedUnreadCount(String(linked.linked_account_id)));

              const rootAccountId = getState().accountSwitches?.get('rootAccountId') ?? me;
              let inAppEnabled = false;
              try {
                const prefs = JSON.parse(localStorage.getItem(`linked_notif_prefs_${rootAccountId}`) ?? '{}');
                inAppEnabled = prefs[String(linked.linked_account_id)]?.inApp ?? false;
              } catch { /* ignore */ }

              if (inAppEnabled) {
                const fromName = linked.notification.account.display_name || linked.notification.account.username;
                const msgTemplate = messages[`notification.${linked.notification.type}`];
                const rawMessage = typeof msgTemplate === 'string' ? msgTemplate.replace(/\{name\}/g, fromName) : fromName;
                const MAX_MSG_LENGTH = 120;
                const message = rawMessage.length > MAX_MSG_LENGTH ? rawMessage.slice(0, MAX_MSG_LENGTH - 1) + '…' : rawMessage;
                dispatch(showAlert({ title: `@${linked.linked_account_acct}`, message }));
              }
            }

            if (me) {
              const key = `linked_notif_last_id_${me}_${linked.linked_account_id}`;
              const prev = localStorage.getItem(key);
              if (!prev || Number(linked.notification.id) > Number(prev)) {
                localStorage.setItem(key, linked.notification.id);
              }
            }
            break;
          }
          case 'notifications_merged': {
            dispatch(refreshStaleNotificationGroups());
            break;
          }
          case 'conversation':
            // @ts-expect-error
            dispatch(updateConversations(JSON.parse(data.payload)));
            break;
          case 'announcement':
            // @ts-expect-error
            dispatch(updateAnnouncements(JSON.parse(data.payload)));
            break;
          case 'announcement.reaction':
            // @ts-expect-error
            dispatch(updateAnnouncementsReaction(JSON.parse(data.payload)));
            break;
          case 'announcement.delete':
            dispatch(deleteAnnouncement(data.payload));
            break;
          }
        } catch (e) {
          console.error(`Failed to process streaming event '${data.event}':`, e);
        }
      },
    };
  });
};

/**
 * @param {Dispatch} dispatch
 */
async function refreshHomeTimelineAndNotification(dispatch) {
  await dispatch(expandHomeTimeline({ maxId: undefined }));

  // TODO: polling for merged notifications
  try {
    await dispatch(pollRecentGroupNotifications());
  } catch {
    // TODO
  }

  await dispatch(fetchAnnouncements());
}

/**
 * @returns {() => void}
 */
export const connectUserStream = () =>
  connectTimelineStream('home', 'user', {}, {
    fallback: refreshHomeTimelineAndNotification,
    // @ts-expect-error
    fillGaps: fillHomeTimelineGaps
  });

/**
 * @param {Object} options
 * @param {boolean} [options.onlyMedia]
 * @returns {() => void}
 */
export const connectCommunityStream = ({ onlyMedia } = {}) =>
  connectTimelineStream(`community${onlyMedia ? ':media' : ''}`, `public:local${onlyMedia ? ':media' : ''}`, {}, {
    // @ts-expect-error
    fillGaps: () => (fillCommunityTimelineGaps({ onlyMedia }))
  });

/**
 * @param {Object} options
 * @param {boolean} [options.onlyMedia]
 * @param {boolean} [options.onlyRemote]
 * @returns {() => void}
 */
export const connectPublicStream = ({ onlyMedia, onlyRemote } = {}) =>
  connectTimelineStream(`public${onlyRemote ? ':remote' : ''}${onlyMedia ? ':media' : ''}`, `public${onlyRemote ? ':remote' : ''}${onlyMedia ? ':media' : ''}`, {}, {
    // @ts-expect-error
    fillGaps: () => fillPublicTimelineGaps({ onlyMedia, onlyRemote })
  });

/**
 * @param {string} columnId
 * @param {string} tagName
 * @param {boolean} onlyLocal
 * @param {(status: object) => boolean} accept
 * @returns {() => void}
 */
export const connectHashtagStream = (columnId, tagName, onlyLocal, accept) =>
  connectTimelineStream(`hashtag:${columnId}${onlyLocal ? ':local' : ''}`, `hashtag${onlyLocal ? ':local' : ''}`, { tag: tagName }, { accept });

/**
 * @returns {() => void}
 */
export const connectDirectStream = () =>
  connectTimelineStream('direct', 'direct');

/**
 * @param {string} listId
 * @returns {() => void}
 */
export const connectListStream = listId =>
  connectTimelineStream(`list:${listId}`, 'list', { list: listId }, {
    // @ts-expect-error
    fillGaps: () => fillListTimelineGaps(listId)
  });
