import { useEffect, useMemo, useState } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import { fetchAntennas } from 'flavours/glitch/actions/antennas';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { CollapsiblePanel } from './collapsible_panel';

const MAX_ANTENNAS = 10;

type Antenna = ImmutableMap<string, string>;

const messages = defineMessages({
  antennas: { id: 'navigation_bar.antennas', defaultMessage: 'Antennas' },
  expand: {
    id: 'navigation_panel.expand_antennas',
    defaultMessage: 'Expand antenna menu',
  },
  collapse: {
    id: 'navigation_panel.collapse_antennas',
    defaultMessage: 'Collapse antenna menu',
  },
});

export const AntennaPanel: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const antennas = useAppSelector(
    (state) => state.antennas as ImmutableMap<string, Antenna | false>,
  );
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void dispatch(fetchAntennas()).then(() => {
      setLoading(false);

      return '';
    });
  }, [dispatch]);

  const orderedAntennas = useMemo(
    () =>
      antennas
        .filter((antenna): antenna is Antenna => !!antenna)
        .toList()
        .sort((a, b) => {
          const aLast = a.get('last_status_id');
          const bLast = b.get('last_status_id');

          if (aLast && bLast) {
            return bLast.localeCompare(aLast);
          }
          if (aLast) {
            return -1;
          }
          if (bLast) {
            return 1;
          }

          return (a.get('title') ?? '').localeCompare(b.get('title') ?? '');
        })
        .slice(0, MAX_ANTENNAS)
        .toArray(),
    [antennas],
  );

  return (
    <CollapsiblePanel
      to='/antennas'
      icon='radar'
      iconComponent={RadarIcon}
      title={intl.formatMessage(messages.antennas)}
      collapseTitle={intl.formatMessage(messages.collapse)}
      expandTitle={intl.formatMessage(messages.expand)}
      loading={loading}
    >
      {orderedAntennas.map((antenna) => (
        <ColumnLink
          icon='radar'
          key={antenna.get('id')}
          iconComponent={RadarIcon}
          text={antenna.get('title') ?? ''}
          to={`/antennas/${antenna.get('id')}`}
          transparent
        />
      ))}
    </CollapsiblePanel>
  );
};
