import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';
import { useDispatch, useSelector } from 'react-redux';

import { cleanup, render, screen } from '@testing-library/react';

import { DirectComposer } from '../direct_composer';

vi.mock('react-redux', async importOriginal => ({
  ...(await importOriginal()),
  useDispatch: Object.assign(vi.fn(), { withTypes: () => vi.fn() }),
  useSelector: Object.assign(vi.fn(), { withTypes: () => vi.fn() }),
}));
vi.mock('flavours/glitch/initial_state', async importOriginal => ({ ...(await importOriginal()), me: 'self' }));
vi.mock('flavours/glitch/selectors', () => ({ makeGetStatus: () => () => null }));
vi.mock('flavours/glitch/components/display_name', () => ({ DisplayName: () => null }));
vi.mock('flavours/glitch/components/icon', () => ({ Icon: () => null }));
vi.mock('flavours/glitch/components/icon_button', () => ({ IconButton: () => null }));
vi.mock('flavours/glitch/features/compose/containers/emoji_picker_dropdown_container', () => ({ default: () => null }));
vi.mock('flavours/glitch/features/compose/components/upload_progress', () => ({ UploadProgress: () => null }));

const renderComposer = text => {
  const state = fromJS({
    accounts: {
      local: { acct: 'alice' },
      remote: { acct: 'bob@remote.example' },
    },
    direct_compose: { conversation: { text } },
    server: { server: { item: { configuration: { statuses: { max_characters: 20 } } } } },
  });

  vi.mocked(useDispatch).mockReturnValue(vi.fn());
  vi.mocked(useSelector).mockImplementation(selector => selector(state));

  render(
    <IntlProvider locale='en'>
      <DirectComposer conversationId='conversation' recipientIds={['local', 'remote']} />
    </IntlProvider>,
  );
};

describe('direct composer length', () => {
  afterEach(() => {
    cleanup();
  });

  it('counts the prepended mentions with remote domains excluded', () => {
    renderComposer('hello');

    expect(screen.getByText('3').className).toBe('character-counter');
    expect(screen.getByRole('button', { name: 'Send' }).disabled).toBe(false);
  });

  it('blocks sending when the mentions push the post over the limit', () => {
    renderComposer('hello there!');

    expect(screen.getByText('-4').className).toContain('character-counter--over');
    expect(screen.getByRole('button', { name: 'Send' }).disabled).toBe(true);
  });
});
