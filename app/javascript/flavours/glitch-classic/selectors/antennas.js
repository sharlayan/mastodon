import { createSelector } from '@reduxjs/toolkit';

export const getAvailableAntennas = createSelector(
  [(state) => state.get('antennas')],
  (antennas) => antennas.filter((item) => !!item).toList(),
);
