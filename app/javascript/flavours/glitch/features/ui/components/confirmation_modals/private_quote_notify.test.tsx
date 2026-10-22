import { IntlProvider } from 'react-intl';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import { submitCompose } from '@/flavours/glitch/actions/compose';
import type { StatusVisibility } from '@/flavours/glitch/api_types/statuses';

import { PrivateQuoteNotify } from './private_quote_notify';

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppDispatch: () => vi.fn(),
}));
vi.mock('@/flavours/glitch/actions/compose', async (importOriginal) => ({
  ...(await importOriginal()),
  submitCompose: vi.fn(),
}));
vi.mock('./confirmation_modal', () => ({
  ConfirmationModal: ({ onConfirm }: { onConfirm: () => void }) => (
    <button type='button' onClick={onConfirm}>
      Confirm
    </button>
  ),
}));

it.each<StatusVisibility | undefined>(['private', undefined])(
  'preserves the submission callback and %s privacy after confirmation',
  (overridePrivacy) => {
    const onSubmitSuccess = vi.fn();
    render(
      <IntlProvider locale='en'>
        <PrivateQuoteNotify
          onClose={vi.fn()}
          onSubmitSuccess={onSubmitSuccess}
          overridePrivacy={overridePrivacy}
        />
      </IntlProvider>,
    );
    fireEvent.click(screen.getByText('Confirm'));
    expect(submitCompose).toHaveBeenLastCalledWith(
      onSubmitSuccess,
      overridePrivacy,
    );
  },
);
