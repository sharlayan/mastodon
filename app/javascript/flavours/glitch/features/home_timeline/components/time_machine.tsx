import { useCallback, useId, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { CalendarIcon } from '@phosphor-icons/react';

import { ColumnHeaderButton } from '@/flavours/glitch/components/column_header';
import { PopoverMenuCard } from '@/flavours/glitch/components/menu/card';

const MAX_LOOKBACK_MS = 7 * 24 * 60 * 60 * 1000;

const toDatetimeLocal = (date: Date) => {
  const pad = (value: number) => String(value).padStart(2, '0');

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

export const isTimeMachineTimestampValid = (timestamp: Date, now: Date) => {
  return (
    timestamp.getTime() >= now.getTime() - MAX_LOOKBACK_MS && timestamp <= now
  );
};

const getTimeMachineBounds = (now: Date) => {
  const earliest = new Date(now.getTime() - MAX_LOOKBACK_MS);

  const min = new Date(earliest);
  min.setSeconds(0, 0);

  if (min < earliest) {
    min.setMinutes(min.getMinutes() + 1);
  }

  const max = new Date(now);
  max.setSeconds(0, 0);

  return { min: toDatetimeLocal(min), max: toDatetimeLocal(max) };
};

export const HomeTimelineTimeMachine: React.FC<{
  onSelect: (timestamp: Date) => void;
}> = ({ onSelect }) => {
  const [value, setValue] = useState('');
  const inputId = useId();
  const headingId = useId();
  const now = new Date();
  const { min, max } = getTimeMachineBounds(now);
  const timestamp = useMemo(() => (value ? new Date(value) : null), [value]);
  const isValid =
    timestamp !== null &&
    !Number.isNaN(timestamp.getTime()) &&
    isTimeMachineTimestampValid(timestamp, now);

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();

      if (timestamp && isTimeMachineTimestampValid(timestamp, new Date())) {
        onSelect(timestamp);
      }
    },
    [onSelect, timestamp],
  );

  const handleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setValue(event.target.value);
    },
    [],
  );

  return (
    <section aria-labelledby={headingId}>
      <h3 id={headingId}>
        <FormattedMessage
          id='home.time_machine.title'
          defaultMessage='Time machine'
        />
      </h3>
      <p className='setting-toggle__label'>
        <FormattedMessage
          id='home.time_machine.hint'
          defaultMessage='Jump to your home timeline at a time from the past 7 days.'
        />
      </p>
      <form onSubmit={handleSubmit}>
        <label htmlFor={inputId}>
          <FormattedMessage
            id='home.time_machine.time'
            defaultMessage='Date and time'
          />
        </label>
        <div className='column-settings__row'>
          <input
            id={inputId}
            type='datetime-local'
            className='glitch-setting-text setting-text'
            value={value}
            min={min}
            max={max}
            required
            onChange={handleChange}
          />
          <button type='submit' className='button' disabled={!isValid}>
            <FormattedMessage
              id='home.time_machine.go'
              defaultMessage='Go to time'
            />
          </button>
        </div>
      </form>
    </section>
  );
};

export const HomeTimelineTimeMachineButton: React.FC<{
  onSelect: (timestamp: Date) => void;
}> = ({ onSelect }) => {
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<HTMLDivElement | null>(null);

  const handleClose = useCallback(() => {
    setOpen(false);
  }, []);

  const handleSelect = useCallback(
    (timestamp: Date) => {
      onSelect(timestamp);
      setOpen(false);
    },
    [onSelect],
  );

  const handleToggle = useCallback(() => {
    setOpen((value) => !value);
  }, []);

  return (
    <div ref={setTarget}>
      <ColumnHeaderButton
        icon={CalendarIcon}
        aria-expanded={open}
        onClick={handleToggle}
      >
        <FormattedMessage
          id='home.time_machine.title'
          defaultMessage='Time machine'
        />
      </ColumnHeaderButton>
      <PopoverMenuCard
        isOpen={open}
        reference={target}
        placement='bottom-end'
        offset={8}
        onClose={handleClose}
        maxWidth='min(360px, calc(100vw - 32px))'
      >
        <div className='column-settings'>
          <HomeTimelineTimeMachine onSelect={handleSelect} />
        </div>
      </PopoverMenuCard>
    </div>
  );
};
