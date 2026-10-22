import PropTypes from 'prop-types';

import { IntlProvider } from 'react-intl';

import { fireEvent, render, screen } from '@testing-library/react';

import { AccountImageEdit } from '../image_edit';

const mocks = vi.hoisted(() => ({
  driveEnabled: true,
  state: {
    profileEdit: { imageInfo: { src: '', alt: '' } },
    server: { server: { item: undefined } },
  },
  dispatch: vi.fn(),
  patchProfile: vi.fn(),
  unwrap: vi.fn(),
}));

vi.mock('@/flavours/glitch/initial_state', () => ({
  get driveEnabled() {
    return mocks.driveEnabled;
  },
}));

vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (selector) => selector(mocks.state),
}));

vi.mock('@/flavours/glitch/reducers/slices/profile_edit', () => ({
  patchProfile: mocks.patchProfile,
  selectImageInfo: (state) => state.profileEdit.imageInfo,
}));

vi.mock('@/flavours/glitch/components/dropdown_menu', () => {
  const Dropdown = ({ items }) => (
    <div>
      {items.filter(Boolean).map((item) => (
        <button key={item.text} type='button' onClick={item.action}>
          {item.text}
        </button>
      ))}
    </div>
  );
  Dropdown.propTypes = {
    items: PropTypes.arrayOf(PropTypes.shape({
      text: PropTypes.string.isRequired,
      action: PropTypes.func,
    })).isRequired,
  };
  return { Dropdown };
});

vi.mock('@/flavours/glitch/components/icon_button', () => {
  const IconButton = ({ title, onClick }) => (
    <button type='button' onClick={onClick}>
      {title}
    </button>
  );
  IconButton.propTypes = {
    title: PropTypes.string.isRequired,
    onClick: PropTypes.func.isRequired,
  };
  return { IconButton };
});

const renderImageEdit = (location) =>
  render(
    <IntlProvider locale='en'>
      <AccountImageEdit location={location} />
    </IntlProvider>,
  );

beforeEach(() => {
  vi.clearAllMocks();
  mocks.driveEnabled = true;
  mocks.state.profileEdit.imageInfo = { src: '', alt: '' };
  mocks.state.server.server.item = undefined;
  mocks.patchProfile.mockImplementation((payload) => ({
    type: 'test/patchProfile',
    payload,
  }));
  mocks.unwrap.mockResolvedValue({});
  mocks.dispatch.mockImplementation((action) =>
    action.type === 'test/patchProfile' ? { unwrap: mocks.unwrap } : action,
  );
});

describe('Drive profile image selection', () => {
  it.each([
    ['avatar', ''],
    ['avatar', '/avatar.png'],
    ['header', ''],
    ['header', '/header.png'],
  ])('copies a selected image into %s with existing image %s', async (location, src) => {
    mocks.state.profileEdit.imageInfo.src = src;
    renderImageEdit(location);

    fireEvent.click(screen.getByRole('button', { name: 'Use image from Drive' }));

    const { modalType, modalProps } = mocks.dispatch.mock.calls[0][0].payload;
    expect(modalType).toBe('DRIVE');
    expect(modalProps).toMatchObject({
      acceptedTypes: ['image'],
      accept: 'image/jpeg,image/png,image/gif,image/webp',
    });

    await modalProps.onSelectFile({ id: 'drive-file', description: 'A landscape' });

    expect(mocks.patchProfile).toHaveBeenCalledWith({
      [`${location}_drive_file_id`]: 'drive-file',
      [`${location}_description`]: 'A landscape',
    });
    expect(mocks.unwrap).toHaveBeenCalledOnce();
  });

  it('passes failed profile updates back to the picker', async () => {
    renderImageEdit('avatar');
    fireEvent.click(screen.getByRole('button', { name: 'Use image from Drive' }));
    const { onSelectFile } = mocks.dispatch.mock.calls[0][0].payload.modalProps;
    const error = new Error('The Drive file was deleted');
    mocks.unwrap.mockRejectedValueOnce(error);

    await expect(onSelectFile({ id: 'deleted-file', description: null })).rejects.toBe(error);
    expect(mocks.patchProfile).toHaveBeenCalledWith({
      avatar_drive_file_id: 'deleted-file',
      avatar_description: '',
    });
  });

  it.each([
    ['avatar', 3],
    ['header', 5],
    ['avatar', undefined],
  ])('limits the %s description to %s Unicode code points', async (location, configuredLimit) => {
    if (configuredLimit !== undefined) {
      mocks.state.server.server.item = {
        configuration: {
          accounts: {
            max_avatar_description_length: 3,
            max_header_description_length: 5,
          },
        },
      };
    }
    renderImageEdit(location);
    fireEvent.click(screen.getByRole('button', { name: 'Use image from Drive' }));
    const { onSelectFile } = mocks.dispatch.mock.calls[0][0].payload.modalProps;

    await onSelectFile({ id: 'drive-file', description: '🐈'.repeat(151) });

    expect(mocks.patchProfile).toHaveBeenCalledWith({
      [`${location}_drive_file_id`]: 'drive-file',
      [`${location}_description`]: '🐈'.repeat(configuredLimit ?? 150),
    });
  });

  it.each(['', '/avatar.png'])('hides Drive when disabled with existing image %s', (src) => {
    mocks.driveEnabled = false;
    mocks.state.profileEdit.imageInfo.src = src;
    renderImageEdit('avatar');

    expect(screen.queryByRole('button', { name: 'Use image from Drive' })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: src ? 'Replace image' : 'Add image' }));
    expect(mocks.dispatch.mock.calls[0][0].payload).toEqual({
      modalType: 'ACCOUNT_EDIT_IMAGE_UPLOAD',
      modalProps: { location: 'avatar' },
    });
  });
});
