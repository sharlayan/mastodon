import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { ScheduleButton } from '../schedule_button';

vi.mock('flavours/glitch/components/popover', () => ({
  Popover: ({ isOpen, children }) => isOpen ? children({ props: {}, placement: 'bottom' }) : null,
}));

afterEach(cleanup);

describe('<ScheduleButton />', () => {
  it('prevents clearing an existing reservation while still allowing its time to change', () => {
    const onScheduleChange = vi.fn();
    render(
      <IntlProvider locale='en'>
        <ScheduleButton scheduledAt='2030-12-01T12:00:00Z' isEditingScheduled onScheduleChange={onScheduleChange} />
      </IntlProvider>,
    );
    fireEvent.click(screen.getByRole('button'));

    const clearButton = screen.getByRole('button', { name: 'Clear' });
    expect(clearButton.disabled).toBe(true);
    fireEvent.click(clearButton);
    expect(onScheduleChange).not.toHaveBeenCalled();

    const timeInput = document.querySelector('input[type="datetime-local"]');
    fireEvent.change(timeInput, { target: { value: '2031-01-01T12:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set' }));

    expect(onScheduleChange).toHaveBeenCalledWith(new Date('2031-01-01T12:00').toISOString());
  });

  it('allows clearing the schedule of a new composition', () => {
    const onScheduleChange = vi.fn();
    render(
      <IntlProvider locale='en'>
        <ScheduleButton scheduledAt='2030-12-01T12:00:00Z' onScheduleChange={onScheduleChange} />
      </IntlProvider>,
    );
    fireEvent.click(screen.getByRole('button'));
    fireEvent.click(screen.getByRole('button', { name: 'Clear' }));

    expect(onScheduleChange).toHaveBeenCalledWith(null);
  });

  it('prefills a time the server accepts as at least five minutes ahead', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2031-03-01T12:00:45'));
    try {
      const onScheduleChange = vi.fn();
      render(
        <IntlProvider locale='en'>
          <ScheduleButton onScheduleChange={onScheduleChange} />
        </IntlProvider>,
      );
      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByRole('button', { name: 'Set' }));

      expect(onScheduleChange).toHaveBeenCalledTimes(1);
      const scheduled = new Date(onScheduleChange.mock.calls[0][0]).getTime();
      expect(scheduled).toBeGreaterThan(Date.now() + 5 * 60_000);
    } finally {
      vi.useRealTimers();
    }
  });

  it('treats a time within five minutes from now as too early', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2031-03-01T12:00:45'));
    try {
      render(
        <IntlProvider locale='en'>
          <ScheduleButton onScheduleChange={vi.fn()} />
        </IntlProvider>,
      );
      fireEvent.click(screen.getByRole('button'));
      const timeInput = document.querySelector('input[type="datetime-local"]');
      fireEvent.change(timeInput, { target: { value: '2031-03-01T12:05' } });

      expect(screen.getByRole('button', { name: 'Set' }).disabled).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});
