import { useEffect, useCallback, useRef } from 'react';

import { me } from 'flavours/glitch/initial_state';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { fetchAccountSwitches, setLinkedUnreadCounts } from './actions';
import { apiGetLinkedUnreadCounts } from './api';

const POLL_INTERVAL_MS = 5 * 60_000;

export const LinkedNotificationsPoller: React.FC = () => {
  const dispatch = useAppDispatch();
  const pollingRef = useRef(false);

  const loaded = useAppSelector(
    (state) => state.accountSwitches.get('loaded') as boolean,
  );

  useEffect(() => {
    if (!loaded) {
      void dispatch(fetchAccountSwitches());
    }
  }, [dispatch, loaded]);

  const poll = useCallback(async () => {
    if (!me || pollingRef.current) return;

    pollingRef.current = true;
    try {
      const counts = await apiGetLinkedUnreadCounts();
      dispatch(setLinkedUnreadCounts(counts));
    } catch {
      // Silently swallow polling errors
    } finally {
      pollingRef.current = false;
    }
  }, [dispatch]);

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
