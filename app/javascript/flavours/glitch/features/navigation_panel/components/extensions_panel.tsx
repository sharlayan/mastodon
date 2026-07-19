import { useIntl, defineMessages } from 'react-intl';

import CalendarTodayIcon from '@/material-icons/400-24px/calendar_today.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import ExtensionIcon from '@/material-icons/400-24px/extension.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';
import {
  circlesEnabled,
  clipsEnabled,
  pagesEnabled,
} from 'flavours/glitch/initial_state';
import { SharlayanCollapsiblePanel } from 'flavours/glitch/sharlayan/registry/navigation/collapsible_panel';

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
  circles: { id: 'navigation_bar.circles', defaultMessage: 'Circles' },
  reactions: { id: 'navigation_bar.reactions', defaultMessage: 'Reactions' },
  pages: { id: 'navigation_bar.pages', defaultMessage: 'Pages' },
});

export const ExtensionsPanel: React.FC = () => {
  const intl = useIntl();

  const children = [];

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

  if (clipsEnabled) {
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
