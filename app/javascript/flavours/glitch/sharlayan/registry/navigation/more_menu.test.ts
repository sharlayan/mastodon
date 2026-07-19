import type { MenuItem } from 'flavours/glitch/models/dropdown_menu';

import { extendSharlayanMoreMenuItems } from './more_menu';

const formatMessage = ({ id }: { id: string }) => id;

const itemPaths = (items: MenuItem[]) =>
  items.map((item) => {
    if (item === null) return null;
    if ('to' in item) return item.to;
    if ('action' in item) return 'action';

    return item.href;
  });

describe('Sharlayan More menu registry', () => {
  it('inserts gated entries without changing the upstream item order', () => {
    const items: MenuItem[] = [
      { to: '/mutes', text: 'mutes' },
      { to: '/domain_blocks', text: 'blocks' },
      null,
      { text: 'logout', action: vi.fn() },
    ];

    extendSharlayanMoreMenuItems(items, formatMessage, vi.fn(), true);

    expect(itemPaths(items)).toEqual([
      '/drive',
      null,
      '/mutes',
      '/custom_emoji_mutes',
      '/reaction_mutes',
      '/domain_blocks',
      '/domain_mutes',
      null,
      'action',
      'action',
    ]);
  });

  it('does not add Drive when its feature gate is off', () => {
    const items: MenuItem[] = [{ text: 'logout', action: vi.fn() }];

    extendSharlayanMoreMenuItems(items, formatMessage, vi.fn(), false);

    expect(itemPaths(items)).toEqual(['action', 'action']);
  });
});
