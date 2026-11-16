import {
  apiCreate,
  apiUpdate,
  apiGetLists,
} from 'flavours/glitch-classic/api/lists';
import type { List } from 'flavours/glitch-classic/models/list';
import { createDataLoadingThunk } from 'flavours/glitch-classic/store/typed_functions';

export const createList = createDataLoadingThunk(
  'list/create',
  (list: Partial<List>) => apiCreate(list),
);

export const updateList = createDataLoadingThunk(
  'list/update',
  (list: Partial<List>) => apiUpdate(list),
);

export const fetchLists = createDataLoadingThunk('lists/fetch', () =>
  apiGetLists(),
);
