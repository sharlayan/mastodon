// @vitest-environment node

import { createMemoryHistory } from 'history';

import { leaveChatRoute, trackChatHistory } from '../history_parent';

const tracked = (...paths: string[]) => {
  const [first = '/', ...rest] = paths;
  const history = createMemoryHistory({ initialEntries: [first] });
  trackChatHistory(history);
  rest.forEach((path) => {
    history.push(path);
  });
  return history;
};

describe('leaveChatRoute', () => {
  it('goes back only once while the first step back is still pending', () => {
    const history = tracked('/chat', '/chat/A');
    const goBack = vi.spyOn(history, 'goBack').mockImplementation(() => {
      return undefined;
    });
    const replace = vi.spyOn(history, 'replace');

    leaveChatRoute(history, '/chat');
    leaveChatRoute(history, '/chat');

    expect(goBack).toHaveBeenCalledTimes(1);
    expect(replace).not.toHaveBeenCalled();
  });

  it('leaves again after the pending step back has landed', () => {
    const history = tracked('/chat', '/chat/A');
    leaveChatRoute(history, '/chat');
    expect(history.location.pathname).toBe('/chat');

    history.push('/chat/B');
    leaveChatRoute(history, '/chat');

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
  });

  it('steps over the room under a room view to reach the list', () => {
    const history = tracked('/chat', '/chat/A', '/chat/A/members');

    leaveChatRoute(history, '/chat');

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
  });

  it('does not step over a different room on the way to the list', () => {
    const history = tracked('/chat', '/chat/A', '/chat/B');

    leaveChatRoute(history, '/chat');

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(2);
  });

  it('replaces a room view reached from outside chat with the list', () => {
    const history = tracked('/home', '/chat/A', '/chat/A/settings');

    leaveChatRoute(history, '/chat');

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(2);
  });

  it('stays put when already on the parent', () => {
    const history = tracked('/home', '/chat');
    const replace = vi.spyOn(history, 'replace');

    leaveChatRoute(history, '/chat');

    expect(replace).not.toHaveBeenCalled();
    expect(history.index).toBe(1);
  });
});
