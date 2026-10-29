import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { isRedesignEnabled } from './environment';

const state = vi.hoisted(() => ({
  initialState: undefined as { features: string[] } | undefined,
}));

vi.mock('../initial_state', () => state);

describe('redesign feature gates', () => {
  const originalUserFlavour = document.documentElement.dataset.userFlavour;

  beforeEach(() => {
    state.initialState = { features: [] };
    document.documentElement.dataset.userFlavour = 'glitch';
    window.localStorage.removeItem('experiments');
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    window.localStorage.removeItem('experiments');

    if (originalUserFlavour === undefined) {
      delete document.documentElement.dataset.userFlavour;
    } else {
      document.documentElement.dataset.userFlavour = originalUserFlavour;
    }
  });

  it('enables the redesign when the server requests it', () => {
    state.initialState = { features: ['fasp', 'redesign'] };

    expect(isRedesignEnabled()).toBe(true);
  });

  it('enables the redesign when the client requests it', () => {
    window.localStorage.setItem('experiments', 'other,redesign');

    expect(isRedesignEnabled()).toBe(true);
  });

  it.each([null, '', 'other', 'redesign-preview'])(
    'keeps the redesign disabled with client experiments %j',
    (experiments) => {
      state.initialState = { features: ['fasp'] };

      if (experiments !== null) {
        window.localStorage.setItem('experiments', experiments);
      }

      expect(isRedesignEnabled()).toBe(false);
    },
  );

  it('keeps the redesign disabled without initial state or client experiments', () => {
    state.initialState = undefined;

    expect(isRedesignEnabled()).toBe(false);
  });

  it('can use the client experiment without initial state', () => {
    state.initialState = undefined;
    window.localStorage.setItem('experiments', 'redesign');

    expect(isRedesignEnabled()).toBe(true);
  });

  it('falls back to the legacy UI when localStorage is inaccessible', () => {
    const error = new DOMException('Storage access denied', 'SecurityError');
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw error;
    });
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    expect(isRedesignEnabled()).toBe(false);
    expect(warn).toHaveBeenCalledWith(
      'Could not access localStorage to get client features',
      error,
    );
  });

  it('does not read localStorage when the server enables the redesign', () => {
    state.initialState = { features: ['redesign'] };
    const getItem = vi
      .spyOn(Storage.prototype, 'getItem')
      .mockImplementation(() => {
        throw new DOMException('Storage access denied', 'SecurityError');
      });

    expect(isRedesignEnabled()).toBe(true);
    expect(getItem).not.toHaveBeenCalled();
  });

  it.each([
    { server: true, client: false },
    { server: false, client: true },
    { server: true, client: true },
  ])(
    'keeps Glitch Legacy on the legacy UI with server=$server and client=$client',
    ({ server, client }) => {
      document.documentElement.dataset.userFlavour = 'glitch-classic';
      state.initialState = { features: server ? ['redesign'] : [] };
      if (client) {
        window.localStorage.setItem('experiments', 'redesign');
      }

      expect(isRedesignEnabled()).toBe(false);
    },
  );

  it('does not read client experiments for Glitch Legacy', () => {
    document.documentElement.dataset.userFlavour = 'glitch-classic';
    const getItem = vi.spyOn(Storage.prototype, 'getItem');

    expect(isRedesignEnabled()).toBe(false);
    expect(getItem).not.toHaveBeenCalled();
  });

  it('uses the normal feature flags without a flavour attribute', () => {
    delete document.documentElement.dataset.userFlavour;
    state.initialState = { features: ['redesign'] };

    expect(isRedesignEnabled()).toBe(true);
  });

  it('can use the server feature flag without a document', () => {
    state.initialState = { features: ['redesign'] };
    vi.stubGlobal('document', undefined);

    expect(isRedesignEnabled()).toBe(true);
  });
});
