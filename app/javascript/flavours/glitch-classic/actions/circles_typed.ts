import {
  apiCreate,
  apiUpdate,
  apiGetCircles,
} from 'flavours/glitch-classic/api/circles';
import type { Circle } from 'flavours/glitch-classic/models/circle';
import { createDataLoadingThunk } from 'flavours/glitch-classic/store/typed_functions';

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
