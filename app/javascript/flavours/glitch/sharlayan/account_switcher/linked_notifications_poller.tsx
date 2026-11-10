import { useEffect, useCallback, useRef, useState } from 'react';

import { me } from 'flavours/glitch/initial_state';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { refreshAccountSwitches, setLinkedUnreadCounts } from './actions';
import { apiGetLinkedUnreadCounts } from './api';

const POLL_INTERVAL_MS = 5 * 60_000;
const INITIAL_RETRY_MS = 30_000;

export const LinkedNotificationsPoller: React.FC = () => {
  const dispatch = useAppDispatch();
  const pollingRef = useRef(false);

  const loaded = useAppSelector(
    (state) => state.accountSwitches.get('loaded') as boolean,
  );
  const hasAuthorizedLinkedAccounts = useAppSelector(
    (state) =>
      state.accountSwitches.get('parentSessionAuthorized') === true ||
      (
        state.accountSwitches.get('items') as
          | {
              some(
                predicate: (item: { get(key: string): unknown }) => boolean,
              ): boolean;
            }
          | undefined
      )?.some((item) => item.get('session_authorized') === true),
  );

  const [initialAttempt, setInitialAttempt] = useState(0);

  useEffect(() => {
    if (!me || loaded) return;

    let cancelled = false;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;
    const retry = () => {
      if (!cancelled) setInitialAttempt((attempt) => attempt + 1);
    };
    const handleVisibilityChange = () => {
      if (!document.hidden && retryTimer === undefined) retry();
    };

    void dispatch(refreshAccountSwitches())
      .unwrap()
      .then((data) => {
        if (data || cancelled) return;

        const delay = Math.min(
          INITIAL_RETRY_MS * 2 ** initialAttempt,
          POLL_INTERVAL_MS,
        );
        retryTimer = setTimeout(() => {
          retryTimer = undefined;
          if (!document.hidden) retry();
        }, delay);
        document.addEventListener('visibilitychange', handleVisibilityChange);
      });

    return () => {
      cancelled = true;
      if (retryTimer !== undefined) clearTimeout(retryTimer);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [dispatch, loaded, initialAttempt]);

  const poll = useCallback(async () => {
    if (!me || !hasAuthorizedLinkedAccounts || pollingRef.current) return;

    pollingRef.current = true;
    try {
      const switches = await dispatch(refreshAccountSwitches()).unwrap();
      if (!switches) return;
      if (
        !switches.parent_session_authorized &&
        !switches.children.some((item) => item.session_authorized)
      ) {
        dispatch(setLinkedUnreadCounts({}));
        return;
      }
      const counts = await apiGetLinkedUnreadCounts();
      dispatch(setLinkedUnreadCounts(counts));
    } catch {
    } finally {
      pollingRef.current = false;
    }
  }, [dispatch, hasAuthorizedLinkedAccounts]);

  useEffect(() => {
    if (!me || !loaded || !hasAuthorizedLinkedAccounts) return;

    let lastPolledAt = 0;
    const pollIfVisible = () => {
      if (document.hidden) return;
      lastPolledAt = Date.now();
      void poll();
    };
    const handleVisibilityChange = () => {
      if (!document.hidden && Date.now() - lastPolledAt >= POLL_INTERVAL_MS)
        pollIfVisible();
    };

    const initialTimer = setTimeout(pollIfVisible, 3_000);
    const intervalId = setInterval(pollIfVisible, POLL_INTERVAL_MS);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      clearTimeout(initialTimer);
      clearInterval(intervalId);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [hasAuthorizedLinkedAccounts, loaded, poll]);

  return null;
};
