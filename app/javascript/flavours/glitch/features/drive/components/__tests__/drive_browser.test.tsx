import { IntlProvider } from 'react-intl';

import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';

import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';

import { useDrive } from '../../use_drive';
import { DriveBrowser } from '../drive_browser';
import { FileCard } from '../file_card';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiGetDriveFiles: vi.fn(),
  apiGetDriveFolders: vi.fn(),
  apiGetDriveUsage: vi.fn(),
  apiDeleteDriveFile: vi.fn(),
  apiDeleteDriveFolder: vi.fn(),
  apiMoveDriveFiles: vi.fn(),
  apiMoveDriveFolder: vi.fn(),
}));

vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (
    selector: (state: {
      dropdownMenu: { openId: null; keyboard: boolean };
    }) => unknown,
  ) => selector({ dropdownMenu: { openId: null, keyboard: false } }),
}));

vi.mock('@/flavours/glitch/api/drive', () => ({
  apiGetDriveFiles: mocks.apiGetDriveFiles,
  apiGetDriveFolders: mocks.apiGetDriveFolders,
  apiGetDriveUsage: mocks.apiGetDriveUsage,
  apiCreateDriveFolder: vi.fn(),
  apiDeleteDriveFile: mocks.apiDeleteDriveFile,
  apiDeleteDriveFolder: mocks.apiDeleteDriveFolder,
  apiMoveDriveFile: vi.fn(),
  apiMoveDriveFiles: mocks.apiMoveDriveFiles,
  apiMoveDriveFolder: mocks.apiMoveDriveFolder,
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

const folder = (id: string, parentId: string | null = null) => ({
  id,
  name: id,
  parent_id: parentId,
  files_count: 0,
  folders_count: 0,
  created_at: '2026-10-22T00:00:00Z',
});

const Manager = ({
  onSelectFile,
}: {
  onSelectFile: (file: ApiDriveFileJSON) => void;
}) => (
  <DriveBrowser drive={useDrive()} manageable onSelectFile={onSelectFile} />
);

const checkbox = (name: string) =>
  screen.getByRole<HTMLInputElement>('checkbox', { name: `Select ${name}` });

const renderManager = async (onSelectFile = vi.fn()) => {
  render(
    <IntlProvider locale='en'>
      <Manager onSelectFile={onSelectFile} />
    </IntlProvider>,
  );
  await screen.findByTitle('Gamma');

  return onSelectFile;
};

describe('Drive manager selection', () => {
  beforeEach(() => {
    mocks.apiGetDriveFolders.mockResolvedValue([folder('Album')]);
    mocks.apiGetDriveFiles.mockResolvedValue({
      files: ['Alpha', 'Beta', 'Gamma'].map((id) => makeFile(id, 'image')),
      links: { refs: [] },
    });
    mocks.apiDeleteDriveFile.mockResolvedValue({});
    mocks.apiDeleteDriveFolder.mockResolvedValue({});
    mocks.apiMoveDriveFiles.mockResolvedValue([]);
    vi.spyOn(window, 'confirm').mockReturnValue(true);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('selects with click, Shift and Ctrl, opens on double-click, and deletes the selection with the Delete key', async () => {
    const onSelectFile = await renderManager();

    fireEvent.click(screen.getByTitle('Alpha'));
    fireEvent.click(screen.getByTitle('Gamma'), { shiftKey: true });
    expect(
      ['Alpha', 'Beta', 'Gamma'].map((name) => checkbox(name).checked),
    ).toEqual([true, true, true]);

    fireEvent.click(screen.getByTitle('Beta'), { ctrlKey: true });
    expect(checkbox('Beta').checked).toBe(false);
    expect(screen.getByText('2 items selected')).toBeTruthy();
    expect(onSelectFile).not.toHaveBeenCalled();

    fireEvent.doubleClick(screen.getByTitle('Beta'));
    expect(onSelectFile).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'Beta' }),
    );

    fireEvent.keyDown(screen.getByTitle('Alpha'), { key: 'a', ctrlKey: true });
    expect(checkbox('Album').checked).toBe(true);

    fireEvent.keyDown(screen.getByTitle('Alpha'), { key: 'Delete' });

    await waitFor(() => {
      expect(mocks.apiDeleteDriveFolder).toHaveBeenCalledWith('Album');
    });
    expect(
      mocks.apiDeleteDriveFile.mock.calls.map(([id]) => id as string),
    ).toEqual(['Alpha', 'Beta', 'Gamma']);
  });

  it('shows item, selection, size and storage in the bottom status bar and the selection actions in the toolbar', async () => {
    mocks.apiGetDriveUsage.mockResolvedValue({
      used: 1024 * 1024,
      limit: 10 * 1024 * 1024,
      file_count: 3,
    });
    await renderManager();

    const statusBar = document.querySelector<HTMLElement>('.drive__status-bar');
    if (!statusBar) throw new Error('missing status bar');

    expect(statusBar.textContent).toContain('4 items');
    expect(await screen.findByText('1 MB of 10 MB used')).toBeTruthy();
    expect(screen.queryByRole('group', { name: 'Selected items' })).toBeNull();

    fireEvent.click(screen.getByTitle('Alpha'));
    fireEvent.click(screen.getByTitle('Beta'), { ctrlKey: true });

    expect(statusBar.textContent).toContain('2 items selected');
    expect(statusBar.textContent).toContain('200 B');
    expect(
      document
        .querySelector('.drive__toolbar')
        ?.contains(screen.getByRole('group', { name: 'Selected items' })),
    ).toBe(true);

    fireEvent.keyDown(screen.getByTitle('Alpha'), { key: 'a', ctrlKey: true });

    expect(statusBar.textContent).toContain('4 items selected');
    expect(statusBar.querySelector('.drive__status-bar__size')).toBeNull();
    expect(statusBar.lastElementChild?.classList.contains('drive__usage')).toBe(
      true,
    );
  });

  it('leaves the item count out of the status bar while the file list is still loading', async () => {
    mocks.apiGetDriveFiles.mockReturnValue(new Promise(() => undefined));

    render(
      <IntlProvider locale='en'>
        <Manager onSelectFile={vi.fn()} />
      </IntlProvider>,
    );
    await screen.findByTitle('Album');

    expect(
      document.querySelector('.drive__status-bar')?.textContent,
    ).not.toContain('item');
  });

  it('drags every selected file onto a folder and moves them in one bulk request', async () => {
    await renderManager();

    fireEvent.click(screen.getByTitle('Alpha'));
    fireEvent.click(screen.getByTitle('Beta'), { ctrlKey: true });

    const data = new Map<string, string>();
    const dataTransfer = {
      types: [] as string[],
      setData: (type: string, value: string) => {
        data.set(type, value);
        dataTransfer.types.push(type);
      },
      getData: (type: string) => data.get(type) ?? '',
      effectAllowed: '',
      dropEffect: '',
    };

    fireEvent.dragStart(screen.getByTitle('Beta'), { dataTransfer });
    const target = screen.getByTitle('Album');
    fireEvent.dragOver(target, { dataTransfer });
    fireEvent.drop(target, { dataTransfer });

    expect(mocks.apiMoveDriveFiles).toHaveBeenCalledWith(
      ['Alpha', 'Beta'],
      'Album',
    );
    await waitFor(() => {
      expect(screen.queryByTitle('Alpha')).toBeNull();
    });
    expect(screen.getByTitle('Gamma')).toBeTruthy();
  });

  it('selects the items under a rubber band dragged across empty space', async () => {
    await renderManager();

    const rects: Record<string, [number, number]> = {
      'folder:Album': [0, 0],
      'file:Alpha': [0, 100],
      'file:Beta': [200, 100],
      'file:Gamma': [400, 100],
    };
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: HTMLElement) {
        const [left, top] = rects[
          this.getAttribute('data-drive-item') ?? ''
        ] ?? [0, 0];
        const size = this.classList.contains('drive__body') ? 1000 : 50;
        return {
          left,
          top,
          width: size,
          height: size,
          right: left + size,
          bottom: top + size,
          x: left,
          y: top,
          toJSON: () => ({}),
        };
      },
    );
    HTMLElement.prototype.setPointerCapture = vi.fn();
    HTMLElement.prototype.hasPointerCapture = vi.fn(() => true);
    HTMLElement.prototype.releasePointerCapture = vi.fn();

    const body = document.querySelector<HTMLElement>('.drive__body');
    if (!body) throw new Error('missing drive body');
    const pointer = { pointerId: 1, pointerType: 'mouse', button: 0 };

    fireEvent.pointerDown(body, { ...pointer, clientX: 150, clientY: 90 });
    fireEvent.pointerMove(body, { ...pointer, clientX: 260, clientY: 160 });
    fireEvent.pointerUp(body, { ...pointer, clientX: 260, clientY: 160 });

    expect(
      ['Album', 'Alpha', 'Beta', 'Gamma'].map((name) => checkbox(name).checked),
    ).toEqual([false, false, true, false]);
  });
});
