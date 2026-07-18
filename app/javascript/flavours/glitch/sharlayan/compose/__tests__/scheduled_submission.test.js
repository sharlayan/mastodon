import {
  getScheduledSubmissionContext,
  handleScheduledComposeSuccess,
  runScheduledComposeSubmission,
} from '../scheduled_submission';

describe('scheduled compose submission', () => {
  it('treats a scheduled redraft as a new status submission', () => {
    expect(getScheduledSubmissionContext({
      scheduledAt: '2026-07-18T01:00:00Z',
      statusId: 'scheduled-id',
    })).toEqual({
      editingScheduledId: 'scheduled-id',
      effectiveStatusId: null,
    });

    expect(getScheduledSubmissionContext({
      scheduledAt: null,
      statusId: 'status-id',
    })).toEqual({
      editingScheduledId: null,
      effectiveStatusId: 'status-id',
    });
  });

  it('deletes the previous schedule before submitting its replacement', async () => {
    const calls = [];
    const dispatch = vi.fn();

    await runScheduledComposeSubmission({
      deleteScheduledStatus: async (id) => calls.push(`delete:${id}`),
      dispatch,
      editingScheduledId: 'scheduled-id',
      onFailure: (error) => ({ type: 'FAIL', error }),
      submit: () => calls.push('submit'),
    });

    expect(calls).toEqual(['delete:scheduled-id', 'submit']);
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SCHEDULED_STATUS_DELETE_SUCCESS',
      id: 'scheduled-id',
    });
  });

  it('does not submit a replacement when deleting the old schedule fails', async () => {
    const error = new Error('delete failed');
    const dispatch = vi.fn();
    const submit = vi.fn();

    await runScheduledComposeSubmission({
      deleteScheduledStatus: async () => { throw error; },
      dispatch,
      editingScheduledId: 'scheduled-id',
      onFailure: (failure) => ({ type: 'FAIL', error: failure }),
      submit,
    });

    expect(submit).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith({ type: 'FAIL', error });
  });

  it('registers a scheduled response and skips ordinary success handling', () => {
    const dispatch = vi.fn();
    const data = {
      id: 'scheduled-id',
      scheduled_at: '2026-07-18T01:00:00Z',
    };

    expect(handleScheduledComposeSuccess({
      data,
      dispatch,
      formatDate: () => 'formatted date',
    })).toBe(true);
    expect(dispatch).toHaveBeenCalledTimes(2);

    expect(handleScheduledComposeSuccess({
      data: { id: 'status-id' },
      dispatch,
    })).toBe(false);
  });
});
