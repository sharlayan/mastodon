import {
  apiRequestPost,
  apiRequestPut,
  apiRequestGet,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import type {
  ApiPageJSON,
  ApiPageSeriesJSON,
  ApiPageUnlockJSON,
} from 'flavours/glitch/api_types/pages';

const accessTokenKey = (pageId: string) => `page-access:${pageId}`;

const getPageAccessToken = (pageId: string) => {
  try {
    return sessionStorage.getItem(accessTokenKey(pageId));
  } catch {
    return null;
  }
};

const storePageAccessToken = (pageId: string, token: string) => {
  try {
    sessionStorage.setItem(accessTokenKey(pageId), token);
  } catch {}
};

export const PAGE_LIST_LIMIT = 20;

export const apiGetPages = (offset = 0) =>
  apiRequestGet<ApiPageJSON[]>('v1/pages', {
    limit: PAGE_LIST_LIMIT,
    offset,
  });

export const apiGetPageCategories = () =>
  apiRequestGet<string[]>('v1/pages/categories');

export const apiGetFeaturedPages = () =>
  apiRequestGet<ApiPageJSON[]>('v1/pages/featured');

export const apiGetAccountPages = (accountId: string, offset = 0) =>
  apiRequestGet<ApiPageJSON[]>(`v1/accounts/${accountId}/pages`, {
    limit: PAGE_LIST_LIMIT,
    offset,
  });

export const apiGetAccountPage = (accountId: string, name: string) =>
  apiRequestGet<ApiPageJSON>(
    `v1/accounts/${accountId}/pages/${encodeURIComponent(name)}`,
  );

export const apiGetPage = async (pageId: string) => {
  const page = await apiRequestGet<ApiPageJSON>(`v1/pages/${pageId}`);
  const accessToken = page.locked ? getPageAccessToken(pageId) : null;

  if (!accessToken) {
    return page;
  }

  try {
    return await apiUnlockPage(pageId, undefined, accessToken);
  } catch {
    return page;
  }
};

export const apiUnlockPage = async (
  pageId: string,
  password?: string,
  accessToken?: string,
) => {
  const result = await apiRequestPost<ApiPageUnlockJSON>(
    `v1/pages/${pageId}/unlock`,
    { password, access_token: accessToken },
  );
  storePageAccessToken(pageId, result.access_token);
  return result.page;
};

export const apiCreatePage = (page: Partial<ApiPageJSON>) =>
  apiRequestPost<ApiPageJSON>('v1/pages', page);

export const apiUpdatePage = (pageId: string, page: Partial<ApiPageJSON>) =>
  apiRequestPut<ApiPageJSON>(`v1/pages/${pageId}`, page);

export const apiDeletePage = (pageId: string) =>
  apiRequestDelete(`v1/pages/${pageId}`);

export const apiLikePage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/like`, {
    access_token: getPageAccessToken(pageId),
  });

export const apiUnlikePage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/unlike`, {
    access_token: getPageAccessToken(pageId),
  });

export const apiSetMainPage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/main`);

export const apiUnsetMainPage = (pageId: string) =>
  apiRequestDelete<ApiPageJSON>(`v1/pages/${pageId}/main`);

export const apiSetBookletMainPage = (pageId: string) =>
  apiRequestPost<ApiPageJSON>(`v1/pages/${pageId}/series_main`);

export const apiUnsetBookletMainPage = (pageId: string) =>
  apiRequestDelete<ApiPageJSON>(`v1/pages/${pageId}/series_main`);

export const apiGetPageSeries = () =>
  apiRequestGet<ApiPageSeriesJSON[]>('v1/page_series');

export const apiGetOtherPageSeries = () =>
  apiRequestGet<ApiPageSeriesJSON[]>('v1/page_series/others');

export const apiCreatePageSeries = (series: {
  title: string;
  description?: string | null;
  cover_media_attachment_id?: string | null;
}) => apiRequestPost<ApiPageSeriesJSON>('v1/page_series', series);

export const apiUpdatePageSeries = (
  seriesId: string,
  series: {
    title?: string;
    description?: string | null;
    cover_media_attachment_id?: string | null;
  },
) => apiRequestPut<ApiPageSeriesJSON>(`v1/page_series/${seriesId}`, series);

export const apiDeletePageSeries = (seriesId: string) =>
  apiRequestDelete(`v1/page_series/${seriesId}`);

export const apiUploadPageMedia = (file: File) => {
  const data = new FormData();
  data.append('file', file);

  return apiRequestPost<ApiMediaAttachmentJSON>('v1/media', data);
};
