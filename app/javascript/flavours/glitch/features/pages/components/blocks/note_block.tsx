import { useEffect, useState } from 'react';

import { fetchStatus } from 'flavours/glitch/actions/statuses';
import type { ApiPageNoteBlock } from 'flavours/glitch/api_types/pages';
import StatusContainer from 'flavours/glitch/containers/status_container';
import { useStatus } from 'flavours/glitch/hooks/useStatus';
import { useVisibility } from 'flavours/glitch/hooks/useVisibility';
import { useAppDispatch } from 'flavours/glitch/store';

import { usePageNoteFetch } from './note_fetch_context';

const Status = StatusContainer as unknown as React.FC<{
  id: string;
  contextType?: string;
  showActions?: boolean;
}>;

const observerOptions = { rootMargin: '400px 0px' };
const MAX_FETCH_RETRIES = 2;
const RETRY_DELAY_MS = 2_000;

export const NoteBlock: React.FC<{ block: ApiPageNoteBlock }> = ({ block }) => {
  const dispatch = useAppDispatch();
  const { begin, finish } = usePageNoteFetch();
  const { isIntersecting, observedRef } = useVisibility({ observerOptions });
  const [retryAttempt, setRetryAttempt] = useState(0);
  const statusId = block.note;
  const statusCached = useStatus(statusId) !== null;

  useEffect(() => {
    if (!statusId || statusCached || !isIntersecting || !begin(statusId)) {
      return undefined;
    }

    let active = true;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;

    void dispatch(fetchStatus(statusId, { alsoFetchContext: false })).then(
      (succeeded) => {
        finish(statusId);

        if (active && !succeeded && retryAttempt < MAX_FETCH_RETRIES) {
          retryTimer = setTimeout(
            () => {
              setRetryAttempt((attempt) => attempt + 1);
            },
            RETRY_DELAY_MS * (retryAttempt + 1),
          );
        }
      },
    );

    return () => {
      active = false;
      if (retryTimer) {
        clearTimeout(retryTimer);
      }
      finish(statusId);
    };
  }, [
    begin,
    dispatch,
    finish,
    isIntersecting,
    retryAttempt,
    statusCached,
    statusId,
  ]);

  if (!statusId) {
    return null;
  }

  return (
    <div ref={observedRef} className='page__block page__block--note'>
      <Status id={statusId} contextType='page' showActions={false} />
    </div>
  );
};
