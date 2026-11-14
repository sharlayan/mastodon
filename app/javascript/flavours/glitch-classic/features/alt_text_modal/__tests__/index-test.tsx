// app/javascript/flavours/glitch-classic/features/alt_text_modal/__tests__/index-test.tsx

import { IntlProvider } from 'react-intl';

import { List, Map } from 'immutable';

import { render } from '@testing-library/react';
import { vi } from 'vitest';

import { FocusTargetProvider } from '@/flavours/glitch-classic/components/navigation_focus_target';
import { Router } from '@/flavours/glitch-classic/components/router';
import type { RootState } from 'flavours/glitch-classic/store';
import { useAppSelector } from 'flavours/glitch-classic/store';

import { AltTextModal } from '../index';

vi.mock('flavours/glitch-classic/store', () => ({
  useAppSelector: vi.fn(),
  useAppDispatch: () => vi.fn(),
}));

describe('<AltTextModal />', () => {
  const mediaId = '123';
  const handleClose = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  const renderComponent = () => {
    return render(
      <Router>
        <FocusTargetProvider>
          <IntlProvider locale='en' messages={{}}>
            <AltTextModal mediaId={mediaId} onClose={handleClose} />
          </IntlProvider>
        </FocusTargetProvider>
      </Router>,
    );
  };

  it('renders thumbnail upload button when video is unattached', () => {
    vi.mocked(useAppSelector).mockImplementation(
      (selector: (state: RootState) => unknown) => {
        const mockState = {
          compose: Map({
            language: 'en',
            media_attachments: List([
              Map({
                id: mediaId,
                type: 'video',
                unattached: true,
                meta: Map({ focus: Map({ x: 0, y: 0 }) }),
              }),
            ]),
          }),
          accounts: Map(),
        } as unknown as RootState;

        return selector(mockState);
      },
    );

    const { container } = renderComponent();

    const uploadInput = container.querySelector('#upload-modal__thumbnail');
    expect(uploadInput).not.toBeNull();
  });

  it('hides thumbnail upload button when video is attached', () => {
    vi.mocked(useAppSelector).mockImplementation(
      (selector: (state: RootState) => unknown) => {
        const mockState = {
          compose: Map({
            language: 'en',
            media_attachments: List([
              Map({
                id: mediaId,
                type: 'video',
                unattached: false,
                meta: Map({ focus: Map({ x: 0, y: 0 }) }),
              }),
            ]),
          }),
          accounts: Map(),
        } as unknown as RootState;

        return selector(mockState);
      },
    );

    const { container } = renderComponent();

    const uploadInput = container.querySelector('#upload-modal__thumbnail');
    expect(uploadInput).toBeNull();
  });
});
