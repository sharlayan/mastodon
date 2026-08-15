import PropTypes from 'prop-types';

import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';
import { fromJS, Map as ImmutableMap } from 'immutable';
import ImmutablePropTypes from 'react-immutable-proptypes';

import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  restrictToParentElement,
  restrictToVerticalAxis,
} from '@dnd-kit/modifiers';
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import DragIndicatorIcon from '@/material-icons/400-24px/drag_indicator.svg?react';
import { openModal } from '@/flavours/glitch/actions/modal';
import { Button } from '@/flavours/glitch/components/button';
import { Icon } from '@/flavours/glitch/components/icon';
import { IconButton } from '@/flavours/glitch/components/icon_button';
import { computeNavigationOrder, isNavigationItemAlwaysVisible, NAVIGATION_PANEL_ITEMS, navigationPanelItemMessages } from '@/flavours/glitch/features/navigation_panel/items';
import {
  collectionsEnabled,
  federatedTimelineEnabled,
  localTimelineEnabled,
} from '@/flavours/glitch/initial_state';
import { useAppDispatch } from '@/flavours/glitch/store';

const NavigationPanelSettingsItem = ({ itemKey, index, length, checked, locked, intl, onToggle, onMove }) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: itemKey });

  const style = {
    transform: CSS.Translate.toString(transform),
    transition,
  };

  return (
    <li
      ref={setNodeRef}
      style={style}
      className={classNames('local-settings__navigation-panel__item', { dragging: isDragging })}
    >
      <Icon
        id='drag'
        icon={DragIndicatorIcon}
        className='local-settings__navigation-panel__item__handle'
        aria-label={intl.formatMessage({ id: 'settings.navigation_panel.drag_handle', defaultMessage: 'Drag to reorder' })}
        {...listeners}
        {...attributes}
      />
      <label htmlFor={`navigation-panel--${itemKey}`}>
        <input
          id={`navigation-panel--${itemKey}`}
          type='checkbox'
          checked={locked ? true : checked}
          disabled={locked}
          onChange={() => { onToggle(itemKey); }}
        />
        <FormattedMessage {...navigationPanelItemMessages[itemKey]} />
      </label>
      <div className='local-settings__navigation-panel__item__actions'>
        <IconButton
          icon='arrow-up'
          iconComponent={ArrowUpwardIcon}
          title={intl.formatMessage({ id: 'settings.navigation_panel.move_up', defaultMessage: 'Move up' })}
          onClick={() => { onMove(itemKey, -1); }}
          disabled={index === 0}
        />
        <IconButton
          icon='arrow-down'
          iconComponent={ArrowDownwardIcon}
          title={intl.formatMessage({ id: 'settings.navigation_panel.move_down', defaultMessage: 'Move down' })}
          onClick={() => { onMove(itemKey, 1); }}
          disabled={index === length - 1}
        />
      </div>
    </li>
  );
};

NavigationPanelSettingsItem.propTypes = {
  itemKey: PropTypes.string.isRequired,
  index: PropTypes.number.isRequired,
  length: PropTypes.number.isRequired,
  checked: PropTypes.bool.isRequired,
  locked: PropTypes.bool,
  intl: PropTypes.object.isRequired,
  onToggle: PropTypes.func.isRequired,
  onMove: PropTypes.func.isRequired,
};

const NavigationPanelSettings = ({ settings, onChange, intl }) => {
  const dispatch = useAppDispatch();
  const unavailableItems = [
    ...(!federatedTimelineEnabled ? ['federated'] : []),
    ...(!localTimelineEnabled ? ['local'] : []),
    ...(!collectionsEnabled ? ['collections'] : []),
  ];
  const availableItems = NAVIGATION_PANEL_ITEMS.filter(
    (key) => !unavailableItems.includes(key),
  );
  const order = computeNavigationOrder(settings.getIn(['navigation_panel', 'order'])?.toJS()).filter((key) => availableItems.includes(key));
  const hidden = settings.getIn(['navigation_panel', 'hidden']) ?? ImmutableMap();
  const usingDefaults = fromJS(order).equals(fromJS(availableItems)) && hidden.isEmpty();

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 5,
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  const move = (key, delta) => {
    const index = order.indexOf(key);
    const target = index + delta;

    if (target < 0 || target >= order.length) {
      return;
    }

    onChange(['navigation_panel', 'order'], fromJS(arrayMove(order, index, target)));
  };

  const toggle = (key) => {
    if (isNavigationItemAlwaysVisible(key)) {
      return;
    }

    onChange(['navigation_panel', 'hidden'], hidden.set(key, hidden.get(key) !== true));
  };

  const handleDragEnd = (event) => {
    const { active, over } = event;

    if (!over || active.id === over.id) {
      return;
    }

    const oldIndex = order.indexOf(active.id);
    const newIndex = order.indexOf(over.id);

    if (oldIndex === -1 || newIndex === -1) {
      return;
    }

    onChange(['navigation_panel', 'order'], fromJS(arrayMove(order, oldIndex, newIndex)));
  };

  const handleReset = () => {
    dispatch(openModal({
      modalType: 'CONFIRM',
      modalProps: {
        title: intl.formatMessage({ id: 'settings.navigation_panel.reset_confirm', defaultMessage: 'Reset navigation panel settings to their defaults?' }),
        confirm: intl.formatMessage({ id: 'settings.navigation_panel.reset', defaultMessage: 'Use defaults' }),
        onConfirm: () => {
          onChange(['navigation_panel'], fromJS({ order: [], hidden: {} }));
        },
      },
    }));
  };

  return (
    <div className='glitch local-settings__page navigation_panel'>
      <h1><FormattedMessage id='settings.navigation_panel' defaultMessage='Navigation panel' /></h1>
      <p className='hint'>
        <FormattedMessage id='settings.navigation_panel.hint' defaultMessage='Reorder or hide the links in the navigation sidebar. Hidden links still appear on mobile layouts.' />
      </p>
      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragEnd={handleDragEnd}
        modifiers={[restrictToVerticalAxis, restrictToParentElement]}
      >
        <SortableContext items={order} strategy={verticalListSortingStrategy}>
          <ul className='local-settings__navigation-panel'>
            {order.map((key, index) => (
              <NavigationPanelSettingsItem
                key={key}
                itemKey={key}
                index={index}
                length={order.length}
                checked={hidden.get(key) !== true}
                locked={isNavigationItemAlwaysVisible(key)}
                intl={intl}
                onToggle={toggle}
                onMove={move}
              />
            ))}
          </ul>
        </SortableContext>
      </DndContext>
      <div className='local-settings__page__sync-actions'>
        <Button secondary onClick={handleReset} disabled={usingDefaults}>
          <FormattedMessage id='settings.navigation_panel.reset' defaultMessage='Use defaults' />
        </Button>
      </div>
    </div>
  );
};

NavigationPanelSettings.propTypes = {
  settings: ImmutablePropTypes.map.isRequired,
  onChange: PropTypes.func.isRequired,
  intl: PropTypes.object.isRequired,
};

export default NavigationPanelSettings;
