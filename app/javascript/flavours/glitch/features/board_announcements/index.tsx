import { useEffect, useState, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import ArticleIcon from '@/material-icons/400-24px/article.svg?react';
import CheckCircleIcon from '@/material-icons/400-24px/check_circle.svg?react';
import ErrorIcon from '@/material-icons/400-24px/error.svg?react';
import ExpandMoreIcon from '@/material-icons/400-24px/expand_more.svg?react';
import InfoIcon from '@/material-icons/400-24px/info.svg?react';
import RefreshIcon from '@/material-icons/400-24px/refresh.svg?react';
import WarningIcon from '@/material-icons/400-24px/warning.svg?react';
import {
  fetchBoardAnnouncements,
  readBoardAnnouncement,
} from 'flavours/glitch/actions/board_announcements';
import {
  addColumn,
  removeColumn,
  moveColumn,
} from 'flavours/glitch/actions/columns';
import { openModal } from 'flavours/glitch/actions/modal';
import type {
  ApiBoardAnnouncementJSON,
  ApiBoardAnnouncementIcon,
} from 'flavours/glitch/api_types/board_announcements';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { EmojiHTML } from 'flavours/glitch/components/emoji/html';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useLayout } from 'flavours/glitch/hooks/useLayout';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { useBoardAnnouncementHtml } from './html';
import { ReactionsBar } from './reactions';

const ICON_COMPONENTS: Record<
  ApiBoardAnnouncementIcon,
  React.FC<React.SVGProps<SVGSVGElement>>
> = {
  info: InfoIcon,
  warning: WarningIcon,
  error: ErrorIcon,
  success: CheckCircleIcon,
};

const messages = defineMessages({
  heading: {
    id: 'column.board_announcements',
    defaultMessage: 'Announcements',
  },
  refresh: {
    id: 'board_announcements.refresh',
    defaultMessage: 'Refresh',
  },
  markRead: {
    id: 'board_announcements.mark_read',
    defaultMessage: 'Got it',
  },
});

const WIDE_QUERY = '(min-width: 720px)';

const useWideMatch = () => {
  const [matches, setMatches] = useState(
    () => window.matchMedia(WIDE_QUERY).matches,
  );

  useEffect(() => {
    const watcher = window.matchMedia(WIDE_QUERY);
    const handler = () => {
      setMatches(watcher.matches);
    };

    watcher.addEventListener('change', handler);
    handler();

    return () => {
      watcher.removeEventListener('change', handler);
    };
  }, []);

  return matches;
};

const Announcement: React.FC<{
  announcement: ApiBoardAnnouncementJSON;
  wide: boolean;
  defaultExpanded: boolean;
}> = ({ announcement, wide, defaultExpanded }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [expanded, setExpanded] = useState(defaultExpanded);
  const htmlProps = useBoardAnnouncementHtml();

  const showBody = expanded;

  const handleToggle = useCallback(() => {
    setExpanded((prev) => !prev);
  }, []);

  const handleMarkRead = useCallback(() => {
    void dispatch(readBoardAnnouncement({ id: announcement.id }));
  }, [dispatch, announcement.id]);

  const handleContentClick = useCallback(
    (event: React.MouseEvent<HTMLElement>) => {
      const target = event.target as HTMLElement;
      const image = target.closest<HTMLImageElement>('img:not(.emojione)');

      if (!image || !event.currentTarget.contains(image)) {
        return;
      }

      event.preventDefault();

      const images = Array.from(
        event.currentTarget.querySelectorAll<HTMLImageElement>(
          'img:not(.emojione)',
        ),
      );
      const index = images.indexOf(image);

      const media = fromJS(
        images.map((element) => ({
          type: 'image',
          url: element.src,
          preview_url: element.src,
          description: element.alt || null,
          meta: {
            original: {
              width: element.naturalWidth,
              height: element.naturalHeight,
            },
          },
        })),
      );

      dispatch(
        openModal({
          modalType: 'MEDIA',
          modalProps: { media, index: index < 0 ? 0 : index },
        }),
      );
    },
    [dispatch],
  );

  const date = (
    <time
      className='board-announcement__date'
      dateTime={announcement.published_at}
    >
      {intl.formatDate(announcement.published_at, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      })}
    </time>
  );

  const heading = (
    <>
      <Icon
        id={`board-announcement-${announcement.icon}`}
        icon={ICON_COMPONENTS[announcement.icon]}
        className={`board-announcement__icon board-announcement__icon--${announcement.icon}`}
      />
      <h2 className='board-announcement__title'>{announcement.title}</h2>
      {date}
    </>
  );

  return (
    <article
      className={classNames(
        'board-announcement',
        `board-announcement--icon-${announcement.icon}`,
        {
          'board-announcement--wide': wide,
          'board-announcement--collapsed': !expanded,
        },
      )}
    >
      <button
        type='button'
        className='board-announcement__header'
        aria-expanded={expanded}
        onClick={handleToggle}
      >
        {heading}
        <Icon
          id='expand-more'
          icon={ExpandMoreIcon}
          className='board-announcement__chevron'
        />
      </button>

      {showBody && (
        <>
          <EmojiHTML
            className='board-announcement__content translate'
            htmlString={announcement.content}
            extraEmojis={announcement.emojis}
            {...htmlProps}
            onClick={handleContentClick}
          />
          <ReactionsBar
            reactions={announcement.reactions}
            id={announcement.id}
          />
          {announcement.need_confirmation_to_read && !announcement.read && (
            <div className='board-announcement__confirm'>
              <button type='button' className='button' onClick={handleMarkRead}>
                {intl.formatMessage(messages.markRead)}
              </button>
            </div>
          )}
        </>
      )}
    </article>
  );
};

const BoardAnnouncements: React.FC<{
  columnId?: string;
  multiColumn?: boolean;
}> = ({ columnId, multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { singleColumn } = useLayout();
  const wideMatch = useWideMatch();
  const wide = singleColumn || wideMatch;

  const items = useAppSelector((state) => state.boardAnnouncements.items);
  const isLoading = useAppSelector(
    (state) => state.boardAnnouncements.isLoading,
  );
  const loaded = useAppSelector((state) => state.boardAnnouncements.loaded);

  useEffect(() => {
    void dispatch(fetchBoardAnnouncements());
  }, [dispatch]);

  useEffect(() => {
    items
      .filter((item) => !item.read && !item.need_confirmation_to_read)
      .forEach((item) => {
        void dispatch(readBoardAnnouncement({ id: item.id }));
      });
  }, [dispatch, items]);

  const handlePin = useCallback(() => {
    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('BOARD_ANNOUNCEMENTS', {}));
    }
  }, [dispatch, columnId]);

  const handleMove = useCallback(
    (dir: number) => {
      if (columnId) dispatch(moveColumn(columnId, dir));
    },
    [dispatch, columnId],
  );

  const handleRefresh = useCallback(() => {
    void dispatch(fetchBoardAnnouncements());
  }, [dispatch]);

  const pinned = !!columnId;

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='article'
        iconComponent={ArticleIcon}
        title={intl.formatMessage(messages.heading)}
        onPin={handlePin}
        onMove={handleMove}
        scrollTopOnClick
        pinned={pinned}
        multiColumn={multiColumn}
        showBackButton
        extraButton={
          <button
            type='button'
            className='column-header__button'
            title={intl.formatMessage(messages.refresh)}
            aria-label={intl.formatMessage(messages.refresh)}
            disabled={isLoading}
            onClick={handleRefresh}
          >
            <Icon id='refresh' icon={RefreshIcon} />
          </button>
        }
      />

      <div className='scrollable'>
        {isLoading && items.length === 0 && <LoadingIndicator />}

        {loaded && items.length === 0 && (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='empty_column.board_announcements'
              defaultMessage='There are no announcements yet.'
            />
          </div>
        )}

        {items.map((item, index) => (
          <Announcement
            key={item.id}
            announcement={item}
            wide={wide}
            defaultExpanded={index === 0}
          />
        ))}
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default BoardAnnouncements;
