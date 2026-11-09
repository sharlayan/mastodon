import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import { cleanup, render } from '@testing-library/react';

import type * as BoardAnnouncementActions from 'flavours/glitch/actions/board_announcements';
import type { ApiBoardAnnouncementJSON } from 'flavours/glitch/api_types/board_announcements';

import BoardAnnouncements from '..';

await vi.hoisted(() => import('../../chat/testing/match_media'));

const mocks = vi.hoisted(() => ({
  state: {
    boardAnnouncements: {
      items: [] as ApiBoardAnnouncementJSON[],
      isLoading: false,
      loaded: true,
    },
  },
  dispatch: vi.fn((action: unknown) => action),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (selector: (state: typeof mocks.state) => unknown) =>
    selector(mocks.state),
}));

const thunkParts = vi.hoisted(
  () =>
    (thunk: { pending: unknown; fulfilled: unknown; rejected: unknown }) => ({
      pending: thunk.pending,
      fulfilled: thunk.fulfilled,
      rejected: thunk.rejected,
    }),
);

vi.mock(
  'flavours/glitch/actions/board_announcements',
  async (importOriginal) => {
    const actual = await importOriginal<typeof BoardAnnouncementActions>();

    return {
      ...actual,
      fetchBoardAnnouncements: Object.assign(
        () => ({ type: 'fetch' }),
        thunkParts(actual.fetchBoardAnnouncements),
      ),
      readBoardAnnouncement: Object.assign(
        ({ id }: { id: string }) => ({ type: 'read', id }),
        thunkParts(actual.readBoardAnnouncement),
      ),
    };
  },
);

vi.mock('flavours/glitch/hooks/useLayout', () => ({
  useLayout: () => ({ singleColumn: true }),
}));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('../html', () => ({
  useBoardAnnouncementHtml: () => ({}),
}));

vi.mock('../reactions', () => ({
  ReactionsBar: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const announcement = (id: string) =>
  ({
    id,
    title: `Announcement ${id}`,
    content: '<p>Hello</p>',
    emojis: [],
    reactions: [],
    read: false,
    need_confirmation_to_read: false,
    icon: 'info',
    published_at: '2026-11-09T00:00:00Z',
    updated_at: '2026-11-09T00:00:00Z',
  }) as unknown as ApiBoardAnnouncementJSON;

const readCalls = () =>
  mocks.dispatch.mock.calls
    .map(([action]) => action as { type: string; id?: string })
    .filter((action) => action.type === 'read')
    .map((action) => action.id);

const view = () => (
  <IntlProvider locale='en'>
    <MemoryRouter>
      <BoardAnnouncements multiColumn />
    </MemoryRouter>
  </IntlProvider>
);

describe('BoardAnnouncements', () => {
  afterEach(() => {
    cleanup();
  });

  it('marks each unread announcement as read only once while the list changes', () => {
    mocks.state.boardAnnouncements.items = [
      announcement('1'),
      announcement('2'),
    ];
    const { rerender } = render(view());

    mocks.state.boardAnnouncements.items = [
      announcement('1'),
      announcement('2'),
      announcement('3'),
    ];
    rerender(view());

    mocks.state.boardAnnouncements.items = [
      announcement('1'),
      announcement('2'),
      announcement('3'),
    ];
    rerender(view());

    expect(readCalls().toSorted()).toEqual(['1', '2', '3']);
  });
});
