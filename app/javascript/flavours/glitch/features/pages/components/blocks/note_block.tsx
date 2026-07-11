import { useEffect } from 'react';

import { fetchStatus } from 'flavours/glitch/actions/statuses';
import type { ApiPageNoteBlock } from 'flavours/glitch/api_types/pages';
import StatusContainer from 'flavours/glitch/containers/status_container';
import { useAppDispatch } from 'flavours/glitch/store';

const Status = StatusContainer as unknown as React.FC<{
  id: string;
  contextType?: string;
}>;

export const NoteBlock: React.FC<{ block: ApiPageNoteBlock }> = ({ block }) => {
  const dispatch = useAppDispatch();
  const statusId = block.note;

  useEffect(() => {
    if (statusId) {
      dispatch(fetchStatus(statusId));
    }
  }, [dispatch, statusId]);

  if (!statusId) {
    return null;
  }

  return (
    <div className='page__block page__block--note'>
      <Status id={statusId} contextType='page' />
    </div>
  );
};
