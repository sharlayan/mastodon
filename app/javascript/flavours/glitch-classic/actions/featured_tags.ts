import { apiGetFeaturedTags } from 'flavours/glitch-classic/api/accounts';
import { createDataLoadingThunk } from 'flavours/glitch-classic/store/typed_functions';

export const fetchFeaturedTags = createDataLoadingThunk(
  'accounts/featured_tags',
  ({ accountId }: { accountId: string }) => apiGetFeaturedTags(accountId),
);
