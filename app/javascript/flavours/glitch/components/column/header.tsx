import { useCallback, useState } from 'react';

import { FormattedMessage, defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import { SlidersHorizontalIcon } from '@phosphor-icons/react';

import { openModal } from '@/flavours/glitch/actions/modal';
import {
  ColumnHeader as BaseColumnHeader,
  ColumnHeaderButton,
} from '@/flavours/glitch/components/column_header';
import type { IconProp } from '@/flavours/glitch/components/icon';
import { useColumnWidthContext } from '@/flavours/glitch/features/ui/util/column_width_context';
import { useIdentity } from '@/flavours/glitch/identity_context';
import { useAppDispatch } from '@/flavours/glitch/store';
import { hasReactChildren } from '@/flavours/glitch/utils/has_react_children';

import { useAppHistory } from '../router';

import classes from './header.module.scss';

export const messages = defineMessages({
  show: { id: 'column_header.show_settings', defaultMessage: 'Show settings' },
  hide: { id: 'column_header.hide_settings', defaultMessage: 'Hide settings' },
  moveLeft: {
    id: 'column_header.moveLeft_settings',
    defaultMessage: 'Move column to the left',
  },
  moveRight: {
    id: 'column_header.moveRight_settings',
    defaultMessage: 'Move column to the right',
  },
  back: { id: 'column_back_button.label', defaultMessage: 'Back' },
});

export interface ColumnHeaderProps {
  title?: React.ReactNode;
  icon?: string;
  iconComponent?: IconProp;
  active?: boolean;
  children?: React.ReactNode;
  className?: string;
  pinned?: boolean;
  multiColumn?: boolean;
  extraButton?: React.ReactNode;
  showBackButton?: boolean;
  placeholder?: boolean;
  appendContent?: React.ReactNode;
  collapseIssues?: boolean;
  scrollTopOnClick?: boolean;
  onClick?: () => void;
  onBack?: () => void;
  onMove?: (arg0: number) => void;
  onPin?: () => void;
}

export const ColumnHeader: React.FC<ColumnHeaderProps> = ({
  title,
  children,
  className,
  pinned,
  multiColumn,
  extraButton,
  showBackButton,
  appendContent,
  collapseIssues,
  onBack,
  onMove,
  onPin,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { columnId, width, onSave } = useColumnWidthContext();
  const { signedIn } = useIdentity();
  const history = useAppHistory();
  const [collapsed, setCollapsed] = useState(true);

  const handleToggleClick = useCallback(() => {
    setCollapsed((value) => !value);
  }, []);

  const handleMoveLeft = useCallback(() => {
    onMove?.(-1);
  }, [onMove]);

  const handleMoveRight = useCallback(() => {
    onMove?.(1);
  }, [onMove]);

  const handlePin = useCallback(() => {
    if (!pinned) {
      history.replace('/');
    }

    onPin?.();
  }, [history, pinned, onPin]);

  const handleWidth = useCallback(() => {
    if ((columnId || onSave) && width) {
      dispatch(
        openModal({
          modalType: 'COLUMN_WIDTH',
          modalProps: { columnId, width, onSave },
        }),
      );
    }
  }, [columnId, dispatch, onSave, width]);

  const canAdjustWidth = multiColumn && Boolean(width && (columnId ?? onSave));
  const canPin = multiColumn && (pinned === true || !!onPin);
  const hasColumnActions = multiColumn && (canPin || canAdjustWidth);
  const hasSettings =
    signedIn && (hasReactChildren(children) || hasColumnActions);

  let withBackButton: boolean | 'auto' = false;
  if (!pinned) {
    if (showBackButton) {
      withBackButton = true;
    } else if (multiColumn) {
      withBackButton = 'auto';
    }
  }

  const settingsLabel = intl.formatMessage(
    collapsed ? messages.show : messages.hide,
  );

  const extraButtons =
    hasReactChildren(extraButton) || hasSettings ? (
      <div className={classes.buttons}>
        {extraButton}
        {hasSettings && (
          <ColumnHeaderButton
            icon={SlidersHorizontalIcon}
            aria-expanded={!collapsed}
            onClick={handleToggleClick}
            className={classNames(collapseIssues && classes.withIssue)}
          >
            {settingsLabel}
          </ColumnHeaderButton>
        )}
      </div>
    ) : undefined;

  const settingsPanel = hasSettings && !collapsed && (
    <div className={classes.panel}>
      {hasColumnActions && (
        <div className={classes.columnActions}>
          {canPin && (
            <button
              className='text-btn column-header__setting-btn'
              onClick={handlePin}
              type='button'
            >
              {pinned ? (
                <FormattedMessage
                  id='column_header.unpin'
                  defaultMessage='Unpin'
                />
              ) : (
                <FormattedMessage id='column_header.pin' defaultMessage='Pin' />
              )}
            </button>
          )}
          {canAdjustWidth && (
            <button
              className='text-btn column-header__setting-btn'
              onClick={handleWidth}
              type='button'
            >
              <FormattedMessage
                id='column_header.adjust_width'
                defaultMessage='Adjust width'
              />
            </button>
          )}
          {pinned && onMove && (
            <>
              <button
                className='text-btn column-header__setting-btn'
                onClick={handleMoveLeft}
                type='button'
              >
                {intl.formatMessage(messages.moveLeft)}
              </button>
              <button
                className='text-btn column-header__setting-btn'
                onClick={handleMoveRight}
                type='button'
              >
                {intl.formatMessage(messages.moveRight)}
              </button>
            </>
          )}
        </div>
      )}
      {children}
    </div>
  );

  const extraStickyContent =
    settingsPanel || hasReactChildren(appendContent) ? (
      <>
        {settingsPanel}
        {appendContent}
      </>
    ) : undefined;

  return (
    <BaseColumnHeader
      title={title}
      className={className}
      withBackButton={withBackButton}
      onBack={onBack}
      extraButtons={extraButtons}
      extraStickyContent={extraStickyContent}
    />
  );
};
