import { useEffect, useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useParams, useHistory, Link } from 'react-router-dom';

import { isFulfilled } from '@reduxjs/toolkit';

import { Helmet } from '@unhead/react/helmet';

import { useIdentity } from '@/flavours/glitch/identity_context';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import { fetchClip, deleteClip } from 'flavours/glitch/actions/clips';
import {
  addColumn,
  removeColumn,
  moveColumn,
} from 'flavours/glitch/actions/columns';
import { openModal } from 'flavours/glitch/actions/modal';
import { expandClipTimeline } from 'flavours/glitch/actions/timelines';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { BundleColumnError } from 'flavours/glitch/features/ui/components/bundle_column_error';
import StatusListContainer from 'flavours/glitch/features/ui/containers/status_list_container';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { ClipFavouriteButton } from './components/favourite_button';

const messages = defineMessages({
  deleteTitle: {
    id: 'confirmations.delete_clip.title',
    defaultMessage: 'Delete clip?',
  },
  deleteMessage: {
    id: 'confirmations.delete_clip.message',
    defaultMessage: 'Are you sure you want to permanently delete this clip?',
  },
  deleteConfirm: {
    id: 'confirmations.delete_clip.confirm',
    defaultMessage: 'Delete',
  },
});

const ClipTimeline: React.FC<{
  multiColumn?: boolean;
  columnId?: string;
  params?: { id?: string } | null;
}> = ({ multiColumn, columnId, params }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const history = useHistory();
  const { accountId } = useIdentity();
  const { id: routeId } = useParams<{ id: string }>();
  const id = params?.id ?? routeId;
  const pinned = !!columnId;
  const clip = useAppSelector((state) => state.clips.get(id));
  const nextUri = useAppSelector(
    (state) => state.timelines.getIn([`clip:${id}`, 'next']) as string | null,
  );

  useEffect(() => {
    void dispatch(fetchClip({ id }));
    void dispatch(expandClipTimeline(id));
  }, [dispatch, id]);

  const handleLoadMore = useCallback(() => {
    if (nextUri) {
      void dispatch(expandClipTimeline(id, { nextUri }));
    }
  }, [dispatch, id, nextUri]);

  const handleDeleteClick = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'CONFIRM',
        modalProps: {
          title: intl.formatMessage(messages.deleteTitle),
          message: intl.formatMessage(messages.deleteMessage),
          confirm: intl.formatMessage(messages.deleteConfirm),
          onConfirm: () => {
            void dispatch(deleteClip({ id })).then((result) => {
              if (!isFulfilled(result)) {
                return result;
              }

              if (columnId) {
                dispatch(removeColumn(columnId));
              } else {
                history.push('/clips');
              }

              return result;
            });
          },
        },
      }),
    );
  }, [dispatch, history, id, columnId, intl]);

  const handlePin = useCallback(() => {
    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('CLIP', { id }));
    }
  }, [dispatch, columnId, id]);

  const handleMove = useCallback(
    (dir: number) => {
      dispatch(moveColumn(columnId, dir));
    },
    [dispatch, columnId],
  );

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
        onPin={handlePin}
        onMove={handleMove}
        scrollTopOnClick
        pinned={pinned}
        showBackButton={!pinned}
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
          trackScroll={!pinned}
          scrollKey={`clip_timeline-${columnId ?? ''}`}
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
