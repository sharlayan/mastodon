import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { DriveManagerModal } from '../drive_manager_modal';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
}));

vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal()),
  useHistory: () => ({ action: 'PUSH' }),
  useLocation: () => ({
    pathname: '/',
    search: '',
    hash: '',
    state: undefined,
  }),
}));
vi.mock('@/flavours/glitch/store', async () => ({
  createAppSelector: (await import('@reduxjs/toolkit')).createSelector,
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (
    selector: (state: {
      dropdownMenu: { openId: null; keyboard: boolean };
    }) => unknown,
  ) => selector({ dropdownMenu: { openId: null, keyboard: false } }),
}));

vi.mock('@/flavours/glitch/api/drive', () => ({
  apiGetDriveFiles: vi.fn(() =>
    Promise.resolve({ files: [], links: { refs: [] } }),
  ),
  apiGetDriveFolders: vi.fn(() => Promise.resolve([])),
  apiGetDriveUsage: vi.fn(() => Promise.resolve(null)),
  apiGetDriveSettings: vi.fn(() =>
    Promise.resolve({
      keep_original_filename: true,
      default_folder_id: null,
      upload_original_image: true,
    }),
  ),
  apiUpdateDriveSettings: vi.fn(),
  apiCreateDriveFolder: vi.fn(),
  apiDeleteDriveFile: vi.fn(),
  apiDeleteDriveFolder: vi.fn(),
  apiMoveDriveFiles: vi.fn(),
  apiMoveDriveFolder: vi.fn(),
  apiRenameDriveFile: vi.fn(),
  apiTransferDriveFileToPosts: vi.fn(),
  apiUpdateDriveFolder: vi.fn(),
  apiUploadDriveFile: vi.fn(),
}));

afterEach(cleanup);

describe('DriveManagerModal', () => {
  it('shows the managing browser, toggles Drive settings and closes', async () => {
    const onClose = vi.fn();

    render(
      <IntlProvider locale='en'>
        <DriveManagerModal onClose={onClose} />
      </IntlProvider>,
    );

    expect(screen.getByRole('heading', { name: 'Drive' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Manage' })).toBeTruthy();
    expect(await screen.findByText('No files here yet.')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Drive settings' }));
    expect(
      await screen.findByText('Keep original file names when uploading'),
    ).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Close' }));
    expect(onClose).toHaveBeenCalled();
  });
});
