import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import ExpandLessIcon from '@/material-icons/400-24px/expand_less.svg?react';
import ExpandMoreIcon from '@/material-icons/400-24px/expand_more.svg?react';

import { IconButton } from './icon_button';

const messages = defineMessages({
  collapse: { id: 'status.collapse', defaultMessage: 'Collapse' },
  uncollapse: { id: 'status.uncollapse', defaultMessage: 'Uncollapse' },
});

export const CollapseButton: React.FC<{
  collapsed: boolean;
  setCollapsed: (value: boolean) => void;
}> = ({ collapsed, setCollapsed }) => {
  const intl = useIntl();

  const handleClick = useCallback(
    (event: React.MouseEvent) => {
      if (event.button === 0) {
        setCollapsed(!collapsed);
        event.preventDefault();
        event.stopPropagation();
      }
    },
    [collapsed, setCollapsed],
  );

  return (
    <IconButton
      className='status__collapse-button'
      active={collapsed}
      title={intl.formatMessage(
        collapsed ? messages.uncollapse : messages.collapse,
      )}
      icon={collapsed ? 'expand-more' : 'expand-less'}
      iconComponent={collapsed ? ExpandMoreIcon : ExpandLessIcon}
      onClick={handleClick}
    />
  );
};
