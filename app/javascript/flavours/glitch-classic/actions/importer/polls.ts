import { createAction } from '@reduxjs/toolkit';

import type { Poll } from 'flavours/glitch-classic/models/poll';

export const importPolls = createAction<{ polls: Poll[] }>(
  'poll/importMultiple',
);
