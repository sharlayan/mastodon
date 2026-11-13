import { hideAnnouncements, showAnnouncements, toggleShowAnnouncements } from '../../actions/announcements';
import announcements from '../announcements';

describe('announcements visibility', () => {
  it('sets visibility explicitly and keeps toggle behavior', () => {
    let state = announcements(undefined, showAnnouncements());
    expect(state.get('show')).toBe(true);

    state = announcements(state, showAnnouncements());
    expect(state.get('show')).toBe(true);

    state = announcements(state, hideAnnouncements());
    expect(state.get('show')).toBe(false);

    state = announcements(state, hideAnnouncements());
    expect(state.get('show')).toBe(false);

    state = announcements(state, toggleShowAnnouncements());
    expect(state.get('show')).toBe(true);
  });
});
