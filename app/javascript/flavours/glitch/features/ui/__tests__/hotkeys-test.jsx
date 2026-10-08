import { afterEach, describe, expect, it, vi } from 'vitest';

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

describe('UI timeline hotkeys', () => {
  let container;

  afterEach(() => {
    container?.remove();
  });

  it.each([
    ['j', 'handleMoveDown'],
    ['k', 'handleMoveUp'],
  ])('focuses the current column post with %s from its header in legacy mode', (_key, handler) => {
    container = document.createElement('div');
    container.innerHTML = `
      <div class="column" data-column-root>
        <div class="scrollable">
          <div class="item-list">
            <article class="focusable" tabindex="-1">First column post</article>
          </div>
        </div>
      </div>
      <div class="column" data-column-root>
        <button type="button">Current column header</button>
        <div class="scrollable">
          <div class="item-list">
            <article id="current-post" class="focusable" tabindex="-1">Current column post</article>
          </div>
        </div>
      </div>
    `;
    document.body.append(container);

    const header = container.querySelector('button');
    const post = container.querySelector('#current-post');
    header.focus();

    const ui = new UI({ dispatch: vi.fn() });

    expect(document.activeElement).toBe(header);
    expect(ui[handler]()).toBe(true);
    expect(document.activeElement).toBe(post);
  });
});
