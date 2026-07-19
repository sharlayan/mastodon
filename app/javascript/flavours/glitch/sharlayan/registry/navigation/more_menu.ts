import type { MenuItem } from 'flavours/glitch/models/dropdown_menu';

export const extendSharlayanMoreMenuItems = (
  items: MenuItem[],
  formatMessage: (descriptor: { id: string; defaultMessage: string }) => string,
  openAccountSwitcher: () => void,
  driveEnabled: boolean,
) => {
  const driveItems: MenuItem[] = driveEnabled
    ? [{ to: '/drive', text: formatMessage(messages.drive) }, null]
    : [];

  items.unshift(...driveItems);
  insertAfter(items, '/mutes', [
    {
      to: '/custom_emoji_mutes',
      text: formatMessage(messages.customEmojiMutes),
    },
    { to: '/reaction_mutes', text: formatMessage(messages.reactionMutes) },
  ]);
  insertAfter(items, '/domain_blocks', [
    { to: '/domain_mutes', text: formatMessage(messages.domainMutes) },
  ]);
  items.splice(-1, 0, {
    text: formatMessage(messages.switchAccount),
    action: openAccountSwitcher,
  });
};

const insertAfter = (
  items: MenuItem[],
  path: string,
  additions: MenuItem[],
) => {
  const index = items.findIndex(
    (item) => item !== null && 'to' in item && item.to === path,
  );

  if (index !== -1) items.splice(index + 1, 0, ...additions);
};

const messages = {
  domainMutes: {
    id: 'navigation_bar.domain_mutes',
    defaultMessage: 'Muted domains',
  },
  customEmojiMutes: {
    id: 'navigation_bar.custom_emoji_mutes',
    defaultMessage: 'Muted custom emoji',
  },
  reactionMutes: {
    id: 'navigation_bar.reaction_mutes',
    defaultMessage: 'Reaction mutes',
  },
  switchAccount: {
    id: 'navigation_bar.switch_account',
    defaultMessage: 'Switch account',
  },
  drive: { id: 'navigation_bar.drive', defaultMessage: 'Drive' },
};
