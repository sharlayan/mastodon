import api, {
  apiRequestPost,
  apiRequestPut,
  apiRequestDelete,
  apiRequestGet,
  getLinks,
} from 'flavours/glitch/api';
import type {
  ApiDriveFileJSON,
  ApiDriveFolderJSON,
  ApiDriveSettingsJSON,
  ApiDriveUsageJSON,
} from 'flavours/glitch/api_types/drive';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';

export const apiGetDriveFiles = async (
  params?: {
    folder_id?: string;
    orphaned?: boolean;
    max_id?: string;
  },
  url?: string,
) => {
  const response = await api().request<ApiDriveFileJSON[]>({
    method: 'GET',
    url: url ?? '/api/v1/drive/files',
    params,
  });

  return {
    files: response.data,
    links: getLinks(response),
  };
};

export const apiUploadDriveFile = (
  data: FormData,
  onUploadProgress?: (progressEvent: { loaded: number }) => void,
) =>
  api()
    .post<ApiDriveFileJSON>('/api/v1/drive/files', data, { onUploadProgress })
    .then((response) => response.data);

export const apiUpdateDriveFile = (
  id: string,
  params: Partial<ApiDriveFileJSON>,
) => apiRequestPut<ApiDriveFileJSON>(`v1/drive/files/${id}`, params);

export const apiRenameDriveFile = (id: string, name: string) =>
  apiRequestPut<ApiDriveFileJSON>(`v1/drive/files/${id}`, { name });

export const apiMoveDriveFile = (id: string, folderId: string | null) =>
  apiRequestPut<ApiDriveFileJSON>(`v1/drive/files/${id}`, {
    folder_id: folderId ?? '',
  });

export const apiDeleteDriveFile = (id: string) =>
  apiRequestDelete(`v1/drive/files/${id}`);

export const apiAttachDriveFile = (id: string) =>
  apiRequestPost<ApiMediaAttachmentJSON>(`v1/drive/files/${id}/attach`);

export const apiTransferDriveFileToPosts = (id: string) =>
  apiRequestPost<{ transferred: number }>(
    `v1/drive/files/${id}/transfer_to_posts`,
  );

export const apiGetDriveFolders = () =>
  apiRequestGet<ApiDriveFolderJSON[]>('v1/drive/folders');

export const apiCreateDriveFolder = (params: {
  name: string;
  parent_id?: string;
}) => apiRequestPost<ApiDriveFolderJSON>('v1/drive/folders', params);

export const apiUpdateDriveFolder = (
  id: string,
  params: { name?: string; parent_id?: string },
) => apiRequestPut<ApiDriveFolderJSON>(`v1/drive/folders/${id}`, params);

export const apiMoveDriveFolder = (id: string, parentId: string | null) =>
  apiRequestPut<ApiDriveFolderJSON>(`v1/drive/folders/${id}`, {
    parent_id: parentId ?? '',
  });

export const apiDeleteDriveFolder = (id: string) =>
  apiRequestDelete(`v1/drive/folders/${id}`);

export const apiGetDriveUsage = () =>
  apiRequestGet<ApiDriveUsageJSON>('v1/drive/usage');

export const apiGetDriveSettings = () =>
  apiRequestGet<ApiDriveSettingsJSON>('v1/drive/settings');

export const apiUpdateDriveSettings = (settings: ApiDriveSettingsJSON) =>
  apiRequestPut<ApiDriveSettingsJSON>('v1/drive/settings', settings);
