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
  it('opens the message composer with the new-message shortcut', () => {
    const dispatch = vi.fn();
    const preventDefault = vi.fn();
    const ui = new UI({ dispatch });

    expect(ui.handleHotkeyNewMessage({ preventDefault })).toBe(true);
    expect(preventDefault).toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledTimes(1);
  });
});
