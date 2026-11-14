import { createSelector } from '@reduxjs/toolkit';

export const STATUS_ACTION_BAR_ITEMS = [
  'favourite',
  'reaction',
  'bookmark',
  'clip',
  'quote',
];

export const STATUS_ACTION_BAR_DEFAULT_HIDDEN = ['clip', 'quote'];

export const statusActionBarItemMessages = {
  favourite: { id: 'settings.status_action_bar.favourite', defaultMessage: 'Favorite' },
  reaction: { id: 'settings.status_action_bar.reaction', defaultMessage: 'Reaction' },
  bookmark: { id: 'settings.status_action_bar.bookmark', defaultMessage: 'Bookmark' },
  clip: { id: 'settings.status_action_bar.clip', defaultMessage: 'Clip' },
  quote: { id: 'settings.status_action_bar.quote', defaultMessage: 'Quote' },
};

export const computeStatusActionBarOrder = (storedOrder = []) => {
  const validStoredOrder = Array.isArray(storedOrder)
    ? storedOrder.filter((key, index) => STATUS_ACTION_BAR_ITEMS.includes(key) && storedOrder.indexOf(key) === index)
    : [];

  return [...validStoredOrder, ...STATUS_ACTION_BAR_ITEMS.filter(key => !validStoredOrder.includes(key))];
};

export const selectStatusActionBarOrder = createSelector(
  [(state) => state.getIn(['local_settings', 'status_action_bar', 'order'])],
  (storedOrder) => computeStatusActionBarOrder(storedOrder?.toJS()),
);
