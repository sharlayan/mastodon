import { Map as ImmutableMap } from 'immutable';

import { createClip } from 'flavours/glitch/models/clip';
import type { RootState } from 'flavours/glitch/store';

import { getOrderedAccountClips, getOrderedFavouriteClips } from '../clips';

const clip = (
  id: string,
  title: string,
  accountId: string,
  favourited = false,
) =>
  createClip({
    id,
    title,
    description: null,
    public: true,
    account_id: accountId,
    statuses_count: 0,
    favourites_count: 0,
    favourited,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  });

const stateWithClips = () =>
  ({
    clips: ImmutableMap({
      first: clip('first', 'Beta', 'account-1'),
      second: clip('second', 'Alpha', 'account-2', true),
      third: clip('third', 'Gamma', 'account-1', true),
    }),
  }) as unknown as RootState;

describe('clip selectors', () => {
  it('keeps account clip results stable while unrelated state changes', () => {
    const state = stateWithClips();
    const changedState = { ...state, unrelated: true } as unknown as RootState;

    expect(getOrderedAccountClips(state, 'account-1')).toBe(
      getOrderedAccountClips(changedState, 'account-1'),
    );
    expect(
      getOrderedAccountClips(state, 'account-1').map(({ id }) => id),
    ).toEqual(['first', 'third']);
  });

  it('keeps favourite clip results stable while unrelated state changes', () => {
    const state = stateWithClips();
    const changedState = { ...state, unrelated: true } as unknown as RootState;

    expect(getOrderedFavouriteClips(state)).toBe(
      getOrderedFavouriteClips(changedState),
    );
    expect(getOrderedFavouriteClips(state).map(({ id }) => id)).toEqual([
      'second',
      'third',
    ]);
  });
});
