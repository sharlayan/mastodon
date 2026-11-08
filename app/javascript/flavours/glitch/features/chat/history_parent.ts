import type { History, Location } from 'history';

interface Tracker {
  previous: Map<string, string>;
  current: Location;
}

const trackers = new WeakMap<History, Tracker>();

const withoutDeck = (pathname: string) =>
  pathname.replace(/^\/deck(?=\/|$)/, '') || '/';

export const trackChatHistory = (history: History) => {
  if (trackers.has(history)) return;
  const tracker: Tracker = { previous: new Map(), current: history.location };
  trackers.set(history, tracker);
  history.listen((location, action) => {
    const from = tracker.current;
    tracker.current = location;
    if (!location.key) return;
    if (action === 'PUSH') {
      tracker.previous.set(location.key, withoutDeck(from.pathname));
    } else if (action === 'REPLACE') {
      const prior = from.key ? tracker.previous.get(from.key) : undefined;
      if (prior === undefined) tracker.previous.delete(location.key);
      else tracker.previous.set(location.key, prior);
    }
  });
};

export const leaveChatRoute = (history: History, parent: string) => {
  const { key } = history.location;
  const prior = key ? trackers.get(history)?.previous.get(key) : undefined;
  if (prior === parent) history.goBack();
  else history.replace(parent);
};
