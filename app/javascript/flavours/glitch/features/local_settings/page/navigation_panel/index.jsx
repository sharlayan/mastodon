import PropTypes from 'prop-types';

import { FormattedMessage } from 'react-intl';

import { fromJS, Map as ImmutableMap } from 'immutable';
import ImmutablePropTypes from 'react-immutable-proptypes';

import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import { IconButton } from '@/flavours/glitch/components/icon_button';
import { computeNavigationOrder, navigationPanelItemMessages } from '@/flavours/glitch/features/navigation_panel/items';
import { useIdentity } from '@/flavours/glitch/identity_context';
import { collectionsEnabled, roleplayMode } from '@/flavours/glitch/initial_state';
import { isAdministrator } from '@/flavours/glitch/permissions';

const NavigationPanelSettings = ({ settings, onChange, intl }) => {
  const { permissions } = useIdentity();
  const adminTimelineAvailable = roleplayMode && isAdministrator(permissions);
  const order = computeNavigationOrder(settings.getIn(['navigation_panel', 'order'])?.toJS())
    .filter((key) => key !== 'admin_timeline' || adminTimelineAvailable)
    .filter((key) => key !== 'collections' || collectionsEnabled);
  const hidden = settings.getIn(['navigation_panel', 'hidden']) ?? ImmutableMap();

  const move = (key, delta) => {
    const index = order.indexOf(key);
    const target = index + delta;

    if (target < 0 || target >= order.length) {
      return;
    }

    const next = order.slice();
    next.splice(index, 1);
    next.splice(target, 0, key);

    onChange(['navigation_panel', 'order'], fromJS(next));
  };

  const toggle = (key) => {
    onChange(['navigation_panel', 'hidden'], hidden.set(key, hidden.get(key) !== true));
  };

  return (
    <div className='glitch local-settings__page navigation_panel'>
      <h1><FormattedMessage id='settings.navigation_panel' defaultMessage='Navigation panel' /></h1>
      <p className='hint'>
        <FormattedMessage id='settings.navigation_panel.hint' defaultMessage='Reorder or hide the links in the navigation sidebar. Hidden links still appear on mobile layouts.' />
      </p>
      <ul className='local-settings__navigation-panel'>
        {order.map((key, index) => (
          <li key={key} className='local-settings__navigation-panel__item'>
            <label htmlFor={`navigation-panel--${key}`}>
              <input
                id={`navigation-panel--${key}`}
                type='checkbox'
                checked={hidden.get(key) !== true}
                onChange={() => { toggle(key); }}
              />
              <FormattedMessage {...navigationPanelItemMessages[key]} />
            </label>
            <div className='local-settings__navigation-panel__item__actions'>
              <IconButton
                icon='arrow-up'
                iconComponent={ArrowUpwardIcon}
                title={intl.formatMessage({ id: 'settings.navigation_panel.move_up', defaultMessage: 'Move up' })}
                onClick={() => { move(key, -1); }}
                disabled={index === 0}
              />
              <IconButton
                icon='arrow-down'
                iconComponent={ArrowDownwardIcon}
                title={intl.formatMessage({ id: 'settings.navigation_panel.move_down', defaultMessage: 'Move down' })}
                onClick={() => { move(key, 1); }}
                disabled={index === order.length - 1}
              />
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
};

NavigationPanelSettings.propTypes = {
  settings: ImmutablePropTypes.map.isRequired,
  onChange: PropTypes.func.isRequired,
  intl: PropTypes.object.isRequired,
};

export default NavigationPanelSettings;
