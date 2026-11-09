import { act, renderHook, waitFor } from '@testing-library/react';
import { vi } from 'vitest';

import {
  apiGetDriveFiles,
  apiGetDriveFolders,
  apiGetDriveUsage,
  apiUploadDriveFile,
} from '@/flavours/glitch/api/drive';
import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';

import { useDrive } from './use_drive';

const dispatch = vi.hoisted(() => vi.fn());

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppDispatch: () => dispatch,
}));

vi.mock('@/flavours/glitch/api/drive', () => ({
  apiCreateDriveFolder: vi.fn(),
  apiDeleteDriveFile: vi.fn(),
  apiDeleteDriveFolder: vi.fn(),
  apiGetDriveFiles: vi.fn(),
  apiGetDriveFolders: vi.fn(() => Promise.resolve([])),
  apiGetDriveUsage: vi.fn(() => Promise.resolve(null)),
  apiMoveDriveFile: vi.fn(),
  apiMoveDriveFolder: vi.fn(),
  apiRenameDriveFile: vi.fn(),
  apiTransferDriveFileToPosts: vi.fn(),
  apiUpdateDriveFolder: vi.fn(),
  apiUploadDriveFile: vi.fn(),
}));

type FilesResult = Awaited<ReturnType<typeof apiGetDriveFiles>>;

const file = (id: string) => ({ id }) as unknown as ApiDriveFileJSON;
const page = (ids: string[], next?: string) =>
  ({
    files: ids.map(file),
    links: { refs: next ? [{ rel: 'next', uri: next }] : [] },
  }) as unknown as FilesResult;

describe('useDrive', () => {
  beforeEach(() => {
    vi.mocked(apiGetDriveFolders).mockResolvedValue([]);
    vi.mocked(apiGetDriveUsage).mockResolvedValue(
      null as unknown as Awaited<ReturnType<typeof apiGetDriveUsage>>,
    );
  });

  it('drops a load-more page that returns after another folder was opened', async () => {
    let resolveMore: (value: FilesResult) => void = () => undefined;
    vi.mocked(apiGetDriveFiles).mockImplementation((params, url) => {
      if (url) {
        return new Promise((resolve) => {
          resolveMore = resolve;
        });
      }

      return Promise.resolve(
        params?.folder_id === 'b'
          ? page(['b1'])
          : page(['root1'], '/api/v1/drive/files?max_id=root1'),
      );
    });

    const { result } = renderHook(() => useDrive());
    await waitFor(() => {
      expect(result.current.files.map((entry) => entry.id)).toEqual(['root1']);
    });

    act(() => {
      result.current.loadMore();
    });
    act(() => {
      result.current.openFolder('b');
    });
    await waitFor(() => {
      expect(result.current.files.map((entry) => entry.id)).toEqual(['b1']);
    });

    await act(async () => {
      resolveMore(page(['root2'], '/api/v1/drive/files?max_id=root2'));
      await Promise.resolve();
    });

    expect(result.current.files.map((entry) => entry.id)).toEqual(['b1']);
  });

  it('keeps the uploaded files and refreshes usage when another upload fails', async () => {
    vi.mocked(apiGetDriveFiles).mockResolvedValue(page(['existing']));
    vi.mocked(apiUploadDriveFile).mockImplementation((data: FormData) => {
      const name = data.get('name') as string;
      return name === 'bad.png'
        ? Promise.reject(new Error('too large'))
        : Promise.resolve(file(`uploaded-${name}`));
    });
    dispatch.mockClear();

    const { result } = renderHook(() => useDrive());
    await waitFor(() => {
      expect(result.current.files.map((entry) => entry.id)).toEqual([
        'existing',
      ]);
    });
    vi.mocked(apiGetDriveUsage).mockClear();

    act(() => {
      result.current.uploadFiles([
        new File(['a'], 'good.png'),
        new File(['b'], 'bad.png'),
      ]);
    });

    await waitFor(() => {
      expect(result.current.uploading).toBe(false);
    });
    expect(result.current.files.map((entry) => entry.id)).toEqual([
      'uploaded-good.png',
      'existing',
    ]);
    expect(apiGetDriveUsage).toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledTimes(1);
  });
});
