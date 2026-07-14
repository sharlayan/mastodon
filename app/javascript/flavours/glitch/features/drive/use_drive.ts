import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages } from 'react-intl';

import { AxiosError } from 'axios';

import { showAlert, showAlertForError } from 'flavours/glitch/actions/alerts';
import {
  apiCreateDriveFolder,
  apiDeleteDriveFile,
  apiDeleteDriveFolder,
  apiGetDriveFiles,
  apiGetDriveFolders,
  apiGetDriveUsage,
  apiMoveDriveFile,
  apiMoveDriveFolder,
  apiRenameDriveFile,
  apiUpdateDriveFolder,
  apiUploadDriveFile,
} from 'flavours/glitch/api/drive';
import type {
  ApiDriveFileJSON,
  ApiDriveFolderJSON,
  ApiDriveUsageJSON,
} from 'flavours/glitch/api_types/drive';
import { useAppDispatch } from 'flavours/glitch/store';

export const ROOT_FOLDER_ID = null;

const messages = defineMessages({
  attachedFile: {
    id: 'drive.delete_attached_error',
    defaultMessage: 'Files attached to a post cannot be deleted.',
  },
});

const nextLink = (links: { refs: { rel: string; uri: string }[] }) =>
  links.refs.find((link) => link.rel === 'next')?.uri;

export const useDrive = () => {
  const dispatch = useAppDispatch();

  const [files, setFiles] = useState<ApiDriveFileJSON[]>([]);
  const [folders, setFolders] = useState<ApiDriveFolderJSON[]>([]);
  const [usage, setUsage] = useState<ApiDriveUsageJSON | null>(null);
  const [currentFolderId, setCurrentFolderId] = useState<string | null>(
    ROOT_FOLDER_ID,
  );
  const [orphanedOnly, setOrphanedOnly] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [next, setNext] = useState<string | undefined>();
  const [reloadKey, setReloadKey] = useState(0);

  const onError = useCallback(
    (error: unknown) => {
      dispatch(showAlertForError(error));
    },
    [dispatch],
  );

  const refreshUsage = useCallback(() => {
    apiGetDriveUsage()
      .then((data) => {
        setUsage(data);
        return data;
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    apiGetDriveFolders()
      .then((data) => {
        setFolders(data);
        return data;
      })
      .catch(onError);
  }, [onError]);

  useEffect(() => {
    refreshUsage();
  }, [refreshUsage]);

  useEffect(() => {
    let cancelled = false;

    apiGetDriveFiles(
      orphanedOnly ? { orphaned: true } : { folder_id: currentFolderId ?? '' },
    )
      .then(({ files: loaded, links }) => {
        if (cancelled) return loaded;
        setFiles(loaded);
        setNext(nextLink(links));
        return loaded;
      })
      .catch((error: unknown) => {
        if (!cancelled) onError(error);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [currentFolderId, orphanedOnly, reloadKey, onError]);

  const loadMore = useCallback(() => {
    if (!next || loadingMore) return;

    setLoadingMore(true);

    apiGetDriveFiles(undefined, next)
      .then(({ files: more, links }) => {
        setFiles((prev) => [...prev, ...more]);
        setNext(nextLink(links));
        return more;
      })
      .catch(onError)
      .finally(() => {
        setLoadingMore(false);
      });
  }, [next, loadingMore, onError]);

  const openFolder = useCallback(
    (folderId: string | null) => {
      if (folderId === currentFolderId && !orphanedOnly) return;

      setLoading(true);
      setNext(undefined);
      setOrphanedOnly(false);
      setCurrentFolderId(folderId);
    },
    [currentFolderId, orphanedOnly],
  );

  const toggleOrphanedOnly = useCallback(() => {
    setLoading(true);
    setNext(undefined);
    setOrphanedOnly((prev) => !prev);
  }, []);

  const uploadFiles = useCallback(
    (selected: FileList | File[]) => {
      const list = Array.from(selected);
      if (list.length === 0) return;

      setUploading(true);

      const targetFolderId = orphanedOnly ? null : currentFolderId;

      Promise.all(
        list.map((file) => {
          const data = new FormData();
          data.append('file', file);
          data.append('name', file.name);
          if (targetFolderId) data.append('folder_id', targetFolderId);
          return apiUploadDriveFile(data);
        }),
      )
        .then((uploaded) => {
          setFiles((prev) => {
            const known = new Set(prev.map((file) => file.id));
            return [...uploaded.filter((file) => !known.has(file.id)), ...prev];
          });
          refreshUsage();
          return uploaded;
        })
        .catch(onError)
        .finally(() => {
          setUploading(false);
        });
    },
    [currentFolderId, orphanedOnly, onError, refreshUsage],
  );

  const deleteFile = useCallback(
    (id: string) => {
      const target = files.find((file) => file.id === id);

      if (target && !target.orphaned) {
        dispatch(showAlert({ message: messages.attachedFile }));
        return;
      }

      apiDeleteDriveFile(id)
        .then(() => {
          setFiles((prev) => prev.filter((file) => file.id !== id));
          refreshUsage();
          return true;
        })
        .catch((error: unknown) => {
          if (
            error instanceof AxiosError &&
            error.response?.status === 422 &&
            target
          ) {
            setFiles((prev) =>
              prev.map((file) =>
                file.id === id ? { ...file, orphaned: false } : file,
              ),
            );
            dispatch(showAlert({ message: messages.attachedFile }));
            return;
          }

          onError(error);
        });
    },
    [files, dispatch, onError, refreshUsage],
  );

  const renameFile = useCallback(
    (id: string, name: string) => {
      apiRenameDriveFile(id, name)
        .then((updated) => {
          setFiles((prev) =>
            prev.map((file) => (file.id === id ? updated : file)),
          );
          return updated;
        })
        .catch(onError);
    },
    [onError],
  );

  const moveFile = useCallback(
    (id: string, folderId: string | null) => {
      const file = files.find((candidate) => candidate.id === id);
      if (!file || file.folder_id === folderId) return;

      setFiles((prev) => prev.filter((candidate) => candidate.id !== id));

      apiMoveDriveFile(id, folderId).catch((error: unknown) => {
        setFiles((prev) =>
          prev.some((candidate) => candidate.id === id)
            ? prev
            : [file, ...prev],
        );
        onError(error);
      });
    },
    [files, onError],
  );

  const createFolder = useCallback(
    (name: string) => {
      apiCreateDriveFolder({
        name,
        ...(currentFolderId ? { parent_id: currentFolderId } : {}),
      })
        .then((folder) => {
          setFolders((prev) => [...prev, folder]);
          return folder;
        })
        .catch(onError);
    },
    [currentFolderId, onError],
  );

  const renameFolder = useCallback(
    (id: string, name: string) => {
      apiUpdateDriveFolder(id, { name })
        .then((updated) => {
          setFolders((prev) =>
            prev.map((folder) => (folder.id === id ? updated : folder)),
          );
          return updated;
        })
        .catch(onError);
    },
    [onError],
  );

  const moveFolder = useCallback(
    (id: string, parentId: string | null) => {
      if (id === parentId) return;

      apiMoveDriveFolder(id, parentId)
        .then((updated) => {
          setFolders((prev) =>
            prev.map((folder) => (folder.id === id ? updated : folder)),
          );
          return updated;
        })
        .catch(onError);
    },
    [onError],
  );

  const deleteFolder = useCallback(
    (id: string) => {
      apiDeleteDriveFolder(id)
        .then(() => {
          setFolders((prev) =>
            prev
              .filter((folder) => folder.id !== id)
              .map((folder) =>
                folder.parent_id === id
                  ? { ...folder, parent_id: null }
                  : folder,
              ),
          );
          setCurrentFolderId((prev) => (prev === id ? ROOT_FOLDER_ID : prev));
          setNext(undefined);
          setLoading(true);
          setReloadKey((prev) => prev + 1);
          return true;
        })
        .catch(onError);
    },
    [onError],
  );

  const currentFolder = useMemo(
    () => folders.find((folder) => folder.id === currentFolderId) ?? null,
    [folders, currentFolderId],
  );

  const childFolders = useMemo(
    () => folders.filter((folder) => folder.parent_id === currentFolderId),
    [folders, currentFolderId],
  );

  const ancestors = useMemo(() => {
    const trail: ApiDriveFolderJSON[] = [];
    const seen = new Set<string>();

    let node = currentFolder;

    while (node && !seen.has(node.id)) {
      seen.add(node.id);
      trail.unshift(node);
      node = folders.find((folder) => folder.id === node?.parent_id) ?? null;
    }

    return trail;
  }, [currentFolder, folders]);

  const isDescendantOf = useCallback(
    (folderId: string, maybeAncestorId: string) => {
      const seen = new Set<string>();
      let node = folders.find((folder) => folder.id === folderId);

      while (node?.parent_id && !seen.has(node.id)) {
        seen.add(node.id);
        if (node.parent_id === maybeAncestorId) return true;
        node = folders.find((folder) => folder.id === node?.parent_id);
      }

      return false;
    },
    [folders],
  );

  return {
    files,
    folders,
    usage,
    childFolders,
    ancestors,
    currentFolder,
    currentFolderId,
    orphanedOnly,
    loading,
    loadingMore,
    uploading,
    hasMore: Boolean(next),
    openFolder,
    toggleOrphanedOnly,
    loadMore,
    uploadFiles,
    deleteFile,
    renameFile,
    moveFile,
    createFolder,
    renameFolder,
    moveFolder,
    deleteFolder,
    isDescendantOf,
  };
};

export type DriveState = ReturnType<typeof useDrive>;
