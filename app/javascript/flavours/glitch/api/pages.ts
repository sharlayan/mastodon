import {
  apiRequestPost,
  apiRequestPut,
  apiRequestGet,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

export const apiGetPages = () => apiRequestGet<ApiPageJSON[]>('v1/pages');

export const apiGetFeaturedPages = () =>
  apiRequestGet<ApiPageJSON[]>('v1/pages/featured');

export const apiGetAccountPages = (accountId: string) =>
  apiRequestGet<ApiPageJSON[]>(`v1/accounts/${accountId}/pages`);

export const apiGetAccountPage = (accountId: string, name: string) =>
  apiRequestGet<ApiPageJSON>(
    `v1/accounts/${accountId}/pages/${encodeURIComponent(name)}`,
  );

export const apiGetPage = (pageId: string) =>
  apiRequestGet<ApiPageJSON>(`v1/pages/${pageId}`);

export const apiCreatePage = (page: Partial<ApiPageJSON>) =>
  apiRequestPost<ApiPageJSON>('v1/pages', page);

export const apiUpdatePage = (pageId: string, page: Partial<ApiPageJSON>) =>
  apiRequestPut<ApiPageJSON>(`v1/pages/${pageId}`, page);

export const apiDeletePage = (pageId: string) =>
  apiRequestDelete(`v1/pages/${pageId}`);

export const apiLikePage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/like`);

export const apiUnlikePage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/unlike`);

export const apiUploadPageMedia = (file: File) => {
  const data = new FormData();
  data.append('file', file);

  return apiRequestPost<ApiMediaAttachmentJSON>('v1/media', data);
};
