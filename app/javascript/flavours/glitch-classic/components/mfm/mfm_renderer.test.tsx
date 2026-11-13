import { render } from '@testing-library/react';

import type { MfmRenderer as MfmRendererType } from './mfm_renderer';

let MfmRenderer: typeof MfmRendererType;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ MfmRenderer } = await import('./mfm_renderer'));
}, 30_000);

const hrefs = (container: HTMLElement) =>
  Array.from(container.querySelectorAll('a')).map((link) =>
    link.getAttribute('href'),
  );

describe('MfmRenderer links', () => {
  it('links local mentions by username', () => {
    const { container } = render(<MfmRenderer text='hi @alice' />);

    expect(hrefs(container)).toEqual(['/@alice']);
  });

  it('resolves mentions against the status mentions and the author server', () => {
    const { container } = render(
      <MfmRenderer
        text='@alice @bob @carol@other.tld'
        authorAcct='dave@misskey.example'
        mentions={[
          {
            username: 'alice',
            acct: 'alice@misskey.example',
            url: 'https://misskey.example/@alice',
          },
          {
            username: 'alice',
            acct: 'alice',
            url: 'https://local.example/@alice',
          },
        ]}
      />,
    );

    expect(hrefs(container)).toEqual([
      'https://misskey.example/@alice',
      'https://misskey.example/@bob',
      'https://other.tld/@carol',
    ]);
  });

  it('encodes hashtag links', () => {
    const { container } = render(<MfmRenderer text='#c%d #g&h=1' />);

    expect(hrefs(container)).toEqual(['/tags/c%25d', '/tags/g%26h%3D1']);
  });
});
