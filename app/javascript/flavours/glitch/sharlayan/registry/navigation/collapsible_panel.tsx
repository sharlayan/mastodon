import { useCallback, useId, useState } from 'react';

import KeyboardArrowDownIcon from '@/material-icons/400-24px/keyboard_arrow_down.svg?react';
import KeyboardArrowUpIcon from '@/material-icons/400-24px/keyboard_arrow_up.svg?react';
import type { IconProp } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';

export const SharlayanCollapsiblePanel: React.FC<{
  children: React.ReactNode[];
  title: string;
  collapseTitle: string;
  expandTitle: string;
  icon: string;
  iconComponent: IconProp;
}> = ({ children, icon, iconComponent, title, collapseTitle, expandTitle }) => {
  const [expanded, setExpanded] = useState(false);
  const accessibilityId = useId();
  const handleClick = useCallback((event?: React.MouseEvent) => {
    event?.preventDefault();
    setExpanded((value) => !value);
  }, []);

  return (
    <li className='navigation-panel__list-panel'>
      <div className='navigation-panel__list-panel__header'>
        <ColumnLink
          transparent
          icon={icon}
          iconComponent={iconComponent}
          text={title}
          id={`${accessibilityId}-title`}
          onClick={handleClick}
        />

        {children.length > 0 && (
          <>
            <div className='navigation-panel__list-panel__header__sep' />
            <IconButton
              icon='down'
              expanded={expanded}
              iconComponent={
                expanded ? KeyboardArrowUpIcon : KeyboardArrowDownIcon
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
          className='navigation-panel__list-panel__items navigation-panel__list-panel__items--with-icons'
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
