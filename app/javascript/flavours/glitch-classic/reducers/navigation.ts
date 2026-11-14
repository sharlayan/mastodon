import { createReducer } from '@reduxjs/toolkit';

import {
  openNavigation,
  closeNavigation,
  toggleNavigation,
} from 'flavours/glitch-classic/actions/navigation';

interface State {
  open: boolean;
}

const initialState: State = {
  open: false,
};

export const navigationReducer = createReducer(initialState, (builder) => {
  builder
    .addCase(openNavigation, (state) => {
      state.open = true;
    })
    .addCase(closeNavigation, (state) => {
      state.open = false;
    })
    .addCase(toggleNavigation, (state) => {
      state.open = !state.open;
    });
});
