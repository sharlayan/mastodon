import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, waitFor } from '@testing-library/react';

import { ImageUploadField } from '../image_upload_field';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiUploadPageMedia: vi.fn(),
  openModal: vi.fn((payload: unknown) => ({ type: 'OPEN_MODAL', payload })),
}));

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
}));

vi.mock('flavours/glitch/actions/modal', () => ({
  openModal: mocks.openModal,
}));

vi.mock('flavours/glitch/api/pages', () => ({
  apiUploadPageMedia: mocks.apiUploadPageMedia,
}));

vi.mock('flavours/glitch/api/drive', () => ({
  apiAttachDriveFile: vi.fn(),
}));

vi.mock('flavours/glitch/initial_state', () => ({
  driveEnabled: false,
  pagesDriveOnly: false,
}));

const renderField = (crop?: boolean) => {
  const onChange = vi.fn();
  const { container } = render(
    <IntlProvider locale='en'>
      <ImageUploadField value={null} onChange={onChange} crop={crop} />
    </IntlProvider>,
  );
  const input = container.querySelector('input[type="file"]');
  if (!input) throw new Error('file input missing');
  return { input, onChange };
};

const gif = () => new File(['GIF89a'], 'anim.gif', { type: 'image/gif' });

describe('ImageUploadField', () => {
  afterEach(() => {
    cleanup();
    vi.clearAllMocks();
  });

  it('uploads the original file without cropping by default', async () => {
    const media = { id: '1', url: 'x' };
    mocks.apiUploadPageMedia.mockResolvedValue(media);
    const { input, onChange } = renderField();
    const file = gif();

    fireEvent.change(input, { target: { files: [file] } });

    await waitFor(() => {
      expect(onChange).toHaveBeenCalledWith(media);
    });
    expect(mocks.apiUploadPageMedia).toHaveBeenCalledWith(file);
    expect(mocks.openModal).not.toHaveBeenCalled();
  });

  it('opens the crop modal when cropping is enabled', async () => {
    const { input } = renderField(true);

    fireEvent.change(input, { target: { files: [gif()] } });

    await waitFor(() => {
      expect(mocks.openModal).toHaveBeenCalledWith(
        expect.objectContaining({ modalType: 'BOOKLET_COVER_CROP' }),
      );
    });
    expect(mocks.apiUploadPageMedia).not.toHaveBeenCalled();
  });
});
