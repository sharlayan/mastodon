import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

export const getPageDisplayTitle = (page: ApiPageJSON): string =>
  page.page_series ? `[${page.page_series.title}] ${page.title}` : page.title;
