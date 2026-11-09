import { IntlProvider } from 'react-intl';

import { List, Map as ImmutableMap } from 'immutable';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';

import { apiGetStatusReactionAccounts } from 'flavours/glitch/api/status_reactions';
import type { ApiStatusReactionAccountJSON } from 'flavours/glitch/api/status_reactions';

import { StatusReactionsModal } from '../status_reactions_modal';

vi.mock('flavours/glitch/api/status_reactions', () => ({
  apiGetStatusReactionAccounts: vi.fn(),
  STATUS_REACTION_ACCOUNTS_PAGE_SIZE: 2,
}));
const dispatch = vi.hoisted(() => vi.fn());

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => dispatch,
}));
vi.mock('flavours/glitch/actions/importer', () => ({
  importFetchedAccounts: vi.fn(() => ({ type: 'TEST_IMPORT' })),
}));
vi.mock('flavours/glitch/components/account', () => ({
  Account: ({ id }: { id: string }) => <div data-testid='account'>{id}</div>,
}));
vi.mock('flavours/glitch/components/loading_indicator', () => ({
  LoadingIndicator: () => null,
}));

const entry = (id: string) =>
  ({ id, account: { id } }) as unknown as ApiStatusReactionAccountJSON;

const deferred = <T,>() => {
  let settle: (value: T) => void = () => undefined;
  const promise = new Promise<T>((resolve) => {
    settle = resolve;
  });
  return {
    promise,
    resolve: (value: T) => {
      settle(value);
    },
  };
};

const reactions = List([
  ImmutableMap<string, string | number | boolean>({ name: 'A', count: 3 }),
  ImmutableMap<string, string | number | boolean>({ name: 'B', count: 1 }),
]);

afterEach(cleanup);

describe('<StatusReactionsModal />', () => {
  it('drops a slow next page of a reaction once another reaction is selected', async () => {
    const nextPageOfA = deferred<ApiStatusReactionAccountJSON[]>();
    const firstPageOfB = deferred<ApiStatusReactionAccountJSON[]>();
    vi.mocked(apiGetStatusReactionAccounts)
      .mockResolvedValueOnce([entry('a1'), entry('a2')])
      .mockReturnValueOnce(nextPageOfA.promise)
      .mockReturnValueOnce(firstPageOfB.promise);

    render(
      <IntlProvider locale='en'>
        <StatusReactionsModal
          statusId='1'
          reactions={reactions}
          onClose={vi.fn()}
        />
      </IntlProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Load more' }));
    fireEvent.click(screen.getByRole('button', { name: /^B/ }));

    await act(async () => {
      firstPageOfB.resolve([entry('b1')]);
      await firstPageOfB.promise;
    });
    await act(async () => {
      nextPageOfA.resolve([entry('a3')]);
      await nextPageOfA.promise;
    });

    expect(
      screen.getAllByTestId('account').map((node) => node.textContent),
    ).toEqual(['b1']);
  });
});
