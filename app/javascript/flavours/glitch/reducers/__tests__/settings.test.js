import settings from '../settings';

describe('settings defaults', () => {
  it('groups follow notifications by default', () => {
    const state = settings(undefined, { type: '@@INIT' });

    expect(state.getIn(['notifications', 'group']).toJS()).toEqual({ follow: true });
  });
});
