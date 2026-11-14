import type { History, Location } from 'history';

interface Entry {
  path: string;
  key?: string;
}

interface Tracker {
  previous: Map<string, Entry>;
  current: Location;
  leaving?: string;
}

const MAX_STEPS = 3;

const trackers = new WeakMap<History, Tracker>();

const withoutDeck = (pathname: string) =>
  pathname.replace(/^\/deck(?=\/|$)/, '') || '/';

const isWithin = (path: string, ancestor: string) =>
  path.startsWith(`${ancestor}/`);

export const trackChatHistory = (history: History) => {
  if (trackers.has(history)) return;
  const tracker: Tracker = { previous: new Map(), current: history.location };
  trackers.set(history, tracker);
  history.listen((location, action) => {
    const from = tracker.current;
    tracker.current = location;
    tracker.leaving = undefined;
    if (!location.key) return;
    if (action === 'PUSH') {
      tracker.previous.set(location.key, {
        path: withoutDeck(from.pathname),
        key: from.key,
      });
    } else if (action === 'REPLACE') {
      const prior = from.key ? tracker.previous.get(from.key) : undefined;
      if (prior === undefined) tracker.previous.delete(location.key);
      else tracker.previous.set(location.key, prior);
    }
  });
};

const stepsBackTo = (tracker: Tracker, history: History, parent: string) => {
  const here = withoutDeck(history.location.pathname);
  let key = history.location.key;
  for (let steps = 1; key && steps <= MAX_STEPS; steps += 1) {
    const prior = tracker.previous.get(key);
    if (!prior) return 0;
    if (prior.path === parent) return steps;
    if (!isWithin(here, prior.path) || !isWithin(prior.path, parent)) return 0;
    key = prior.key;
  }
  return 0;
};

export const leaveChatRoute = (history: History, parent: string) => {
  const tracker = trackers.get(history);
  const { key, pathname } = history.location;
  if (withoutDeck(pathname) === parent) return;
  if (tracker && key && tracker.leaving === key) return;

  const steps = tracker ? stepsBackTo(tracker, history, parent) : 0;
  if (steps > 0) {
    if (tracker && key) tracker.leaving = key;
    if (steps === 1) history.goBack();
    else history.go(-steps);
  } else {
    history.replace(parent);
  }
};
