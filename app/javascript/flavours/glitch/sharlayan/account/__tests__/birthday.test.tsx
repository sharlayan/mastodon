import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { patchProfile } from '@/flavours/glitch/reducers/slices/profile_edit';

import { parseBirthday } from '../birthday';
import { BirthdayModal } from '../birthday_modal';
import { SharlayanBirthdayNumberField } from '../birthday_number_field';

const dispatch = vi.hoisted(() => vi.fn(() => Promise.resolve()));

vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal()),
  useHistory: () => ({ action: 'PUSH' }),
  useLocation: () => ({
    pathname: '/',
    search: '',
    hash: '',
    state: undefined,
  }),
}));
vi.mock(
  '@/flavours/glitch/reducers/slices/profile_edit',
  async (importOriginal) => ({
    ...(await importOriginal<object>()),
    patchProfile: vi.fn((params: unknown) => ({ type: 'PATCH', params })),
  }),
);
vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => dispatch,
  useAppSelector: (
    selector: (state: {
      profileEdit: { profile: unknown; isPending: boolean };
    }) => unknown,
  ) =>
    selector({
      profileEdit: {
        profile: { birthday: '1990-12-31', showBirthday: false },
        isPending: false,
      },
    }),
}));
vi.mock('@/flavours/glitch/components/number_fields', () => ({
  NumberFieldsItem: ({
    label,
    hint,
    children,
  }: {
    label: React.ReactNode;
    hint: string;
    children: React.ReactNode;
  }) => (
    <li title={hint}>
      {label}: {children}
    </li>
  ),
}));

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('birthday', () => {
  it('parses only real YYYY-MM-DD dates', () => {
    expect(parseBirthday('2000-02-29')?.toISOString()).toBe(
      '2000-02-29T00:00:00.000Z',
    );
    expect(parseBirthday('1990-02-30')).toBeNull();
    expect(parseBirthday('12/31')).toBeNull();
    expect(parseBirthday(null)).toBeNull();
  });

  it('shows the birthday on the profile only when the account exposes one', () => {
    render(
      <IntlProvider locale='en'>
        <ul>
          <SharlayanBirthdayNumberField birthday='1990-12-31' />
          <SharlayanBirthdayNumberField birthday={null} />
        </ul>
      </IntlProvider>,
    );

    const items = screen.getAllByRole('listitem');
    expect(items).toHaveLength(1);
    expect(items[0]?.textContent).toBe('Birthday: Dec 31');
    expect(items[0]?.getAttribute('title')).toBe('December 31, 1990');
  });

  it('saves the date and visibility together, or clears the birthday', async () => {
    const onClose = vi.fn();
    render(
      <IntlProvider locale='en'>
        <BirthdayModal onClose={onClose} />
      </IntlProvider>,
    );

    const input = screen.getByLabelText('Birthday');
    expect((input as HTMLInputElement).value).toBe('1990-12-31');

    fireEvent.change(input, { target: { value: '1991-01-02' } });
    fireEvent.click(screen.getByLabelText('Show my birthday on my profile'));
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(patchProfile).toHaveBeenLastCalledWith({
      birthday: '1991-01-02',
      show_birthday: true,
    });
    await vi.waitFor(() => {
      expect(onClose).toHaveBeenCalled();
    });

    fireEvent.change(input, { target: { value: '' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(patchProfile).toHaveBeenLastCalledWith({
      birthday: '',
      show_birthday: true,
    });
  });
});
