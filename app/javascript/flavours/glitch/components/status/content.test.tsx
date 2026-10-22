import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import type { StatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import { StatusContent } from './content';

const mocks = vi.hoisted(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });
  return {
    globalMfm: true,
    catSpeak: false,
    observe: vi.fn(),
    setContainerElement: vi.fn(),
  };
});

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
}));
vi.mock('@/flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  get mfmEnabled() {
    return mocks.globalMfm;
  },
}));
vi.mock('@/flavours/glitch/hooks/useAccount', () => ({
  useAccount: () => undefined,
}));
vi.mock('@/flavours/glitch/hooks/useObserver', () => ({
  useResizeObserver: () => ({ observe: mocks.observe }),
}));
vi.mock('@/flavours/glitch/sharlayan/emoji_info_tooltip', () => ({
  useSharlayanEmojiInfoTooltip: () => ({
    setContainerElement: mocks.setContainerElement,
    tooltip: <span data-testid='emoji-tooltip' />,
  }),
}));
vi.mock('@/flavours/glitch/sharlayan/nyaify', async (importOriginal) => ({
  ...(await importOriginal()),
  catSpeakVisibleFor: () => mocks.catSpeak,
}));
vi.mock('@/flavours/glitch/components/mfm', async (importOriginal) => ({
  ...(await importOriginal()),
  MfmRenderer: ({
    text,
    animationsEnabled,
  }: {
    text: string;
    animationsEnabled: boolean;
  }) => (
    <span data-testid='mfm' data-animations={animationsEnabled}>
      {text}
    </span>
  ),
}));
vi.mock('./hooks', () => ({ useHandlersForStatus: () => ({}) }));
vi.mock('../emoji/html', () => ({
  EmojiHTML: ({
    htmlString,
    extraEmojis: _,
    ...props
  }: {
    htmlString: string;
    extraEmojis: unknown;
  }) => <div {...props} dangerouslySetInnerHTML={{ __html: htmlString }} />,
}));

const status = {
  id: '1',
  account: 'account-1',
  contentHtml: '<p>HTML fallback</p>',
  language: 'en',
  emojis: [],
  mfm: true,
  mfm_text: '$[font.serif Source]',
} as unknown as StatusShape;

function setSettings(meta = {}, collapsed = false) {
  vi.mocked(useAppSelector).mockImplementation((selector) =>
    selector({
      meta: fromJS(meta),
      local_settings: fromJS({ collapsed: { enabled: collapsed } }),
    } as unknown as RootState),
  );
}

function renderContent(
  props: Partial<React.ComponentProps<typeof StatusContent>> = {},
) {
  return render(
    <IntlProvider locale='en'>
      <StatusContent status={status} {...props} />
    </IntlProvider>,
  );
}

describe('redesign status content', () => {
  beforeEach(() => {
    mocks.globalMfm = true;
    mocks.catSpeak = false;
    setSettings();
  });

  it('uses MFM source with the animation preference and retains the emoji tooltip', () => {
    setSettings({ mfm_animations: false });
    renderContent();

    expect(screen.getByTestId('mfm').textContent).toBe('$[font.serif Source]');
    expect(screen.getByTestId('mfm').getAttribute('data-animations')).toBe(
      'false',
    );
    expect(screen.getByTestId('emoji-tooltip')).not.toBeNull();
    expect(mocks.setContainerElement).toHaveBeenCalledWith(
      expect.any(HTMLDivElement),
    );
  });

  it.each(['server', 'user', 'status'])(
    'keeps ordinary HTML when the %s MFM gate is off',
    (gate) => {
      if (gate === 'server') mocks.globalMfm = false;
      if (gate === 'user') setSettings({ mfm_enabled: false });
      renderContent({ status: { ...status, mfm: gate !== 'status' } });

      expect(screen.queryByTestId('mfm')).toBeNull();
      expect(screen.getByText('HTML fallback')).not.toBeNull();
    },
  );

  it('uses completed translated content and preserves line breaks instead of showing the source', () => {
    renderContent({
      status: {
        ...status,
        translation: {
          isLoading: false,
          language: 'ko',
          contentHtml: '<p>번역<br>다음 줄</p><p>문단</p>',
        } as StatusShape['translation'],
      },
    });

    expect(screen.getByTestId('mfm').textContent).toBe('번역\n다음 줄\n문단\n');
    expect(screen.getByTestId('mfm').parentElement?.getAttribute('lang')).toBe(
      'ko',
    );
  });

  it('keeps original MFM while translation is loading', () => {
    renderContent({
      status: {
        ...status,
        translation: {
          isLoading: true,
          contentHtml: '<p>Loading</p>',
        } as StatusShape['translation'],
      },
    });
    expect(screen.getByTestId('mfm').textContent).toBe('$[font.serif Source]');
  });

  it('folds MFM according to the preference without navigating when the summary is clicked', () => {
    setSettings({ mfm_fold_mode: 'all' });
    const onClick = vi.fn();
    renderContent({ onClick });

    const summary = screen.getByText('Expand MFM post');
    expect(summary.closest('details')?.hasAttribute('open')).toBe(false);
    fireEvent.click(summary);
    expect(onClick).not.toHaveBeenCalled();
  });

  it.each([
    ['sensitive', '$[spin Spin]', true],
    ['none', '$[spin Spin]', false],
    ['none', 'a'.repeat(1001), true],
  ])('applies %s fold mode to the MFM source', (mode, source, folded) => {
    setSettings({ mfm_fold_mode: mode });
    renderContent({ status: { ...status, mfm_text: source } });
    expect(!!screen.queryByText('Expand MFM post')).toBe(folded);
  });

  it('applies cat speech only through its existing preference gate', () => {
    mocks.catSpeak = true;
    renderContent({
      status: { ...status, mfm: false, contentHtml: '<p>banana</p>' },
    });
    expect(screen.getByText('banyanya')).not.toBeNull();
  });

  it('makes collapsed content inert and unfolds it on click', () => {
    setSettings({}, true);
    const onTogglePostCollapse = vi.fn();
    renderContent({ postCollapsed: true, onTogglePostCollapse });
    const content = screen.getByTestId('mfm').closest('[inert]');
    expect(content).not.toBeNull();
    if (!content?.parentElement) throw new Error('Missing collapsed content');
    fireEvent.click(content.parentElement);
    expect(onTogglePostCollapse).toHaveBeenCalledOnce();
  });

  it('supports shift-click collapse without intercepting ordinary clicks', () => {
    setSettings({}, true);
    const onTogglePostCollapse = vi.fn();
    const onClick = vi.fn();
    renderContent({ onTogglePostCollapse, onClick });
    fireEvent.click(screen.getByTestId('mfm'), { shiftKey: true });
    expect(onTogglePostCollapse).toHaveBeenCalledOnce();
    expect(onClick).not.toHaveBeenCalled();
    fireEvent.click(screen.getByTestId('mfm'));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it('pauses nested media while retaining its DOM and blocks playback while collapsed', () => {
    const pause = vi
      .spyOn(HTMLMediaElement.prototype, 'pause')
      .mockImplementation(() => undefined);
    renderContent({
      postCollapsed: true,
      children: <video aria-label='Embedded video' />,
    });
    const video = screen.getByLabelText('Embedded video');
    expect(video).not.toBeNull();
    expect(pause).toHaveBeenCalledOnce();
    fireEvent.play(video);
    expect(pause).toHaveBeenCalledTimes(2);
    pause.mockRestore();
  });
});
