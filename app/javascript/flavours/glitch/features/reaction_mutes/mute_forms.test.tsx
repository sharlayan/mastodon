import type { ReactNode } from 'react';

import { IntlProvider } from 'react-intl';

import { act, fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import CustomEmojiMutes from '../custom_emoji_mutes';

import ReactionMutes from '.';

const mocks = vi.hoisted(() => ({
  status: 'fulfilled',
  dispatch: vi.fn(),
}));

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (selector: (state: unknown) => unknown) =>
    selector({
      reaction_mutes: { items: [], loading: false },
      custom_emoji_mutes: { items: [], loading: false, hidden: false },
    }),
}));

vi.mock('flavours/glitch/actions/reaction_mutes', () => ({
  fetchReactionMutes: () => ({ type: 'fetch' }),
  createReactionMute: (params: unknown) => ({ type: 'create', params }),
  deleteReactionMute: () => ({ type: 'delete' }),
}));

vi.mock('flavours/glitch/actions/custom_emoji_mutes', () => ({
  fetchCustomEmojiMutes: () => ({ type: 'fetch' }),
  createCustomEmojiMute: (params: unknown) => ({ type: 'create', params }),
  deleteCustomEmojiMute: () => ({ type: 'delete' }),
  updateCustomEmojiMuteHidden: () => ({ type: 'hidden' }),
}));

vi.mock('flavours/glitch/components/column', () => ({
  Column: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));
vi.mock('flavours/glitch/components/scrollable_list', () => ({
  default: () => null,
}));
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

beforeEach(() => {
  mocks.dispatch.mockReset();
  mocks.dispatch.mockImplementation((action: { type: string }) =>
    action.type === 'create'
      ? Promise.resolve({
          ...action,
          meta: { requestId: '1', requestStatus: mocks.status },
        })
      : action,
  );
});

const submit = async (input: HTMLElement, value: string) => {
  fireEvent.change(input, { target: { value } });
  // eslint-disable-next-line @typescript-eslint/require-await
  await act(async () => {
    fireEvent.submit(input.closest('form') as HTMLFormElement);
  });
};

const createdParams = () =>
  mocks.dispatch.mock.calls
    .map(([action]) => action as { type: string; params?: unknown })
    .filter((action) => action.type === 'create')
    .map((action) => action.params);

describe('reaction mute form', () => {
  const renderForm = () => {
    render(
      <IntlProvider locale='en'>
        <ReactionMutes multiColumn={false} />
      </IntlProvider>,
    );
    return screen.getByRole('textbox');
  };

  it('treats bare names as accounts and domains with a dot as servers', async () => {
    mocks.status = 'fulfilled';
    const input = renderForm();

    await submit(input, 'alice');
    await submit(input, 'bob@remote.tld');
    await submit(input, 'remote.tld');

    expect(createdParams()).toEqual([
      { acct: 'alice' },
      { acct: 'bob@remote.tld' },
      { domain: 'remote.tld' },
    ]);
    expect((input as HTMLInputElement).value).toBe('');
  });

  it('keeps the input when the request fails', async () => {
    mocks.status = 'rejected';
    const input = renderForm();

    await submit(input, 'nobody@remote.tld');

    expect((input as HTMLInputElement).value).toBe('nobody@remote.tld');
  });
});

describe('custom emoji mute form', () => {
  it('keeps the input until the request succeeds', async () => {
    render(
      <IntlProvider locale='en'>
        <CustomEmojiMutes multiColumn={false} />
      </IntlProvider>,
    );
    const prefix = screen.getByPlaceholderText('Shortcode prefix (e.g. blob_)');

    mocks.status = 'rejected';
    await submit(prefix, 'blob_');
    expect((prefix as HTMLInputElement).value).toBe('blob_');

    mocks.status = 'fulfilled';
    await submit(prefix, 'blob_');
    expect((prefix as HTMLInputElement).value).toBe('');
  });
});
