import { useCallback } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import CalendarTodayIcon from '@/material-icons/400-24px/calendar_today.svg?react';
import CloudIcon from '@/material-icons/400-24px/cloud.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import ExtensionIcon from '@/material-icons/400-24px/extension.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import DraftIcon from '@/material-icons/400-24px/save.svg?react';
import VisibilityOffIcon from '@/material-icons/400-24px/visibility_off.svg?react';
import { openModal } from 'flavours/glitch-classic/actions/modal';
import { ColumnLink } from 'flavours/glitch-classic/features/ui/components/column_link';
import {
  circlesEnabled,
  clipsEnabled,
  driveEnabled,
  pagesEnabled,
} from 'flavours/glitch-classic/initial_state';
import { SharlayanCollapsiblePanel } from 'flavours/glitch-classic/sharlayan/registry/navigation/collapsible_panel';
import {
  adminTimelineOwnerViewer,
  softHideDeletion,
} from 'flavours/glitch-classic/sharlayan/roleplay';
import { useAppDispatch, useAppSelector } from 'flavours/glitch-classic/store';

const messages = defineMessages({
  extensions: {
    id: 'navigation_bar.extensions',
    defaultMessage: 'Extensions',
  },
  expand: {
    id: 'navigation_panel.expand_extensions',
    defaultMessage: 'Expand extensions menu',
  },
  collapse: {
    id: 'navigation_panel.collapse_extensions',
    defaultMessage: 'Collapse extensions menu',
  },
  clips: { id: 'navigation_bar.clips', defaultMessage: 'Clips' },
  scheduled: {
    id: 'navigation_bar.scheduled',
    defaultMessage: 'Scheduled posts',
  },
  drafts: { id: 'navigation_bar.drafts', defaultMessage: 'Drafts' },
  circles: { id: 'navigation_bar.circles', defaultMessage: 'Circles' },
  reactions: { id: 'navigation_bar.reactions', defaultMessage: 'Reactions' },
  pages: { id: 'navigation_bar.pages', defaultMessage: 'Pages' },
  drive: { id: 'navigation_bar.drive', defaultMessage: 'Drive' },
  rpHidden: { id: 'navigation_bar.rp_hidden', defaultMessage: 'Deleted posts' },
});

export const ExtensionsPanel: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const handleOpenDrive = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      dispatch(openModal({ modalType: 'DRIVE_MANAGER', modalProps: {} }));
    },
    [dispatch],
  );
  const useMyArchive = useAppSelector(
    (state) => state.local_settings.get('use_my_archive', false) as boolean,
  );

  const children = [];

  children.push(
    <ColumnLink
      key='drafts'
      transparent
      to='/drafts'
      icon='drafts'
      iconComponent={DraftIcon}
      text={intl.formatMessage(messages.drafts)}
    />,
  );

  if (softHideDeletion && adminTimelineOwnerViewer) {
    children.push(
      <ColumnLink
        key='rp-hidden'
        transparent
        to='/rp_hidden'
        icon='visibility-off'
        iconComponent={VisibilityOffIcon}
        text={intl.formatMessage(messages.rpHidden)}
      />,
    );
  }

  if (!useMyArchive) {
    children.push(
      <ColumnLink
        key='reactions'
        transparent
        to='/reactions'
        icon='mood'
        iconComponent={MoodIcon}
        text={intl.formatMessage(messages.reactions)}
      />,
    );
  }

  children.push(
    <ColumnLink
      key='scheduled'
      transparent
      to='/scheduled'
      icon='calendar'
      iconComponent={CalendarTodayIcon}
      text={intl.formatMessage(messages.scheduled)}
    />,
  );

  if (clipsEnabled && !useMyArchive) {
    children.push(
      <ColumnLink
        key='clips'
        transparent
        to='/clips'
        icon='note-stack-add'
        iconComponent={NoteStackAddIcon}
        text={intl.formatMessage(messages.clips)}
      />,
    );
  }

  if (pagesEnabled) {
    children.push(
      <ColumnLink
        key='pages'
        transparent
        to='/pages'
        icon='description'
        iconComponent={DescriptionIcon}
        text={intl.formatMessage(messages.pages)}
      />,
    );
  }

  if (driveEnabled) {
    children.push(
      <ColumnLink
        key='drive'
        transparent
        icon='cloud'
        iconComponent={CloudIcon}
        text={intl.formatMessage(messages.drive)}
        onClick={handleOpenDrive}
      />,
    );
  }

  if (circlesEnabled) {
    children.push(
      <ColumnLink
        key='circles'
        transparent
        to='/circles'
        icon='group'
        iconComponent={PeopleIcon}
        text={intl.formatMessage(messages.circles)}
      />,
    );
  }

  return (
    <SharlayanCollapsiblePanel
      icon='puzzle-piece'
      iconComponent={ExtensionIcon}
      title={intl.formatMessage(messages.extensions)}
      collapseTitle={intl.formatMessage(messages.collapse)}
      expandTitle={intl.formatMessage(messages.expand)}
    >
      {children}
    </SharlayanCollapsiblePanel>
  );
};
