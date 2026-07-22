import PropTypes from 'prop-types';
import { useEffect, useMemo, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';
import { fromJS, Map as ImmutableMap } from 'immutable';
import ImmutablePropTypes from 'react-immutable-proptypes';

import { DndContext, KeyboardSensor, PointerSensor, closestCenter, useSensor, useSensors } from '@dnd-kit/core';
import { restrictToParentElement, restrictToVerticalAxis } from '@dnd-kit/modifiers';
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import DragIndicatorIcon from '@/material-icons/400-24px/drag_indicator.svg?react';
import { Icon } from '@/flavours/glitch/components/icon';
import { IconButton } from '@/flavours/glitch/components/icon_button';
import { Button } from '@/flavours/glitch/components/button';
import { openModal } from '@/flavours/glitch/actions/modal';
import { computeStatusActionBarOrder, STATUS_ACTION_BAR_DEFAULT_HIDDEN, STATUS_ACTION_BAR_ITEMS, statusActionBarItemMessages } from '@/flavours/glitch/features/status_action_bar/items';
import { useAppDispatch } from '@/flavours/glitch/store';

const Item = ({ itemKey, index, length, checked, intl, onToggle, onMove }) => {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: itemKey });

  return (
    <li ref={setNodeRef} style={{ transform: CSS.Translate.toString(transform), transition }} className={classNames('local-settings__navigation-panel__item', { dragging: isDragging })}>
      <Icon id='drag' icon={DragIndicatorIcon} className='local-settings__navigation-panel__item__handle' aria-label={intl.formatMessage({ id: 'settings.status_action_bar.drag_handle', defaultMessage: 'Drag to reorder' })} {...listeners} {...attributes} />
      <label htmlFor={`status-action-bar--${itemKey}`}>
        <input id={`status-action-bar--${itemKey}`} type='checkbox' checked={checked} onChange={() => { onToggle(itemKey); }} />
        <FormattedMessage {...statusActionBarItemMessages[itemKey]} />
      </label>
      <div className='local-settings__navigation-panel__item__actions'>
        <IconButton icon='arrow-up' iconComponent={ArrowUpwardIcon} title={intl.formatMessage({ id: 'settings.status_action_bar.move_up', defaultMessage: 'Move up' })} onClick={() => { onMove(itemKey, -1); }} disabled={index === 0} />
        <IconButton icon='arrow-down' iconComponent={ArrowDownwardIcon} title={intl.formatMessage({ id: 'settings.status_action_bar.move_down', defaultMessage: 'Move down' })} onClick={() => { onMove(itemKey, 1); }} disabled={index === length - 1} />
      </div>
    </li>
  );
};

Item.propTypes = { itemKey: PropTypes.string.isRequired, index: PropTypes.number.isRequired, length: PropTypes.number.isRequired, checked: PropTypes.bool.isRequired, intl: PropTypes.object.isRequired, onToggle: PropTypes.func.isRequired, onMove: PropTypes.func.isRequired };

const StatusActionBarSettings = ({ settings, onChange, intl }) => {
  const dispatch = useAppDispatch();
  const storedOrder = settings.getIn(['status_action_bar', 'order']);
  const storedHidden = settings.getIn(['status_action_bar', 'hidden']) ?? ImmutableMap();
  const normalizedStoredOrder = useMemo(() => computeStatusActionBarOrder(storedOrder?.toJS()), [storedOrder]);
  const [order, setOrder] = useState(normalizedStoredOrder);
  const [hidden, setHidden] = useState(storedHidden);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }), useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }));

  useEffect(() => {
    setOrder(normalizedStoredOrder);
    setHidden(storedHidden);
  }, [normalizedStoredOrder, storedHidden]);

  const dirty = !fromJS(order).equals(fromJS(normalizedStoredOrder)) || !hidden.equals(storedHidden);
  const defaultHidden = useMemo(() => ImmutableMap(STATUS_ACTION_BAR_DEFAULT_HIDDEN.map(key => [key, true])), []);
  const usingDefaults = fromJS(order).equals(fromJS(STATUS_ACTION_BAR_ITEMS)) && hidden.equals(defaultHidden);
  const move = (key, delta) => {
    const index = order.indexOf(key);
    const target = index + delta;
    if (target >= 0 && target < order.length) setOrder(arrayMove(order, index, target));
  };
  const handleDragEnd = ({ active, over }) => {
    if (!over || active.id === over.id) return;
    const oldIndex = order.indexOf(active.id);
    const newIndex = order.indexOf(over.id);
    if (oldIndex !== -1 && newIndex !== -1) setOrder(arrayMove(order, oldIndex, newIndex));
  };
  const handleSave = () => {
    onChange(['status_action_bar'], fromJS({ order, hidden: hidden.toJS() }));
  };
  const handleReset = () => {
    dispatch(openModal({
      modalType: 'CONFIRM',
      modalProps: {
        title: intl.formatMessage({ id: 'settings.status_action_bar.reset_confirm', defaultMessage: 'Reset post action bar settings to their defaults?' }),
        confirm: intl.formatMessage({ id: 'settings.status_action_bar.reset', defaultMessage: 'Use defaults' }),
        onConfirm: () => {
          setOrder([...STATUS_ACTION_BAR_ITEMS]);
          setHidden(defaultHidden);
        },
      },
    }));
  };

  return (
    <div className='glitch local-settings__page status_action_bar'>
      <h1><FormattedMessage id='settings.status_action_bar' defaultMessage='Post action bar' /></h1>
      <p className='hint'><FormattedMessage id='settings.status_action_bar.hint' defaultMessage='Choose which optional actions appear on posts and arrange their order. Reply, boost, and more are always shown.' /></p>
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd} modifiers={[restrictToVerticalAxis, restrictToParentElement]}>
        <SortableContext items={order} strategy={verticalListSortingStrategy}>
          <ul className='local-settings__navigation-panel'>
            {order.map((key, index) => <Item key={key} itemKey={key} index={index} length={order.length} checked={hidden.get(key) !== true} intl={intl} onToggle={itemKey => { setHidden(current => current.set(itemKey, current.get(itemKey) !== true)); }} onMove={move} />)}
          </ul>
        </SortableContext>
      </DndContext>
      <div className='local-settings__page__sync-actions'>
        <Button secondary onClick={handleReset} disabled={usingDefaults}><FormattedMessage id='settings.status_action_bar.reset' defaultMessage='Use defaults' /></Button>
        <Button onClick={handleSave} disabled={!dirty}><FormattedMessage id='settings.status_action_bar.save' defaultMessage='Save changes' /></Button>
      </div>
    </div>
  );
};

StatusActionBarSettings.propTypes = { settings: ImmutablePropTypes.map.isRequired, onChange: PropTypes.func.isRequired, intl: PropTypes.object.isRequired };

export default StatusActionBarSettings;
