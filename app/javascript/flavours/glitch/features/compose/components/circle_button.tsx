import { useCallback, useEffect, useMemo } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import { fetchCircles } from '@/flavours/glitch/actions/circles';
import { changeComposeCircle } from '@/flavours/glitch/actions/compose_typed';
import { Dropdown } from '@/flavours/glitch/components/dropdown_menu';
import { Icon } from '@/flavours/glitch/components/icon';
import { circlesEnabled } from '@/flavours/glitch/initial_state';
import { getOrderedCircles } from '@/flavours/glitch/selectors/circles';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import GroupIcon from '@/material-icons/400-24px/group.svg?react';

const messages = defineMessages({
  circle: { id: 'compose_form.circle.label', defaultMessage: 'Circle' },
  select: {
    id: 'compose_form.circle.select',
    defaultMessage: 'Select circle',
  },
  none: { id: 'compose_form.circle.none', defaultMessage: 'No circle' },
});

interface CircleButtonProps {
  disabled?: boolean;
}

export const CircleButton: FC<CircleButtonProps> = ({ disabled = false }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const circles = useAppSelector((state) => getOrderedCircles(state));
  const circleId = useAppSelector(
    (state) => state.compose.get('circle_id') as string | null,
  );

  useEffect(() => {
    if (circlesEnabled) {
      void dispatch(fetchCircles());
    }
  }, [dispatch]);

  const handleSelect = useCallback(
    (id: string | null) => {
      dispatch(changeComposeCircle(id));
    },
    [dispatch],
  );

  const items = useMemo(() => {
    const options = circles.map((circle) => ({
      text: circle.title,
      action: () => {
        handleSelect(circle.id);
      },
    }));

    if (circleId) {
      return [
        {
          text: intl.formatMessage(messages.none),
          action: () => {
            handleSelect(null);
          },
        },
        ...options,
      ];
    }

    return options;
  }, [circles, circleId, handleSelect, intl]);

  const selectedCircle = circles.find((circle) => circle.id === circleId);

  const label = selectedCircle
    ? selectedCircle.title
    : intl.formatMessage(messages.select);

  if (!circlesEnabled || circles.length === 0) {
    return null;
  }

  return (
    <Dropdown items={items} disabled={disabled} scrollKey='compose-circle'>
      <button
        type='button'
        title={intl.formatMessage(messages.circle)}
        disabled={disabled}
        className={classNames('dropdown-button', 'circle-button', {
          active: !!circleId,
        })}
      >
        <Icon id='group' icon={GroupIcon} />
        <span className='dropdown-button__label'>{label}</span>
      </button>
    </Dropdown>
  );
};
