import { useCallback, useEffect } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { PlusIcon } from '@phosphor-icons/react';
import { Helmet } from '@unhead/react/helmet';

import { Column } from '@/flavours/glitch/components/column';
import {
  ColumnHeader,
  ColumnHeaderButton,
  ColumnSettingsMenu,
} from '@/flavours/glitch/components/column_header';
import { MultiColumnMenuItems } from '@/flavours/glitch/components/column_header/multicolumn_settings';
import { MenuItemCheckbox } from '@/flavours/glitch/components/menu';
import { openNewComposer } from '@/flavours/glitch/reducers/slices/composer';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import {
  addColumn,
  removeColumn,
  moveColumn,
} from 'flavours/glitch/actions/columns';
import {
  mountConversations,
  unmountConversations,
  expandConversations,
} from 'flavours/glitch/actions/conversations';
import { changeSetting } from 'flavours/glitch/actions/settings';
import { connectDirectStream } from 'flavours/glitch/actions/streaming';
import { expandDirectTimeline } from 'flavours/glitch/actions/timelines';
import StatusListContainer from 'flavours/glitch/features/ui/containers/status_list_container';
import { roleplayMode } from 'flavours/glitch/sharlayan/roleplay';

import { ConversationsList } from './components/conversations_list';

const messages = defineMessages({
  title: { id: 'column.direct', defaultMessage: 'Private mentions' },
  title_redesign: { id: 'tab_bar.messages', defaultMessage: 'Messages' },
});

interface ColumnBase {
  columnId?: string;
  multiColumn?: boolean;
}

const DirectTimeline: React.FC<ColumnBase> = ({ columnId, multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const pinned = !!columnId;

  // glitch-soc additions
  const hasUnread = useAppSelector(
    (state) => (state.timelines.getIn(['direct', 'unread'], 0) as number) > 0,
  );
  const conversationsMode = useAppSelector(
    (state) => !!state.settings.getIn(['direct', 'conversations'], false),
  );
  const onChangeSetting = useCallback(
    ({ value, checked }: { value: string; checked: boolean }) => {
      dispatch(changeSetting(['direct', value], checked));
    },
    [dispatch],
  );
  const preserveGroup = useAppSelector(
    (state) =>
      !!state.settings.getIn(
        ['direct', 'preserve_group_on_new_mentions'],
        false,
      ),
  );

  const composeNewMessage = useCallback(() => {
    dispatch(openNewComposer({ type: 'message' }));
  }, [dispatch]);

  const handlePin = useCallback(() => {
    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('DIRECT', {}));
    }
  }, [dispatch, columnId]);

  const handleMove = useCallback(
    (dir: number) => {
      dispatch(moveColumn(columnId, dir));
    },
    [dispatch, columnId],
  );

  const handleLoadMoreTimeline = useCallback(
    (maxId: string) => {
      void dispatch(expandDirectTimeline({ maxId }));
    },
    [dispatch],
  );

  useEffect(() => {
    dispatch(mountConversations());

    if (conversationsMode) {
      dispatch(expandConversations({ replace: true }));
    } else {
      void dispatch(expandDirectTimeline());
    }

    const disconnect = dispatch(connectDirectStream());

    return () => {
      dispatch(unmountConversations());
      disconnect();
    };
  }, [dispatch, conversationsMode, preserveGroup]);

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.title)}
    >
      <ColumnHeader
        title={intl.formatMessage(messages.title_redesign)}
        withBackButton={multiColumn && !pinned && 'auto'}
        withUnreadMarker={hasUnread}
        extraButtons={
          <>
            <ColumnHeaderButton
              showTextOnDesktop
              variant='solid'
              color='accent'
              icon={PlusIcon}
              onClick={composeNewMessage}
            >
              <FormattedMessage id='messages.new' defaultMessage='New' />
            </ColumnHeaderButton>
            <ColumnSettingsMenu
              labelPrefix={intl.formatMessage(messages.title_redesign)}
            >
              <MenuItemCheckbox
                value='conversations'
                checked={conversationsMode}
                onChange={onChangeSetting}
                keepMenuOpenOnClick
              >
                <FormattedMessage
                  id='direct.group_by_accounts'
                  defaultMessage='Group by account'
                />
              </MenuItemCheckbox>
              <MenuItemCheckbox
                value='preserve_group_on_new_mentions'
                checked={preserveGroup}
                disabled={!conversationsMode}
                onChange={onChangeSetting}
                keepMenuOpenOnClick
              >
                <FormattedMessage
                  id='direct.preserve_group_on_new_mentions'
                  defaultMessage='Keep the existing group when mentioning new users'
                />
              </MenuItemCheckbox>

              {multiColumn && (
                <MultiColumnMenuItems
                  onPin={handlePin}
                  onMove={handleMove}
                  pinned={pinned}
                />
              )}
            </ColumnSettingsMenu>
          </>
        }
      />
      {conversationsMode ? (
        <ConversationsList
          trackScroll={!pinned}
          scrollKey={`direct_timeline-${columnId}`}
          emptyMessage={
            <FormattedMessage
              id='empty_column.messages'
              defaultMessage="You don't have any messages yet. When you send or receive one, it will show up here."
            />
          }
          bindToDocument={!multiColumn}
          prepend={
            <div className='follow_requests-unlocked_explanation'>
              <span>
                {roleplayMode && (
                  <>
                    <FormattedMessage
                      id='compose_form.rp_server_dm_warning'
                      defaultMessage='Server administrators can read direct messages for moderation.'
                    />{' '}
                  </>
                )}
                <FormattedMessage
                  id='compose_form.encryption_warning_messages'
                  defaultMessage='Messages are not end-to-end encrypted. Never share sensitive information, such as your phone number or banking details, on Mastodon.'
                />{' '}
                <a
                  href='https://docs.joinmastodon.org/user/posting/#private'
                  rel='noreferrer'
                  target='_blank'
                >
                  <FormattedMessage
                    id='compose_form.direct_message_warning_learn_more'
                    defaultMessage='Learn more'
                  />
                </a>
              </span>
            </div>
          }
          alwaysPrepend
        />
      ) : (
        <StatusListContainer
          trackScroll={!pinned}
          scrollKey={`direct_timeline-${columnId}`}
          timelineId='direct'
          bindToDocument={!multiColumn}
          onLoadMore={handleLoadMoreTimeline}
          prepend={
            <div className='follow_requests-unlocked_explanation'>
              <span>
                {roleplayMode && (
                  <>
                    <FormattedMessage
                      id='compose_form.rp_server_dm_warning'
                      defaultMessage='Server administrators can read direct messages for moderation.'
                    />{' '}
                  </>
                )}
                <FormattedMessage
                  id='compose_form.encryption_warning'
                  defaultMessage='Posts on Mastodon are not end-to-end encrypted. Do not share any dangerous information over Mastodon.'
                />{' '}
                <a href='/terms' target='_blank'>
                  <FormattedMessage
                    id='compose_form.direct_message_warning_learn_more'
                    defaultMessage='Learn more'
                  />
                </a>
              </span>
            </div>
          }
          alwaysPrepend
          emptyMessage={
            <FormattedMessage
              id='empty_column.direct'
              defaultMessage="You don't have any private mentions yet. When you send or receive one, it will show up here."
            />
          }
        />
      )}

      <Helmet>
        <title>{intl.formatMessage(messages.title_redesign)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default DirectTimeline;
