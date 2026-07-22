import type { MenuItem } from 'mastodon/models/dropdown_menu';

const message = {
  id: 'navigation_bar.switch_account',
  defaultMessage: 'Switch account',
};

export const accountSwitcherMenuItem = (
  formatMessage: (descriptor: typeof message) => string,
  openAccountSwitcher: () => void,
): MenuItem => ({
  text: formatMessage(message),
  action: openAccountSwitcher,
});
