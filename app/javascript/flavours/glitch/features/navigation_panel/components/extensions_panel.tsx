import { useIntl, defineMessages } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

import CalendarTodayIcon from '@/material-icons/400-24px/calendar_today.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import ExtensionIcon from '@/material-icons/400-24px/extension.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import DraftIcon from '@/material-icons/400-24px/save.svg?react';
import VisibilityOffIcon from '@/material-icons/400-24px/visibility_off.svg?react';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';
import {
  circlesEnabled,
  clipsEnabled,
  pagesEnabled,
} from 'flavours/glitch/initial_state';
import { SharlayanCollapsiblePanel } from 'flavours/glitch/sharlayan/registry/navigation/collapsible_panel';
import {
  adminTimelineOwnerViewer,
  softHideDeletion,
} from 'flavours/glitch/sharlayan/roleplay';
import { useAppSelector } from 'flavours/glitch/store';

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
  rpHidden: { id: 'navigation_bar.rp_hidden', defaultMessage: 'Deleted posts' },
});

export const ExtensionsPanel: React.FC = () => {
  const intl = useIntl();
  const useMyArchive = useAppSelector(
    (state) =>
      (state.local_settings as ImmutableMap<string, unknown>).get(
        'use_my_archive',
        false,
      ) as boolean,
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
