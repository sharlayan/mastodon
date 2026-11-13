import { act, fireEvent, render, screen } from '@testing-library/react';

import { RetryingImage } from '../retrying_image';

describe('<RetryingImage />', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('hides a failed image and retries it with a cache-busting URL', () => {
    render(<RetryingImage src='/avatar.png' alt='avatar' />);

    fireEvent.error(screen.getByRole('img'));
    expect(screen.queryByRole('img')).toBeNull();

    act(() => {
      void vi.advanceTimersByTime(5_000);
    });

    expect(screen.getByRole('img').getAttribute('src')).toMatch(
      /^\/avatar\.png\?_sharlayan_retry=\d+$/,
    );
  });

  it('loads a changed source immediately after an error', () => {
    const { rerender } = render(<RetryingImage src='/old.png' alt='avatar' />);

    fireEvent.error(screen.getByRole('img'));
    rerender(<RetryingImage src='/new.png' alt='avatar' />);

    expect(screen.getByRole('img').getAttribute('src')).toBe('/new.png');
  });
});
