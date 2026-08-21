import { useCallback, useEffect } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import VisibilityOffIcon from '@/material-icons/400-24px/visibility_off.svg?react';
import { expandTimeline } from 'flavours/glitch/actions/timelines';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import StatusListContainer from 'flavours/glitch/features/ui/containers/status_list_container';
import { useAppDispatch } from 'flavours/glitch/store';

const TIMELINE_ID = 'rp-hidden';
const ENDPOINT = '/api/v1/timelines/rp_hidden';

const messages = defineMessages({
  title: { id: 'column.rp_hidden', defaultMessage: 'Deleted posts' },
});

export const RpHiddenTimeline: React.FC = () => {
  const dispatch = useAppDispatch();
  const intl = useIntl();

  useEffect(() => {
    void dispatch(expandTimeline(TIMELINE_ID, ENDPOINT));
  }, [dispatch]);

  const handleLoadMore = useCallback(
    (maxId: string) => {
      void dispatch(expandTimeline(TIMELINE_ID, ENDPOINT, { max_id: maxId }));
    },
    [dispatch],
  );

  return (
    <Column bindToDocument label={intl.formatMessage(messages.title)}>
      <ColumnHeader
        icon='visibility-off'
        iconComponent={VisibilityOffIcon}
        title={intl.formatMessage(messages.title)}
        showBackButton
        scrollTopOnClick
      />

      <StatusListContainer
        trackScroll
        scrollKey={TIMELINE_ID}
        timelineId={TIMELINE_ID}
        onLoadMore={handleLoadMore}
        emptyMessage={
          <FormattedMessage
            id='empty_column.rp_hidden'
            defaultMessage='There are no deleted posts to review.'
          />
        }
        bindToDocument
      />

      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};
