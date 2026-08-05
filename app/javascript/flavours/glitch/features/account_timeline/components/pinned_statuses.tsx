import type { FC } from 'react';

import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { Badge } from '@/flavours/glitch/components/badge';
import { Button } from '@/flavours/glitch/components/button';
import { Icon } from '@/flavours/glitch/components/icon';
import { StatusHeader } from '@/flavours/glitch/components/status/header';
import type { StatusHeaderRenderFn } from '@/flavours/glitch/components/status/header';
import StatusIcons from '@/flavours/glitch/components/status_icons';
import IconPinned from '@/images/icons/icon_pinned.svg?react';

import { useAccountContext } from '../hooks/useAccountContext';
import classes from '../styles.module.scss';

export const renderPinnedStatusHeader: StatusHeaderRenderFn = ({
  featured,
  mediaIcons,
  settings,
  collapseEnabled,
  collapseButtonCharacterLimit,
  collapsed,
  setCollapsed,
  ...args
}) => {
  const icons = settings && (
    <StatusIcons
      status={args.status}
      mediaIcons={mediaIcons}
      settings={settings}
      collapsible={collapseEnabled}
      collapseButtonCharacterLimit={collapseButtonCharacterLimit}
      collapsed={collapsed}
      setCollapsed={setCollapsed}
    />
  );

  if (!featured) {
    return <StatusHeader {...args} contentBeforeDate={icons} />;
  }
  return (
    <StatusHeader
      {...args}
      className={classes.pinnedStatusHeader}
      contentBeforeDate={
        <>
          <Badge
            className={classes.pinnedBadge}
            icon={<Icon id='pinned' icon={IconPinned} />}
            label={
              <FormattedMessage
                id='account.timeline.pinned'
                defaultMessage='Pinned'
              />
            }
          />
          {icons}
        </>
      }
    />
  );
};

export const PinnedShowAllButton: FC = () => {
  const { onShowAllPinned } = useAccountContext();

  return (
    <Button
      onClick={onShowAllPinned}
      className={classNames(classes.pinnedViewAllButton, 'focusable')}
    >
      <Icon id='pinned' icon={IconPinned} />
      <FormattedMessage
        id='account.timeline.pinned.view_all'
        defaultMessage='View all pinned posts'
      />
    </Button>
  );
};
