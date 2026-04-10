import { createContext, useContext } from 'react';

export const MfmHoverContext = createContext(false);

export function useMfmHover() {
  return useContext(MfmHoverContext);
}
