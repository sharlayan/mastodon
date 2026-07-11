import { useEffect, useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import CheckCircleIcon from '@/material-icons/400-24px/check_circle.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import ErrorIcon from '@/material-icons/400-24px/error.svg?react';
import InfoIcon from '@/material-icons/400-24px/info.svg?react';
import WarningIcon from '@/material-icons/400-24px/warning.svg?react';
import {
  fetchBoardAnnouncements,
  readBoardAnnouncement,
} from 'flavours/glitch/actions/board_announcements';
import type {
  ApiBoardAnnouncementIcon,
  ApiBoardAnnouncementJSON,
} from 'flavours/glitch/api_types/board_announcements';
import { EmojiHTML } from 'flavours/glitch/components/emoji/html';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { boardAnnouncementsEnabled } from 'flavours/glitch/initial_state';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

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
  dismiss: {
    id: 'board_announcements.dismiss',
    defaultMessage: 'Dismiss',
  },
});

const Banner: React.FC<{ banner: ApiBoardAnnouncementJSON }> = ({ banner }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleDismiss = useCallback(() => {
    void dispatch(readBoardAnnouncement({ id: banner.id }));
  }, [dispatch, banner.id]);

  return (
    <div
      className={`board-announcement-banner board-announcement-banner--${banner.icon}`}
    >
      <Icon
        id={`board-announcement-${banner.icon}`}
        icon={ICON_COMPONENTS[banner.icon]}
        className='board-announcement-banner__icon'
      />
      <div className='board-announcement-banner__body'>
        <strong className='board-announcement-banner__title'>
          {banner.title}
        </strong>
        <EmojiHTML
          className='board-announcement-banner__content translate'
          htmlString={banner.content}
          extraEmojis={banner.emojis}
        />
      </div>
      <IconButton
        className='board-announcement-banner__dismiss'
        icon='times'
        iconComponent={CloseIcon}
        title={intl.formatMessage(messages.dismiss)}
        onClick={handleDismiss}
      />
    </div>
  );
};

export const BoardAnnouncementBanner: React.FC = () => {
  const dispatch = useAppDispatch();

  const items = useAppSelector((state) => state.boardAnnouncements.items);
  const loaded = useAppSelector((state) => state.boardAnnouncements.loaded);

  useEffect(() => {
    if (!boardAnnouncementsEnabled || loaded) {
      return;
    }

    void dispatch(fetchBoardAnnouncements());
  }, [dispatch, loaded]);

  if (!boardAnnouncementsEnabled) {
    return null;
  }

  const banners = items.filter(
    (item) => item.display === 'banner' && !item.read,
  );

  if (banners.length === 0) {
    return null;
  }

  return (
    <div className='board-announcement-banners'>
      {banners.map((banner) => (
        <Banner key={banner.id} banner={banner} />
      ))}
    </div>
  );
};
