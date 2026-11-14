export const createDriveFileAttachment = ({
  api,
  changeComposeSensitivity,
  showAlert,
  uploadComposeFail,
  uploadComposeRequest,
  uploadComposeSuccess,
  messages,
}) => (driveFileId, sensitive = false) => (dispatch, getState) => {
  if (getState().compose.get('quoted_status_id')) {
    dispatch(showAlert({ message: messages.uploadQuote }));
    return;
  }

  const uploadLimit = getState().getIn(['server', 'server', 'item', 'configuration', 'statuses', 'max_media_attachments']);
  const media = getState().getIn(['compose', 'media_attachments']);
  const pending = getState().getIn(['compose', 'pending_media_attachments']);

  if (media.size + pending + 1 > uploadLimit) {
    dispatch(showAlert({ message: messages.uploadErrorLimit }));
    return;
  }

  dispatch(uploadComposeRequest());

  api().post(`/api/v1/drive/files/${driveFileId}/attach`).then(({ data }) => {
    dispatch(uploadComposeSuccess(data, null));
    if (sensitive && !getState().getIn(['compose', 'sensitive'])) {
      dispatch(changeComposeSensitivity());
    }
  }).catch(error => dispatch(uploadComposeFail(error)));
};
