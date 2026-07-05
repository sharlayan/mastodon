import { useState, useCallback, useId } from 'react';

import KeyboardArrowDownIcon from '@/material-icons/400-24px/keyboard_arrow_down.svg?react';
import KeyboardArrowUpIcon from '@/material-icons/400-24px/keyboard_arrow_up.svg?react';
import type { IconProp } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';

export const CollapsiblePanel: React.FC<{
  children: React.ReactNode[];
  to?: string;
  title: string;
  collapseTitle: string;
  expandTitle: string;
  icon: string;
  iconComponent: IconProp;
  activeIconComponent?: IconProp;
  loading?: boolean;
  showItemIcons?: boolean;
}> = ({
  children,
  to,
  icon,
  iconComponent,
  activeIconComponent,
  title,
  collapseTitle,
  expandTitle,
  loading,
  showItemIcons,
}) => {
  const [expanded, setExpanded] = useState(false);
  const accessibilityId = useId();

  const handleClick = useCallback(
    (e?: React.MouseEvent) => {
      e?.preventDefault();
      setExpanded((value) => !value);
    },
    [setExpanded],
  );

  return (
    <li className='navigation-panel__list-panel'>
      <div className='navigation-panel__list-panel__header'>
        <ColumnLink
          transparent
          to={to}
          onClick={to ? undefined : handleClick}
          icon={icon}
          iconComponent={iconComponent}
          activeIconComponent={activeIconComponent}
          text={title}
          id={`${accessibilityId}-title`}
        />

        {(loading || children.length > 0) && (
          <>
            <div className='navigation-panel__list-panel__header__sep' />

            <IconButton
              icon='down'
              expanded={expanded}
              iconComponent={
                loading
                  ? LoadingIndicator
                  : expanded
                    ? KeyboardArrowUpIcon
                    : KeyboardArrowDownIcon
              }
              title={expanded ? collapseTitle : expandTitle}
              onClick={handleClick}
              ariaControls={`${accessibilityId}-content`}
            />
          </>
        )}
      </div>

      {children.length > 0 && expanded && (
        <div
          className={
            showItemIcons
              ? 'navigation-panel__list-panel__items navigation-panel__list-panel__items--with-icons'
              : 'navigation-panel__list-panel__items'
          }
          role='region'
          id={`${accessibilityId}-content`}
          aria-labelledby={`${accessibilityId}-title`}
        >
          {children}
        </div>
      )}
    </li>
  );
};
