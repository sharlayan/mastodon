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
});
