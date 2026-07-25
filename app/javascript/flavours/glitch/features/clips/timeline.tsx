import { useEffect, useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import { useParams, useHistory, Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import { useIdentity } from '@/flavours/glitch/identity_context';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import { fetchClip, deleteClip } from 'flavours/glitch/actions/clips';
import { expandClipTimeline } from 'flavours/glitch/actions/timelines';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { BundleColumnError } from 'flavours/glitch/features/ui/components/bundle_column_error';
import StatusListContainer from 'flavours/glitch/features/ui/containers/status_list_container';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { ClipFavouriteButton } from './components/favourite_button';

const ClipTimeline: React.FC<{
  multiColumn?: boolean;
}> = ({ multiColumn }) => {
  const dispatch = useAppDispatch();
  const history = useHistory();
  const { accountId } = useIdentity();
  const { id } = useParams<{ id: string }>();
  const clip = useAppSelector((state) => state.clips.get(id));

  useEffect(() => {
    void dispatch(fetchClip({ id }));
    void dispatch(expandClipTimeline(id));
  }, [dispatch, id]);

  const handleLoadMore = useCallback(
    (maxId: string) => {
      void dispatch(expandClipTimeline(id, { maxId }));
    },
    [dispatch, id],
  );

  const handleDeleteClick = useCallback(() => {
    void dispatch(deleteClip({ id })).then(() => {
      history.push('/clips');
      return '';
    });
  }, [dispatch, history, id]);

  if (clip === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const title = clip ? clip.title : id;
  const isOwner = !!clip && clip.account_id === accountId;

  return (
    <Column bindToDocument={!multiColumn} label={title}>
      <ColumnHeader
        icon='note-stack-add'
        iconComponent={NoteStackAddIcon}
        title={title}
        multiColumn={multiColumn}
        showBackButton
        extraButton={
          clip && (
            <ClipFavouriteButton
              clip={clip}
              className='column-header__button clip-favourite-button star-icon'
            />
          )
        }
      >
        {isOwner && (
          <div className='column-settings'>
            <section className='column-header__links'>
              <Link
                to={`/clips/${id}/edit`}
                className='text-btn column-header__setting-btn'
              >
                <Icon id='pencil' icon={EditIcon} />{' '}
                <FormattedMessage id='clips.edit' defaultMessage='Edit clip' />
              </Link>

              <button
                type='button'
                className='text-btn column-header__setting-btn'
                tabIndex={0}
                onClick={handleDeleteClick}
              >
                <Icon id='trash' icon={DeleteIcon} />{' '}
                <FormattedMessage
                  id='clips.delete'
                  defaultMessage='Delete clip'
                />
              </button>
            </section>
          </div>
        )}
      </ColumnHeader>

      {clip === undefined ? (
        <div className='scrollable'>
          <LoadingIndicator />
        </div>
      ) : (
        <StatusListContainer
          trackScroll
          scrollKey='clip_timeline'
          timelineId={`clip:${id}`}
          onLoadMore={handleLoadMore}
          emptyMessage={
            <FormattedMessage
              id='empty_column.clip'
              defaultMessage='There are no posts in this clip yet.'
            />
          }
          bindToDocument={!multiColumn}
        />
      )}

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ClipTimeline;
