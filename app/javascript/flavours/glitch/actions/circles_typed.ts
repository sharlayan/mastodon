import {
  apiCreate,
  apiUpdate,
  apiGetCircles,
} from 'flavours/glitch/api/circles';
import type { Circle } from 'flavours/glitch/models/circle';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const createCircle = createDataLoadingThunk(
  'circle/create',
  (circle: Partial<Circle>) => apiCreate(circle),
);

export const updateCircle = createDataLoadingThunk(
  'circle/update',
  (circle: Partial<Circle>) => apiUpdate(circle),
);

export const fetchCircles = createDataLoadingThunk('circles/fetch', () =>
  apiGetCircles(),
);
