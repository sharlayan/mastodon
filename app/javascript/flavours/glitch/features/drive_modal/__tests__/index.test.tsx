import { useCallback, useState } from 'react';

import { IntlProvider } from 'react-intl';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';

import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';

import { DriveModal } from '..';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiGetDriveFiles: vi.fn(),
  apiGetDriveFolders: vi.fn(),
  apiGetDriveUsage: vi.fn(),
}));

vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
}));

vi.mock('@/flavours/glitch/actions/compose', () => ({
  attachDriveFile: vi.fn(),
}));

vi.mock('@/flavours/glitch/api/drive', () => ({
  apiGetDriveFiles: mocks.apiGetDriveFiles,
  apiGetDriveFolders: mocks.apiGetDriveFolders,
  apiGetDriveUsage: mocks.apiGetDriveUsage,
  apiCreateDriveFolder: vi.fn(),
  apiDeleteDriveFile: vi.fn(),
  apiDeleteDriveFolder: vi.fn(),
  apiMoveDriveFile: vi.fn(),
  apiMoveDriveFolder: vi.fn(),
  apiRenameDriveFile: vi.fn(),
  apiTransferDriveFileToPosts: vi.fn(),
  apiUpdateDriveFolder: vi.fn(),
  apiUploadDriveFile: vi.fn(),
}));

const image: ApiDriveFileJSON = {
  id: 'image',
  type: 'image',
  name: 'Portrait',
  file_name: 'portrait.png',
  content_type: 'image/png',
  description: 'Portrait',
  url: '/portrait.png',
  preview_url: '/portrait-preview.png',
  meta: null,
  blurhash: null,
  sensitive: false,
  size: 100,
  folder_id: null,
  orphaned: true,
  created_at: '2026-10-22T00:00:00Z',
};

type ModalType = 'drive' | 'other';

const ModalHost = ({
  nextModal,
  onSelectFile,
}: {
  nextModal: ModalType;
  onSelectFile: (file: ApiDriveFileJSON) => Promise<void>;
}) => {
  const [modal, setModal] = useState<ModalType | null>('drive');
  const handleClose = useCallback(() => {
    setModal(null);
  }, []);
  const handleOpen = useCallback(() => {
    setModal(nextModal);
  }, [nextModal]);

  return (
    <>
      <button type='button' onClick={handleOpen}>
        Open another modal
      </button>
      {modal === 'drive' && (
        <DriveModal
          onClose={handleClose}
          onSelectFile={onSelectFile}
          acceptedTypes={['image']}
        />
      )}
      {modal === 'other' && <div role='dialog' aria-label='Other dialog' />}
    </>
  );
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.apiGetDriveFiles.mockResolvedValue({
    files: [image],
    links: { refs: [] },
  });
  mocks.apiGetDriveFolders.mockResolvedValue([]);
  mocks.apiGetDriveUsage.mockResolvedValue(null);
});

afterEach(cleanup);

describe('Drive selection completion', () => {
  it('closes after a successful selection while still mounted', async () => {
    const onClose = vi.fn();
    const onSelectFile = vi.fn().mockResolvedValue(undefined);

    render(
      <IntlProvider locale='en'>
        <DriveModal onClose={onClose} onSelectFile={onSelectFile} />
      </IntlProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: /Portrait/ }));

    await waitFor(() => {
      expect(onClose).toHaveBeenCalledOnce();
    });
    expect(onSelectFile).toHaveBeenCalledWith(image);
  });

  it('restores the picker after a failed selection while still mounted', async () => {
    const onClose = vi.fn();
    const onSelectFile = vi.fn().mockRejectedValue(new Error('Image rejected'));

    render(
      <IntlProvider locale='en'>
        <DriveModal onClose={onClose} onSelectFile={onSelectFile} />
      </IntlProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: /Portrait/ }));

    expect(
      await screen.findByRole('button', { name: /Portrait/ }),
    ).toBeTruthy();
    expect(onClose).not.toHaveBeenCalled();
  });

  it.each(['other', 'drive'] as const)(
    'preserves the new %s modal after closing a pending selection',
    async (nextModal) => {
      let resolveSelection!: () => void;
      const selection = new Promise<void>((resolve) => {
        resolveSelection = resolve;
      });
      const onSelectFile = vi.fn().mockReturnValue(selection);

      render(
        <IntlProvider locale='en'>
          <ModalHost nextModal={nextModal} onSelectFile={onSelectFile} />
        </IntlProvider>,
      );

      fireEvent.click(await screen.findByRole('button', { name: /Portrait/ }));
      expect(onSelectFile).toHaveBeenCalledWith(image);
      fireEvent.click(screen.getByRole('button', { name: 'Close' }));
      fireEvent.click(
        screen.getByRole('button', { name: 'Open another modal' }),
      );

      await act(async () => {
        resolveSelection();
        await selection;
      });

      expect(
        nextModal === 'drive'
          ? screen.getByRole('heading', { name: 'Attach from drive' })
          : screen.getByRole('dialog', { name: 'Other dialog' }),
      ).toBeTruthy();
    },
  );
});
