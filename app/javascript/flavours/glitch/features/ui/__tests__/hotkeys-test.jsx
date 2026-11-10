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

  it('focuses the current column post with j and k from its header in legacy mode', () => {
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
    const ui = new UI({ dispatch: vi.fn() });

    for (const handler of ['handleMoveDown', 'handleMoveUp']) {
      header.focus();
      expect(document.activeElement, handler).toBe(header);
      expect(ui[handler](), handler).toBe(true);
      expect(document.activeElement, handler).toBe(post);
    }
  });
});
