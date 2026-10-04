import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import { fromJS } from 'immutable';

import { render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import type { ExpandedStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';
import { accountFactoryState } from '@/testing/factories';

import { StatusPrepend } from './prepend';

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
}));

vi.mock('../avatar', () => ({ Avatar: () => null }));
vi.mock('../display_name', () => ({
  DisplayName: ({ account }: { account: { display_name_html: string } }) => (
    <span>{account.display_name_html}</span>
  ),
}));

const replyId = 'reply-status-id';

const renderStatusPrepend = ({
  statusAccountId,
  replyAccountId,
  accounts = {},
}: {
  statusAccountId: string;
  replyAccountId: string;
  accounts?: Record<string, ReturnType<typeof accountFactoryState>>;
}) => {
  vi.mocked(useAppSelector).mockImplementation((selector) =>
    selector({ accounts: fromJS(accounts) } as unknown as RootState),
  );

  const status = {
    account: { id: statusAccountId },
    in_reply_to_id: replyId,
    in_reply_to_account_id: replyAccountId,
  } as ExpandedStatusShape;

  return render(
    <MemoryRouter>
      <IntlProvider locale='en'>
        <StatusPrepend status={status} showThread />
      </IntlProvider>
    </MemoryRouter>,
  );
};

describe('StatusPrepend', () => {
  afterEach(() => {
    vi.mocked(useAppSelector).mockReset();
  });

  it('links a reply to its status ID when the replied-to account is available', () => {
    renderStatusPrepend({
      statusAccountId: 'replying-account-id',
      replyAccountId: 'replied-to-account-id',
      accounts: {
        'replied-to-account-id': accountFactoryState({
          id: 'replied-to-account-id',
          acct: 'parent-account',
          display_name: 'Parent account',
        }),
      },
    });

    const link = screen.getByRole('link', {
      name: 'Replying to Parent account',
    });
    expect(link.getAttribute('href')).toBe(`/statuses/${replyId}`);
  });

  it('labels a self-reply as a continuing thread and links by status ID', () => {
    renderStatusPrepend({
      statusAccountId: 'thread-account-id',
      replyAccountId: 'thread-account-id',
    });

    const link = screen.getByRole('link', { name: 'Continuing a thread' });
    expect(link.getAttribute('href')).toBe(`/statuses/${replyId}`);
  });
});
