import { accountSwitcherModal } from '../navigation';

describe('compose navigation extension', () => {
  it('opens the account switcher without passing state into the modal', () => {
    expect(accountSwitcherModal).toEqual({
      modalType: 'ACCOUNT_SWITCHER',
      modalProps: {},
    });
  });
});
