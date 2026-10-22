import { useCallback, useId, useState } from 'react';

import { FormattedDate, FormattedMessage } from 'react-intl';

import { CalendarDotsIcon } from '@phosphor-icons/react';

import { changeScheduledAt } from '@/flavours/glitch/actions/compose';
import { Button } from '@/flavours/glitch/components/button/redesign';
import { MenuCard } from '@/flavours/glitch/components/menu/card';
import { Popover } from '@/flavours/glitch/components/popover';
import { getComposeControlState } from '@/flavours/glitch/sharlayan/compose/calculations';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import classes from './styles.module.scss';

function localDateTime(date: Date) {
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

const minimumScheduleTime = () =>
  Math.ceil((Date.now() + 5 * 60_000) / 60_000) * 60_000;

export const ComposeScheduleButton: React.FC = () => {
  const dispatch = useAppDispatch();
  const scheduledAt = useAppSelector(
    (state) => state.compose.get('scheduled_at') as string | null,
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  const isEditingScheduled = useAppSelector((state) => {
    const id = state.compose.get('id') as string | null;
    return !!id && !!scheduledAt && !state.statuses.has(id);
  });
  const showScheduleButton = useAppSelector(
    (state) => !!state.local_settings.get('show_schedule_button'),
  );
  const { scheduleDisabled, scheduleVisible } = getComposeControlState({
    isEditing,
    isEditingScheduled,
    showScheduleButton,
  });
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<HTMLButtonElement | null>(null);
  const [value, setValue] = useState('');
  const [minimum, setMinimum] = useState(minimumScheduleTime);
  const id = useId();
  const parsed = new Date(value).getTime();
  const invalid = !Number.isFinite(parsed) || parsed < minimum;

  const onToggle = useCallback(() => {
    if (!open) {
      const nextMinimum = minimumScheduleTime();
      setMinimum(nextMinimum);
      const date = scheduledAt ? new Date(scheduledAt) : new Date(nextMinimum);
      setValue(localDateTime(date));
    }
    setOpen(!open);
  }, [open, scheduledAt]);
  const onClose = useCallback(() => {
    setOpen(false);
  }, []);
  const onConfirm = useCallback(() => {
    if (invalid) return;
    const nextMinimum = minimumScheduleTime();
    if (parsed < nextMinimum) {
      setMinimum(nextMinimum);
      return;
    }
    dispatch(changeScheduledAt(new Date(parsed).toISOString()));
    setOpen(false);
  }, [dispatch, invalid, parsed]);
  const onClear = useCallback(() => {
    dispatch(changeScheduledAt(null));
    setOpen(false);
  }, [dispatch]);
  const onChange: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    (event) => {
      setValue(event.target.value);
    },
    [],
  );
  const onKeyDown: React.KeyboardEventHandler<HTMLInputElement> = useCallback(
    (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        onConfirm();
      }
    },
    [onConfirm],
  );
  if (!scheduleVisible) return null;

  return (
    <>
      <Button
        ref={setTarget}
        size='sm'
        leadingIcon={CalendarDotsIcon}
        onClick={onToggle}
        disabled={scheduleDisabled}
        aria-expanded={open}
      >
        {scheduledAt ? (
          <FormattedDate
            value={scheduledAt}
            dateStyle='short'
            timeStyle='short'
          />
        ) : (
          <FormattedMessage
            id='compose_form.schedule'
            defaultMessage='Schedule'
          />
        )}
      </Button>
      <Popover
        isOpen={open}
        onClose={onClose}
        reference={target}
        placement='bottom-start'
        offset={4}
      >
        {({ props }) => (
          <MenuCard {...props} className={classes.schedule}>
            <label htmlFor={id}>
              <FormattedMessage
                id='compose_form.schedule_for'
                defaultMessage='Schedule for'
              />
            </label>
            <input
              id={id}
              type='datetime-local'
              value={value}
              min={localDateTime(new Date(minimum))}
              onChange={onChange}
              onKeyDown={onKeyDown}
              autoFocus
            />
            {invalid && (
              <p role='alert'>
                <FormattedMessage
                  id='compose_form.schedule_min_warning'
                  defaultMessage='Must be at least 5 minutes from now'
                />
              </p>
            )}
            <div className={classes.customControls}>
              <Button size='sm' disabled={isEditingScheduled} onClick={onClear}>
                <FormattedMessage
                  id='compose_form.clear_schedule'
                  defaultMessage='Clear'
                />
              </Button>
              <Button
                size='sm'
                variant='solid'
                disabled={invalid}
                onClick={onConfirm}
              >
                <FormattedMessage
                  id='compose_form.set_schedule'
                  defaultMessage='Set'
                />
              </Button>
            </div>
          </MenuCard>
        )}
      </Popover>
    </>
  );
};
