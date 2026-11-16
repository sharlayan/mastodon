import type { ReactNode } from 'react';

import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';
import type { Map as ImmutableMap } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { ReplyScopeButton } from '../reply_scope_button';

const context = vi.hoisted(() => ({ dispatch: vi.fn() }));
let compose: ImmutableMap<string, unknown> = fromJS({
  id: null,
  reply_to_limited: true,
  limited_scope: 'reply',
});

vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => context.dispatch,
  useAppSelector: (selector: (state: { compose: typeof compose }) => unknown) =>
    selector({ compose }),
}));
vi.mock('@/flavours/glitch/actions/compose_typed', () => ({
  changeComposeReplyScope: (enabled: boolean) => ({
    type: 'CHANGE_REPLY_SCOPE',
    enabled,
  }),
}));
vi.mock('@/flavours/glitch/components/button/redesign', () => ({
  Button: ({
    children,
    size: _size,
    tooltip,
    ...props
  }: React.ComponentPropsWithoutRef<'button'> & {
    children: ReactNode;
    size?: string;
    tooltip?: { text: string };
  }) => (
    <button type='button' title={tooltip?.text} {...props}>
      {children}
    </button>
  ),
}));

afterEach(cleanup);

it('selects the reply audience in both compose interfaces and prevents changing a published audience', () => {
  for (const redesign of [false, true]) {
    context.dispatch.mockClear();
    compose = fromJS({
      id: null,
      reply_to_limited: true,
      limited_scope: 'reply',
    });
    const { rerender, unmount } = render(
      <IntlProvider locale='en'>
        <ReplyScopeButton redesign={redesign} />
      </IntlProvider>,
    );
    const button = screen.getByRole<HTMLButtonElement>('button', {
      name: 'Reply audience',
    });
    expect(button.getAttribute('aria-pressed')).toBe('true');
    expect(button.title).toBe(
      'Only the author and recipients of the original post',
    );
    fireEvent.click(button);
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_REPLY_SCOPE',
      enabled: false,
    });

    compose = compose.set('id', 'published');
    rerender(
      <IntlProvider locale='en'>
        <ReplyScopeButton redesign={redesign} />
      </IntlProvider>,
    );
    expect(screen.getByRole<HTMLButtonElement>('button').disabled).toBe(true);
    unmount();
  }
});

it('offers the selection only for a limited reply or restored reply scope', () => {
  compose = fromJS({ id: null, reply_to_limited: false, limited_scope: null });
  const { rerender } = render(
    <IntlProvider locale='en'>
      <ReplyScopeButton />
    </IntlProvider>,
  );
  expect(screen.queryByRole('button')).toBeNull();

  compose = compose.set('reply_to_limited', true);
  rerender(
    <IntlProvider locale='en'>
      <ReplyScopeButton />
    </IntlProvider>,
  );
  fireEvent.click(screen.getByRole('button', { name: 'Reply audience' }));
  expect(context.dispatch).toHaveBeenCalledWith({
    type: 'CHANGE_REPLY_SCOPE',
    enabled: true,
  });
});
