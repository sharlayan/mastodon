import { useEffect, useMemo, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import StarIcon from '@/material-icons/400-24px/star-fill.svg?react';
import SquigglyArrow from '@/svg-icons/squiggly_arrow.svg?react';
import { fetchClips, deleteClip } from 'flavours/glitch/actions/clips';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import { me } from 'flavours/glitch/initial_state';
import type { Clip } from 'flavours/glitch/models/clip';
import { getOrderedAccountClips } from 'flavours/glitch/selectors/clips';
import { MyArchiveTabs } from 'flavours/glitch/sharlayan/my_archive/tabs';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

import { ClipFavouriteButton } from './components/favourite_button';

const messages = defineMessages({
  heading: { id: 'column.clips', defaultMessage: 'Clips' },
  create: { id: 'clips.create_clip', defaultMessage: 'Create clip' },
  edit: { id: 'clips.edit', defaultMessage: 'Edit clip' },
  delete: { id: 'clips.delete', defaultMessage: 'Delete clip' },
  more: { id: 'status.more', defaultMessage: 'More' },
});

const ClipItem: React.FC<{
  clip: Clip;
}> = ({ clip }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const { id, title, public: isPublic, statuses_count: statusesCount } = clip;

  const handleDeleteClick = useCallback(() => {
    void dispatch(deleteClip({ id }));
  }, [dispatch, id]);

  const menu = useMemo(
    () => [
      { text: intl.formatMessage(messages.edit), to: `/clips/${id}/edit` },
      {
        text: intl.formatMessage(messages.delete),
        action: handleDeleteClick,
        dangerous: true,
      },
    ],
    [intl, id, handleDeleteClick],
  );

  return (
    <div className='lists__item'>
      <Link to={`/clips/${id}`} className='lists__item__title'>
        <Icon
          id={isPublic ? 'globe' : 'lock'}
          icon={isPublic ? PublicIcon : LockIcon}
        />
        <span>{title}</span>
        <span className='lists__item__count'>
          <FormattedMessage
            id='clips.statuses_count'
            defaultMessage='{count, plural, one {# post} other {# posts}}'
            values={{ count: statusesCount }}
          />
        </span>
      </Link>

      <ClipFavouriteButton
        clip={clip}
        className='clip-favourite-button star-icon'
      />

      <Dropdown
        scrollKey='clips'
        items={menu}
        icon='ellipsis-h'
        iconComponent={MoreHorizIcon}
        title={intl.formatMessage(messages.more)}
      />
    </div>
  );
};

const Clips: React.FC<{
  multiColumn?: boolean;
}> = ({ multiColumn }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const clips = useAppSelector((state) => getOrderedAccountClips(state, me));
  const { signedIn } = useIdentity();

  useEffect(() => {
    if (signedIn) {
      void dispatch(fetchClips());
    }
  }, [signedIn, dispatch]);

  const emptyMessage = (
    <>
      <span>
        <FormattedMessage
          id='clips.no_clips_yet'
          defaultMessage='No clips yet.'
        />
        <br />
        <FormattedMessage
          id='clips.create_a_clip_to_organize'
          defaultMessage='Create a clip to collect posts you want to keep'
        />
      </span>

      <SquigglyArrow className='empty-column-indicator__arrow' />
    </>
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        title={intl.formatMessage(messages.heading)}
        icon='note-stack-add'
        iconComponent={NoteStackAddIcon}
        multiColumn={multiColumn}
        extraButton={
          signedIn && (
            <>
              <Link
                to='/clips/favourites'
                className='column-header__button'
                title={intl.formatMessage({
                  id: 'clips.favourites',
                  defaultMessage: 'Favorite clips',
                })}
                aria-label={intl.formatMessage({
                  id: 'clips.favourites',
                  defaultMessage: 'Favorite clips',
                })}
              >
                <Icon id='star' icon={StarIcon} />
              </Link>
              <Link
                to='/clips/new'
                className='column-header__button'
                title={intl.formatMessage(messages.create)}
                aria-label={intl.formatMessage(messages.create)}
              >
                <Icon id='plus' icon={AddIcon} />
              </Link>
            </>
          )
        }
        appendContent={<MyArchiveTabs />}
      />

      <ScrollableList
        scrollKey='clips'
        emptyMessage={emptyMessage}
        bindToDocument={!multiColumn}
      >
        {signedIn ? (
          clips.map((clip) => <ClipItem key={clip.id} clip={clip} />)
        ) : (
          <NotSignedInIndicator />
        )}
      </ScrollableList>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default Clips;
