import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { apiRequestPut } from 'flavours/glitch/api';

import UserThemePage from '../user_theme_page';

vi.mock('flavours/glitch/api', () => ({ apiRequestPut: vi.fn() }));
vi.mock('flavours/glitch/initial_state', () => ({
  userTheme: '{}',
  userThemeCatalog: '[]',
  userThemeDefaults: '{}',
}));
vi.mock('../color_picker', () => ({ default: () => null }));

const renderPage = () => render(
  <IntlProvider locale='en'>
    <UserThemePage />
  </IntlProvider>,
);

describe('user theme page', () => {
  afterEach(() => {
    cleanup();
    document.documentElement.removeAttribute('style');
  });

  it('starts from the last saved overrides when reopened', async () => {
    vi.mocked(apiRequestPut).mockResolvedValue({});
    const first = renderPage();

    const [input] = screen.getAllByRole('textbox');
    const variable = input.getAttribute('aria-label');
    fireEvent.change(input, { target: { value: '#123456' } });
    fireEvent.blur(input, { target: { value: '#123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save changes' }));
    await screen.findByText('Saved');
    first.unmount();

    renderPage();

    expect(screen.getAllByRole('textbox', { name: variable })[0].value).toBe('#123456');
  });
});
