import { createSelector } from '@reduxjs/toolkit';

export const makeGetConversationRecipientAccounts = () => createSelector(
  [
    (state) => state.get('accounts'),
    (_state, recipientIds) => recipientIds,
  ],
  (accounts, recipientIds) => recipientIds
    .map((id) => accounts.get(id))
    .filter(Boolean),
);
