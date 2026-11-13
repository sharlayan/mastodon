import { FormattedMessage } from 'react-intl';

import { CircularProgress } from '@/flavours/glitch-classic/components/circular_progress';
import { Column } from '@/flavours/glitch-classic/components/column';
import { ColumnHeader as LegacyColumnHeader } from '@/flavours/glitch-classic/components/column/header';
import type { ColumnHeaderProps } from '@/flavours/glitch-classic/components/column/header';
import { ColumnHeader } from '@/flavours/glitch-classic/components/column_header';
import { isRedesignEnabled } from '@/flavours/glitch-classic/utils/environment';

import classes from './styles.module.scss';

export const ColumnLoading: React.FC<ColumnHeaderProps> = (otherProps) => (
  <Column>
    {isRedesignEnabled() ? (
      <ColumnHeader title='' />
    ) : (
      <LegacyColumnHeader {...otherProps} />
    )}
    <div className='scrollable'>
      <div className={classes.loadingWrapper}>
        <CircularProgress size={30} strokeWidth={2} />
        <FormattedMessage
          id='loading_indicator.label'
          defaultMessage='Loading…'
        />
      </div>
    </div>
  </Column>
);
