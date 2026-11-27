import { fetchStatus, STATUS_FETCH_FAIL } from 'flavours/glitch/actions/statuses';
import { fetchContext } from 'flavours/glitch/actions/statuses_typed';
import { localStatusPageAccess } from 'flavours/glitch/initial_state';

export const statusPageMayRequireLogin = (signedIn) =>
  !signedIn && localStatusPageAccess !== 'public';

export const fetchStatusWatchingLoginRequirement = (statusId, onLoginRequired) => (dispatch, getState) =>
  fetchStatus(statusId, { forceFetch: true, alsoFetchContext: false })(action => {
    if (action?.type === STATUS_FETCH_FAIL && action.id === statusId && action.error?.status === 422) {
      onLoginRequired(statusId);
    }

    return dispatch(action);
  }, getState).then(found => {
    if (found) {
      dispatch(fetchContext({ statusId }));
    }

    return found;
  });
