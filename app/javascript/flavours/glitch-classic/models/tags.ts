import type { ApiHashtagJSON } from 'flavours/glitch-classic/api_types/tags';

export type Hashtag = ApiHashtagJSON;

export const createHashtag = (serverJSON: ApiHashtagJSON): Hashtag => ({
  ...serverJSON,
});
