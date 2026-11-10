import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';

import { useDrive } from '../../use_drive';
import { DriveBrowser } from '../drive_browser';
import { FileCard } from '../file_card';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiGetDriveFiles: vi.fn(),
  apiGetDriveFolders: vi.fn(),
  apiGetDriveUsage: vi.fn(),
}));

vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
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

const makeFile = (
  id: string,
  type: ApiDriveFileJSON['type'],
): ApiDriveFileJSON => ({
  id,
  type,
  name: id,
  file_name: `${id}.png`,
  content_type: type === 'image' ? 'image/png' : 'video/mp4',
  description: id,
  url: `/${id}.png`,
  preview_url: `/${id}-preview.png`,
  meta: null,
  blurhash: null,
  sensitive: false,
  size: 100,
  folder_id: null,
  orphaned: true,
  created_at: '2026-10-22T00:00:00Z',
});

const ImagePicker = ({
  onSelectFile,
}: {
  onSelectFile: (file: ApiDriveFileJSON) => void;
}) => (
  <DriveBrowser
    drive={useDrive()}
    manageable={false}
    acceptedTypes={['image']}
    onSelectFile={onSelectFile}
  />
);

beforeEach(() => {
  vi.clearAllMocks();
  mocks.apiGetDriveFolders.mockResolvedValue([]);
  mocks.apiGetDriveUsage.mockResolvedValue(null);
});

afterEach(cleanup);

describe('Drive image picker pagination', () => {
  it('reaches images on later pages when the first page has no selectable files', async () => {
    const image = makeFile('Portrait', 'image');
    const next = '/api/v1/drive/files?max_id=older';
    mocks.apiGetDriveFiles
      .mockResolvedValueOnce({
        files: [makeFile('Movie', 'video'), makeFile('Animation', 'gifv')],
        links: { refs: [{ rel: 'next', uri: next }] },
      })
      .mockResolvedValueOnce({ files: [image], links: { refs: [] } });
    const onSelectFile = vi.fn();

    render(
      <IntlProvider locale='en'>
        <ImagePicker onSelectFile={onSelectFile} />
      </IntlProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Load more' }));

    const card = await screen.findByRole('button', {
      name: /Portrait/,
    });
    fireEvent.click(card);

    expect(mocks.apiGetDriveFiles).toHaveBeenLastCalledWith(undefined, next);
    expect(onSelectFile).toHaveBeenCalledWith(image);
    expect(screen.queryByRole('button', { name: 'Load more' })).toBeNull();
  });
});

describe('Drive file card keyboard handling', () => {
  it('does not open the viewer for keys pressed on inner action buttons', () => {
    const file = makeFile('Portrait', 'image');
    const onSelect = vi.fn();

    render(
      <IntlProvider locale='en'>
        <FileCard
          file={file}
          manageable
          draggable={false}
          onSelect={onSelect}
          onDelete={vi.fn()}
          onRename={vi.fn()}
          onTransferToPosts={vi.fn()}
        />
      </IntlProvider>,
    );

    const rename = screen.getByRole('button', { name: 'Rename file' });
    const enter = fireEvent.keyDown(rename, { key: 'Enter' });
    fireEvent.keyDown(rename, { key: ' ' });

    expect(enter).toBe(true);
    expect(onSelect).not.toHaveBeenCalled();

    fireEvent.keyDown(screen.getByTitle('Portrait'), { key: 'Enter' });

    expect(onSelect).toHaveBeenCalledWith(file);
  });
});
