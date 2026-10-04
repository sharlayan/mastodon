import { describe, expect, it, vi } from 'vitest';

import { UI } from '../index';

vi.hoisted(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockReturnValue({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }),
  });
});

describe('UI compose hotkeys', () => {
  it('does not consume the redesign-only new-message shortcut in legacy mode', () => {
    const dispatch = vi.fn();
    const preventDefault = vi.fn();
    const ui = new UI({ dispatch });

    expect(ui.handleHotkeyNewMessage({ preventDefault })).toBe(false);
    expect(preventDefault).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });
});
