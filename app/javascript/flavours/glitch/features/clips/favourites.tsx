import { useEffect } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import StarIcon from '@/material-icons/400-24px/star-fill.svg?react';
import { fetchFavouriteClips } from 'flavours/glitch/actions/clips';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import { getOrderedClips } from 'flavours/glitch/selectors/clips';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { ClipFavouriteButton } from './components/favourite_button';

const messages = defineMessages({
  heading: { id: 'column.clip_favourites', defaultMessage: 'Favorite clips' },
});

const ClipFavourites: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const clips = useAppSelector((state) =>
    getOrderedClips(state).filter((clip) => clip.favourited),
  );

  useEffect(() => {
    void dispatch(fetchFavouriteClips());
  }, [dispatch]);

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        title={intl.formatMessage(messages.heading)}
        icon='star'
        iconComponent={StarIcon}
        multiColumn={multiColumn}
        showBackButton
      />

      <ScrollableList
        scrollKey='clip_favourites'
        emptyMessage={
          <FormattedMessage
            id='empty_column.clip_favourites'
            defaultMessage="You haven't favorited any clips yet."
          />
        }
        bindToDocument={!multiColumn}
      >
        {clips.map((clip) => (
          <div key={clip.id} className='lists__item'>
            <Link to={`/clips/${clip.id}`} className='lists__item__title'>
              <Icon
                id={clip.public ? 'globe' : 'lock'}
                icon={clip.public ? PublicIcon : LockIcon}
              />
              <span>{clip.title}</span>
              <span className='lists__item__count'>
                <FormattedMessage
                  id='clips.statuses_count'
                  defaultMessage='{count, plural, one {# post} other {# posts}}'
                  values={{ count: clip.statuses_count }}
                />
              </span>
            </Link>
            <ClipFavouriteButton
              clip={clip}
              className='clip-favourite-button star-icon'
            />
          </div>
        ))}
      </ScrollableList>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ClipFavourites;
