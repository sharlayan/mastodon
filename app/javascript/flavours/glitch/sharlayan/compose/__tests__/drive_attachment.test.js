import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { createDriveFileAttachment } from '../drive_attachment';

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

const state = ({ quotedStatusId = null, media = ImmutableList(), pending = 0, sensitive = false } = {}) => {
  const compose = ImmutableMap({
    quoted_status_id: quotedStatusId,
    media_attachments: media,
    pending_media_attachments: pending,
    sensitive,
  });
  const server = ImmutableMap({
    server: ImmutableMap({
      item: ImmutableMap({
        configuration: ImmutableMap({
          statuses: ImmutableMap({ max_media_attachments: 4 }),
        }),
      }),
    }),
  });

  return {
    compose,
    getIn: ([namespace, ...path]) => (namespace === 'compose' ? compose : server).getIn(path),
  };
};

describe('drive compose attachment', () => {
  const messages = { uploadQuote: 'quote', uploadErrorLimit: 'limit' };

  const setup = ({ currentState = state(), response = Promise.resolve({ data: { id: 'drive-media' } }) } = {}) => {
    const client = { post: vi.fn(() => response) };
    const api = vi.fn(() => client);
    const showAlert = vi.fn(payload => ({ type: 'ALERT', ...payload }));
    const uploadComposeRequest = vi.fn(() => ({ type: 'REQUEST' }));
    const uploadComposeSuccess = vi.fn((media, file) => ({ type: 'SUCCESS', media, file }));
    const uploadComposeFail = vi.fn(error => ({ type: 'FAIL', error }));
    const changeComposeSensitivity = vi.fn(() => ({ type: 'SENSITIVE' }));
    const attach = createDriveFileAttachment({ api, changeComposeSensitivity, showAlert, uploadComposeFail, uploadComposeRequest, uploadComposeSuccess, messages });

    return { api, attach, changeComposeSensitivity, client, dispatch: vi.fn(), showAlert, uploadComposeRequest, uploadComposeSuccess, currentState };
  };

  it('rejects attachments to quoted posts before contacting Drive', () => {
    const test = setup({ currentState: state({ quotedStatusId: 'quoted-status' }) });

    test.attach('drive-file')(test.dispatch, () => test.currentState);

    expect(test.api).not.toHaveBeenCalled();
    expect(test.dispatch).toHaveBeenCalledWith({ type: 'ALERT', message: 'quote' });
  });

  it('keeps the compose media limit before contacting Drive', () => {
    const test = setup({ currentState: state({ media: ImmutableList([1, 2, 3]), pending: 1 }) });

    test.attach('drive-file')(test.dispatch, () => test.currentState);

    expect(test.api).not.toHaveBeenCalled();
    expect(test.dispatch).toHaveBeenCalledWith({ type: 'ALERT', message: 'limit' });
  });

  it('attaches the Drive media and applies its sensitive flag', async () => {
    const test = setup();

    test.attach('drive-file', true)(test.dispatch, () => test.currentState);
    await flushPromises();

    expect(test.client.post).toHaveBeenCalledWith('/api/v1/drive/files/drive-file/attach');
    expect(test.dispatch).toHaveBeenCalledWith({ type: 'REQUEST' });
    expect(test.dispatch).toHaveBeenCalledWith({ type: 'SUCCESS', media: { id: 'drive-media' }, file: null });
    expect(test.dispatch).toHaveBeenCalledWith({ type: 'SENSITIVE' });
  });
});
