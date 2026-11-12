import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

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
  apiMoveDriveFiles,
  apiMoveDriveFolder,
  apiRenameDriveFile,
  apiTransferDriveFileToPosts,
  apiUpdateDriveFolder,
  apiUploadDriveFile,
} from 'flavours/glitch/api/drive';
import type {
  ApiDriveFileJSON,
  ApiDriveFolderJSON,
  ApiDriveUsageJSON,
} from 'flavours/glitch/api_types/drive';
import { useAppDispatch } from 'flavours/glitch/store';

import type { DriveItems } from './dnd';

export const ROOT_FOLDER_ID = null;

const MOVE_BULK_LIMIT = 100;

const messages = defineMessages({
  attachedFile: {
    id: 'drive.delete_attached_error',
    defaultMessage: 'Files used by a post or page cannot be deleted.',
  },
  skippedInUse: {
    id: 'drive.delete_selected_skipped',
    defaultMessage:
      '{count, plural, one {# file is} other {# files are}} used by a post or page and {count, plural, one {was} other {were}} not deleted.',
  },
  transferred: {
    id: 'drive.transfer_to_posts_success',
    defaultMessage:
      'The file was moved out of Drive and copied to {count, plural, one {# post attachment} other {# post attachments}}.',
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
  const viewGeneration = useRef(0);

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
    viewGeneration.current += 1;

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
        if (cancelled) return;
        setFiles([]);
        setNext(undefined);
        onError(error);
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
    const generation = viewGeneration.current;

    apiGetDriveFiles(undefined, next)
      .then(({ files: more, links }) => {
        if (generation !== viewGeneration.current) return more;
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
      setFiles([]);
      setNext(undefined);
      setOrphanedOnly(false);
      setCurrentFolderId(folderId);
    },
    [currentFolderId, orphanedOnly],
  );

  const toggleOrphanedOnly = useCallback(() => {
    setLoading(true);
    setFiles([]);
    setNext(undefined);
    setOrphanedOnly((prev) => !prev);
  }, []);

  const uploadFiles = useCallback(
    (selected: FileList | File[]) => {
      const list = Array.from(selected);
      if (list.length === 0) return;

      setUploading(true);

      const targetFolderId = orphanedOnly ? null : currentFolderId;
      const generation = viewGeneration.current;

      void Promise.allSettled(
        list.map((file) => {
          const data = new FormData();
          data.append('file', file);
          data.append('name', file.name);
          if (targetFolderId) data.append('folder_id', targetFolderId);
          return apiUploadDriveFile(data);
        }),
      ).then((results) => {
        const uploaded: ApiDriveFileJSON[] = [];

        results.forEach((result) => {
          if (result.status === 'fulfilled') {
            uploaded.push(result.value);
          } else {
            onError(result.reason);
          }
        });

        if (uploaded.length > 0 && generation === viewGeneration.current) {
          setFiles((prev) => {
            const known = new Set(prev.map((file) => file.id));
            return [...uploaded.filter((file) => !known.has(file.id)), ...prev];
          });
        }

        refreshUsage();
        setUploading(false);
        return uploaded;
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

  const transferFileToPosts = useCallback(
    (id: string) => {
      apiTransferDriveFileToPosts(id)
        .then(({ transferred }) => {
          setFiles((prev) => prev.filter((file) => file.id !== id));
          refreshUsage();
          dispatch(
            showAlert({
              message: messages.transferred,
              values: { count: transferred },
            }),
          );
          return transferred;
        })
        .catch(onError);
    },
    [dispatch, onError, refreshUsage],
  );

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

  const canMoveFolderTo = useCallback(
    (folderId: string, targetId: string | null) => {
      const folder = folders.find((candidate) => candidate.id === folderId);
      if (!folder || folder.parent_id === targetId) return false;
      if (targetId === null) return true;

      return folderId !== targetId && !isDescendantOf(targetId, folderId);
    },
    [folders, isDescendantOf],
  );

  const moveItems = useCallback(
    (items: DriveItems, targetId: string | null) => {
      const movingFiles = files.filter(
        (file) =>
          items.fileIds.includes(file.id) && file.folder_id !== targetId,
      );
      const movingFolderIds = items.folderIds.filter((id) =>
        canMoveFolderTo(id, targetId),
      );

      if (movingFiles.length > 0) {
        const movedIds = new Set(movingFiles.map((file) => file.id));
        const ids = movingFiles.map((file) => file.id);
        const chunks: string[][] = [];

        for (let index = 0; index < ids.length; index += MOVE_BULK_LIMIT) {
          chunks.push(ids.slice(index, index + MOVE_BULK_LIMIT));
        }

        if (!orphanedOnly) {
          setFiles((prev) => prev.filter((file) => !movedIds.has(file.id)));
        }

        Promise.all(chunks.map((chunk) => apiMoveDriveFiles(chunk, targetId)))
          .then((results) => {
            const updated = new Map(
              results.flat().map((file) => [file.id, file]),
            );

            if (orphanedOnly) {
              setFiles((prev) =>
                prev.map((file) => updated.get(file.id) ?? file),
              );
            }

            return updated;
          })
          .catch((error: unknown) => {
            if (!orphanedOnly) {
              setFiles((prev) => {
                const known = new Set(prev.map((file) => file.id));
                return [
                  ...movingFiles.filter((file) => !known.has(file.id)),
                  ...prev,
                ];
              });
            }

            onError(error);
          });
      }

      if (movingFolderIds.length > 0) {
        void Promise.allSettled(
          movingFolderIds.map((id) => apiMoveDriveFolder(id, targetId)),
        ).then((results) => {
          const updated = new Map<string, ApiDriveFolderJSON>();

          results.forEach((result) => {
            if (result.status === 'fulfilled') {
              updated.set(result.value.id, result.value);
            } else {
              onError(result.reason);
            }
          });

          setFolders((prev) =>
            prev.map((folder) => updated.get(folder.id) ?? folder),
          );

          return updated;
        });
      }
    },
    [files, orphanedOnly, canMoveFolderTo, onError],
  );

  const deleteItems = useCallback(
    (items: DriveItems) => {
      const targets = files.filter((file) => items.fileIds.includes(file.id));
      const deletable = targets.filter((file) => file.orphaned);
      const inUse = new Set(
        targets.filter((file) => !file.orphaned).map((file) => file.id),
      );

      const requests = [
        ...deletable.map((file) =>
          apiDeleteDriveFile(file.id).then(() => ({
            kind: 'file' as const,
            id: file.id,
          })),
        ),
        ...items.folderIds.map((id) =>
          apiDeleteDriveFolder(id).then(() => ({
            kind: 'folder' as const,
            id,
          })),
        ),
      ];
      const requestedIds = [
        ...deletable.map((file) => ({ kind: 'file' as const, id: file.id })),
        ...items.folderIds.map((id) => ({ kind: 'folder' as const, id })),
      ];

      void Promise.allSettled(requests).then((results) => {
        const deletedFiles = new Set<string>();
        const deletedFolders = new Set<string>();

        results.forEach((result, index) => {
          const request = requestedIds[index];
          if (!request) return;

          if (result.status === 'fulfilled') {
            (request.kind === 'file' ? deletedFiles : deletedFolders).add(
              request.id,
            );
          } else if (
            request.kind === 'file' &&
            result.reason instanceof AxiosError &&
            result.reason.response?.status === 422
          ) {
            inUse.add(request.id);
          } else {
            onError(result.reason);
          }
        });

        setFiles((prev) =>
          prev
            .filter((file) => !deletedFiles.has(file.id))
            .map((file) =>
              inUse.has(file.id) ? { ...file, orphaned: false } : file,
            ),
        );

        if (deletedFolders.size > 0) {
          apiGetDriveFolders()
            .then((data) => {
              setFolders(data);
              return data;
            })
            .catch(onError);
          setCurrentFolderId((prev) =>
            prev && deletedFolders.has(prev) ? ROOT_FOLDER_ID : prev,
          );
          setNext(undefined);
          setLoading(true);
          setReloadKey((prev) => prev + 1);
        }

        if (deletedFiles.size > 0) refreshUsage();

        if (inUse.size > 0) {
          dispatch(
            showAlert({
              message: messages.skippedInUse,
              values: { count: inUse.size },
            }),
          );
        }

        return results;
      });
    },
    [files, dispatch, onError, refreshUsage],
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

  return {
    files,
    folders,
    usage,
    onError,
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
    transferFileToPosts,
    moveItems,
    deleteItems,
    createFolder,
    renameFolder,
    deleteFolder,
    isDescendantOf,
    canMoveFolderTo,
  };
};

export type DriveState = ReturnType<typeof useDrive>;
