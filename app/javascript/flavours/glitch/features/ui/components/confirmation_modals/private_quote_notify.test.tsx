import { IntlProvider } from 'react-intl';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import type { StatusVisibility } from '@/flavours/glitch/api_types/statuses';
import { submitComposer } from '@/flavours/glitch/reducers/slices/composer';

import { PrivateQuoteNotify } from './private_quote_notify';

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppDispatch: () => vi.fn(),
}));
vi.mock(
  '@/flavours/glitch/reducers/slices/composer',
  async (importOriginal) => ({
    ...(await importOriginal()),
    submitComposer: vi.fn(),
  }),
);
vi.mock('./confirmation_modal', () => ({
  ConfirmationModal: ({ onConfirm }: { onConfirm: () => void }) => (
    <button type='button' onClick={onConfirm}>
      Confirm
    </button>
  ),
}));

it('resubmits with the redirect option and a private or absent privacy after confirmation', () => {
  const privacies: (StatusVisibility | undefined)[] = ['private', undefined];

  for (const overridePrivacy of privacies) {
    const { unmount } = render(
      <IntlProvider locale='en'>
        <PrivateQuoteNotify
          onClose={vi.fn()}
          redirectOnSuccess
          overridePrivacy={overridePrivacy}
        />
      </IntlProvider>,
    );
    fireEvent.click(screen.getByText('Confirm'));
    expect(submitComposer).toHaveBeenLastCalledWith({
      force: true,
      overridePrivacy,
      redirectOnSuccess: true,
    });
    unmount();
  }
});
