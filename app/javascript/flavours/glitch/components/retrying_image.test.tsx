import { act, fireEvent, render, screen } from '@testing-library/react';

import { RetryingImage } from './retrying_image';

describe('RetryingImage', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('stops retrying a broken image on focus after a bounded number of attempts', () => {
    render(<RetryingImage alt='avatar' src='https://example.com/a.png' />);
    const sources = new Set<string>();
    const fail = () => {
      const image = screen.queryByAltText('avatar');
      if (!image) return;
      sources.add(image.getAttribute('src') ?? '');
      fireEvent.error(image);
    };

    for (const delay of [5_000, 15_000, 30_000]) {
      fail();
      vi.setSystemTime(Date.now() + delay);
      act(() => {
        vi.advanceTimersByTime(delay);
      });
    }

    for (let index = 0; index < 5; index += 1) {
      fail();
      vi.setSystemTime(Date.now() + 1_000);
      act(() => {
        window.dispatchEvent(new Event('focus'));
      });
    }

    fail();

    expect(sources.size).toBe(6);
    expect(screen.queryByAltText('avatar')).toBeNull();
  });
});
