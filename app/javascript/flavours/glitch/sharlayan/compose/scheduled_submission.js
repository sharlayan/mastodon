import { defineMessages } from 'react-intl';

import api from 'flavours/glitch/api';
import { showAlert } from 'flavours/glitch/actions/alerts';
import {
  addScheduledStatus,
  SCHEDULED_STATUS_DELETE_SUCCESS,
} from 'flavours/glitch/actions/scheduled_statuses';

const messages = defineMessages({
  scheduledFor: {
    id: 'compose.scheduled_for',
    defaultMessage: 'Scheduled for {time}',
  },
});

export const getScheduledSubmissionContext = ({ scheduledAt, statusId }) => {
  const isRedraftingScheduled = Boolean(statusId && scheduledAt);

  return {
    editingScheduledId: isRedraftingScheduled ? statusId : null,
    effectiveStatusId: isRedraftingScheduled ? null : statusId,
  };
};

export const handleScheduledComposeSuccess = ({
  data,
  dispatch,
  formatDate = (scheduledAt) => new Date(scheduledAt).toLocaleString(
    undefined,
    { dateStyle: 'short', timeStyle: 'short' },
  ),
}) => {
  if (!data?.scheduled_at) return false;

  dispatch(addScheduledStatus(data));
  dispatch(showAlert({
    message: messages.scheduledFor,
    values: { time: formatDate(data.scheduled_at) },
    dismissAfter: 5000,
  }));

  return true;
};

export const runScheduledComposeSubmission = ({
  dispatch,
  editingScheduledId,
  onFailure,
  submit,
  deleteScheduledStatus = (id) => api().delete(`/api/v1/scheduled_statuses/${id}`),
}) => {
  if (!editingScheduledId) return submit();

  return deleteScheduledStatus(editingScheduledId).then(() => {
    dispatch({
      type: SCHEDULED_STATUS_DELETE_SUCCESS,
      id: editingScheduledId,
    });
    return submit();
  }).catch((error) => {
    dispatch(onFailure(error));
  });
};
