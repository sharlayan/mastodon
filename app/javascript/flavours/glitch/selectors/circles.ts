import type { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import type { Circle } from 'flavours/glitch/models/circle';
import { createAppSelector } from 'flavours/glitch/store';

const getCircles = createAppSelector(
  [(state) => state.circles],
  (circles: ImmutableMap<string, Circle | null>): ImmutableList<Circle> =>
    circles.toList().filter((item: Circle | null): item is Circle => !!item),
);

export const getOrderedCircles = createAppSelector(
  [(state) => getCircles(state)],
  (circles) =>
    circles
      .sort((a: Circle, b: Circle) => a.title.localeCompare(b.title))
      .toArray(),
);
