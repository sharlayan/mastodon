import { createAction } from '@reduxjs/toolkit';

import type { ApiAccountJSON } from 'flavours/glitch-classic/api_types/accounts';

export const importAccounts = createAction<{ accounts: ApiAccountJSON[] }>(
  'accounts/importAccounts',
);
