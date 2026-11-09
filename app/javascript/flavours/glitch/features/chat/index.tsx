import {
  Fragment,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from 'react';
import type {
  ChangeEvent,
  ClipboardEvent,
  KeyboardEvent,
  MouseEvent,
  SyntheticEvent,
} from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useHistory, useLocation, useParams } from 'react-router-dom';

import type { List as ImmutableList } from 'immutable';
import { fromJS, Map as ImmutableMap } from 'immutable';

import { Helmet } from '@unhead/react/helmet';
import Textarea from 'react-textarea-autosize';

import PhotoLibraryIcon from '@/material-icons/400-20px/photo_library.svg?react';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ChatIcon from '@/material-icons/400-24px/chat.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import ContentCopyIcon from '@/material-icons/400-24px/content_copy.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import GroupsIcon from '@/material-icons/400-24px/groups.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import ReplyIcon from '@/material-icons/400-24px/reply.svg?react';
import SearchIcon from '@/material-icons/400-24px/search.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import { showAlert } from 'flavours/glitch/actions/alerts';
import { openModal } from 'flavours/glitch/actions/modal';
import api from 'flavours/glitch/api';
import type { ApiCustomEmojiJSON } from 'flavours/glitch/api_types/custom_emoji';
import { compareId } from 'flavours/glitch/compare_id';
import { Badge } from 'flavours/glitch/components/badge';
import { Button } from 'flavours/glitch/components/button';
import { CircularProgress } from 'flavours/glitch/components/circular_progress';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import { textToEmojis } from 'flavours/glitch/components/emoji';
import {
  AnimateEmojiProvider,
  CustomEmojiProvider,
} from 'flavours/glitch/components/emoji/context';
import { SelectField } from 'flavours/glitch/components/form_fields';
import type { IconProp } from 'flavours/glitch/components/icon';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { IconWithBadge } from 'flavours/glitch/components/icon_with_badge';
import { LoadMore } from 'flavours/glitch/components/load_more';
import MediaGallery from 'flavours/glitch/components/media_gallery';
import { NotSignedInIndicator } from 'flavours/glitch/components/not_signed_in_indicator';
import { RelativeTimestamp } from 'flavours/glitch/components/relative_timestamp';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import SettingToggle from 'flavours/glitch/features/notifications/components/setting_toggle';
import { useIdentity } from 'flavours/glitch/identity_context';
import { me, roleplayMode } from 'flavours/glitch/initial_state';
import type { MenuItem } from 'flavours/glitch/models/dropdown_menu';
import { useAppDispatch } from 'flavours/glitch/store';

import type { ChatAccount } from './account';
import {
  ChatAccountRow,
  ChatAvatar,
  ChatDisplayName,
  ChatLinkedDisplayName,
} from './account';
import { leaveChatRoute, trackChatHistory } from './history_parent';
import { createRetries } from './retry';
import type { PageCheckpoint } from './retry';
import {
  CHAT_STREAM_POLLED,
  CHAT_STREAM_RECONNECTED,
  isChatStreamLive,
  subscribeChatStream,
} from './stream';
import {
  createChatScroll,
  useChatScroll,
  usesTouchKeyboard,
} from './use_chat_scroll';
import { useLongPressOpensToolbar } from './use_message_toolbar';

type RoomEnding = 'deleted' | 'removed';

interface ChatReaction {
  message_id: string;
  reaction: string;
  account: ChatAccount;
  url?: string;
  static_url?: string;
  domain?: string | null;
  is_sensitive?: boolean;
}

interface ChatMessage {
  id: string;
  conversation_id: string;
  content: string | null;
  created_at: string;
  edited_at: string | null;
  deleted_at: string | null;
  reply_to_id: string | null;
  account: ChatAccount;
  reactions: ChatReaction[];
  media_attachments: ChatMedia[];
  emojis?: ApiCustomEmojiJSON[];
  editable?: boolean;
  deletes_for_everyone?: boolean;
}

type MessageUpdate = (messages: ChatMessage[]) => ChatMessage[];
type SearchUpdate = (messages: ChatMessage[], query: string) => ChatMessage[];
type InvitationUpdate = (invitations: ChatInvitation[]) => ChatInvitation[];
type ConversationUpdate = (
  conversations: ChatConversation[],
) => ChatConversation[];

interface ChatMedia {
  id: string;
  url: string | null;
  preview_url: string | null;
  type: string;
  description: string | null;
}

interface ChatConversation {
  id: string;
  type: 'direct' | 'group';
  title: string | null;
  description: string | null;
  unread: boolean;
  muted: boolean;
  archived: boolean;
  current_role: 'owner' | 'member' | null;
  accounts: ChatAccount[];
  last_message: ChatMessage | null;
  emojis?: ApiCustomEmojiJSON[];
  updated_at?: string;
}

interface ChatInvitation {
  id: string;
  conversation: ChatConversation;
  inviter: ChatAccount;
  invitee?: ChatAccount;
}

interface ChatSettings {
  policy: 'everyone' | 'followers' | 'following' | 'mutual' | 'none';
  allow_group_invites: boolean;
  notifications: boolean;
  max_group_members: number;
  max_attachments: number;
  federation_enabled: boolean;
  delete_window_hours: number;
  soft_delete: boolean;
}

interface PickedEmoji {
  native?: string;
  colons?: string;
}

type ChatHomeTab = 'home' | 'invitations' | 'joiningRooms' | 'ownedRooms';

interface ReadMark {
  upTo: string;
  sending?: string;
  again: boolean;
}

const cooldownsByAccount = new Map<string, Map<string, number>>();
const chatCooldownsFor = (accountId: string) => {
  let cooldowns = cooldownsByAccount.get(accountId);
  if (!cooldowns) {
    cooldowns = new Map<string, number>();
    cooldownsByAccount.set(accountId, cooldowns);
  }
  return cooldowns;
};

const messages = defineMessages({
  heading: { id: 'chat.title', defaultMessage: 'Chat' },
  more: { id: 'status.more', defaultMessage: 'More' },
  newChat: { id: 'chat.new_chat', defaultMessage: 'New chat' },
  search: { id: 'chat.search', defaultMessage: 'Search messages' },
  newDirect: { id: 'chat.new_direct', defaultMessage: 'Start a direct chat' },
  open: { id: 'chat.open', defaultMessage: 'Open chat' },
  send: { id: 'chat.send', defaultMessage: 'Send' },
  save: { id: 'chat.save', defaultMessage: 'Save' },
  newMessages: {
    id: 'chat.new_messages',
    defaultMessage: 'New messages',
  },
  jumpToNewest: {
    id: 'chat.jump_to_newest',
    defaultMessage: 'Jump to newest message',
  },
  inviteSent: {
    id: 'chat.invite_sent',
    defaultMessage: 'Invitation sent to {account}.',
  },
  archiveConfirmTitle: {
    id: 'chat.archive_confirm_title',
    defaultMessage: 'Archive this group?',
  },
  archiveConfirm: {
    id: 'chat.archive_confirm',
    defaultMessage:
      'Everyone can still read it, but nobody can send messages or reactions. You can undo this at any time with Reopen in this menu.',
  },
  archive: { id: 'chat.archive', defaultMessage: 'Archive' },
  unarchive: { id: 'chat.unarchive', defaultMessage: 'Reopen' },
  invitationAccepted: {
    id: 'chat.invitation_accepted',
    defaultMessage: 'You joined {group}.',
  },
  invitationRejected: {
    id: 'chat.invitation_rejected',
    defaultMessage: 'You rejected the invitation to {group}.',
  },
  invitationCancelled: {
    id: 'chat.invitation_cancelled',
    defaultMessage: 'Cancelled the invitation to {account}.',
  },
  groupSaved: {
    id: 'chat.group_saved',
    defaultMessage: 'Group settings saved.',
  },
  placeholder: {
    id: 'chat.message_placeholder',
    defaultMessage: 'Write a message',
  },
  newGroup: { id: 'chat.new_group', defaultMessage: 'Create a group' },
  groupTitle: { id: 'chat.group_title', defaultMessage: 'Group name' },
  accountSearch: {
    id: 'chat.account_search',
    defaultMessage: 'Search for an account',
  },
  create: { id: 'chat.create', defaultMessage: 'Create' },
  settings: { id: 'chat.settings', defaultMessage: 'Chat settings' },
  attach: { id: 'chat.attach', defaultMessage: 'Attach media' },
  reply: { id: 'chat.reply', defaultMessage: 'Reply' },
  edit: { id: 'chat.edit', defaultMessage: 'Edit' },
  copy: { id: 'chat.copy', defaultMessage: 'Copy' },
  copied: {
    id: 'copy_icon_button.copied',
    defaultMessage: 'Copied to clipboard',
  },
  delete: { id: 'chat.delete', defaultMessage: 'Delete' },
  tabHome: { id: 'chat.home', defaultMessage: 'Home' },
  tabInvitations: { id: 'chat.invitations', defaultMessage: 'Invitations' },
  tabJoiningRooms: {
    id: 'chat.joining_rooms',
    defaultMessage: 'Joined groups',
  },
  tabOwnedRooms: { id: 'chat.owned_rooms', defaultMessage: 'Your groups' },
  unread: { id: 'chat.unread', defaultMessage: 'Unread messages' },
  removeAccount: {
    id: 'chat.remove_account',
    defaultMessage: 'Remove selected account',
  },
  cancel: { id: 'chat.cancel', defaultMessage: 'Cancel' },
  deleteGroupConfirm: {
    id: 'chat.delete_group_confirm',
    defaultMessage:
      'Delete this group for everyone in it? This cannot be undone.',
  },
});

const MAX_MESSAGE_LENGTH = 4096;

const isVisible = () => document.visibilityState !== 'hidden';
const isNotFound = (error: unknown) =>
  (error as { response?: { status?: number } }).response?.status === 404;
const isRefused = (error: unknown) =>
  (error as { response?: { status?: number } }).response?.status === 403;
const roomEndingOf = (error: unknown): RoomEnding | null => {
  const reason = (error as { response?: { data?: { reason?: unknown } } })
    .response?.data?.reason;
  return reason === 'deleted' || reason === 'removed' ? reason : null;
};

export const isRemoteAccount = (account: ChatAccount) =>
  account.acct.includes('@');

export const reactionFromEmoji = (emoji: PickedEmoji) =>
  emoji.native ?? emoji.colons ?? null;

const ChatEmojiPicker: React.FC<{
  messageId: string;
  onPick: (messageId: string, emoji: PickedEmoji) => void;
}> = ({ messageId, onPick }) => {
  const handlePick = useCallback(
    (emoji: PickedEmoji) => {
      onPick(messageId, emoji);
    },
    [messageId, onPick],
  );

  return <EmojiPickerDropdown onPickEmoji={handlePick} fitToViewport />;
};

const conversationName = (conversation: ChatConversation) => {
  if (conversation.title) return conversation.title;

  return conversation.accounts
    .filter((account) => account.id !== me)
    .map((account) => account.display_name || account.acct)
    .join(', ');
};

const EmojiText: React.FC<{
  text: string;
  emojis?: ApiCustomEmojiJSON[];
}> = ({ text, emojis }) => (
  <CustomEmojiProvider emojis={emojis}>
    <AnimateEmojiProvider as='span'>{textToEmojis(text)}</AnimateEmojiProvider>
  </CustomEmojiProvider>
);

const TitleName: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <span className='display-name'>
    <bdi>
      <strong className='display-name__html'>{children}</strong>
    </bdi>
  </span>
);

const ConversationName: React.FC<{ conversation: ChatConversation }> = ({
  conversation,
}) =>
  conversation.title ? (
    <EmojiText text={conversation.title} emojis={conversation.emojis} />
  ) : (
    <>
      {conversation.accounts
        .filter((account) => account.id !== me)
        .map((account, index) => (
          <Fragment key={account.id}>
            {index > 0 && ', '}
            <ChatDisplayName account={account} />
          </Fragment>
        ))}
    </>
  );

const directPartner = (conversation: ChatConversation) =>
  conversation.type === 'direct'
    ? conversation.accounts.find((account) => account.id !== me)
    : undefined;

const ConversationTitle: React.FC<{
  conversation: ChatConversation;
  linked?: boolean;
}> = ({ conversation, linked = false }) => {
  const partner = directPartner(conversation);
  if (conversation.title || !partner)
    return (
      <TitleName>
        <ConversationName conversation={conversation} />
      </TitleName>
    );

  return linked ? (
    <ChatLinkedDisplayName account={partner} />
  ) : (
    <ChatDisplayName account={partner} withHandle />
  );
};

const ConversationPicture: React.FC<{
  conversation: ChatConversation;
  size: number;
}> = ({ conversation, size }) => {
  const other = directPartner(conversation);

  return other ? (
    <ChatAvatar account={other} size={size} />
  ) : (
    <span
      className='chat-native__room-picture'
      style={{ width: `${size}px`, height: `${size}px` }}
    >
      <Icon id='groups' icon={GroupsIcon} />
    </span>
  );
};

const compareConversations = (
  first: ChatConversation,
  second: ChatConversation,
) => {
  const firstMessage = first.last_message?.id;
  const secondMessage = second.last_message?.id;
  if (firstMessage && secondMessage)
    return (
      compareId(secondMessage, firstMessage) || compareId(second.id, first.id)
    );
  if (firstMessage) return -1;
  if (secondMessage) return 1;
  return compareId(second.id, first.id);
};

interface ConversationCursor {
  id: string;
  messageId: string;
}

const conversationCursor = (
  item: ChatConversation,
  messageId?: string,
): ConversationCursor => ({
  id: item.id,
  messageId: messageId ?? item.last_message?.id ?? '0',
});

const cursorParams = (cursor: ConversationCursor) => ({
  max_id: cursor.id,
  max_id_message_id: cursor.messageId,
});

const conversationCursorHeader = (response: object): string | undefined => {
  const headers = Reflect.get(response, 'headers') as
    | Record<string, string>
    | undefined;
  return headers?.['x-chat-cursor-message-id'];
};

export const upsertConversation = (
  list: ChatConversation[],
  conversation: ChatConversation,
) => {
  if (list.some((item) => item.id === conversation.id))
    return list.map((item) =>
      item.id === conversation.id ? conversation : item,
    );
  const remaining = list.filter((item) => item.id !== conversation.id);
  const position = remaining.findIndex(
    (item) => compareConversations(conversation, item) < 0,
  );
  return position === -1
    ? [...remaining, conversation]
    : [
        ...remaining.slice(0, position),
        conversation,
        ...remaining.slice(position),
      ];
};

export const withConversationUpdate = (
  list: ChatConversation[],
  conversation: ChatConversation,
) => {
  const known = list.find((item) => item.id === conversation.id);
  if (!known) return upsertConversation(list, conversation);
  if (
    Date.parse(conversation.updated_at ?? '') <
    Date.parse(known.updated_at ?? '')
  )
    return list;
  const knownMessage = known.last_message;
  const message = conversation.last_message;
  if (!knownMessage || knownMessage.deleted_at)
    return upsertConversation(list, conversation);
  if (!message || compareId(knownMessage.id, message.id) > 0)
    return upsertConversation(list, {
      ...conversation,
      last_message: knownMessage,
      unread: known.unread,
    });
  if (knownMessage.id === message.id)
    return upsertConversation(list, {
      ...conversation,
      unread: known.unread && conversation.unread,
    });
  return upsertConversation(list, conversation);
};

const insertMessage = (list: ChatMessage[], message: ChatMessage) => {
  const position = list.findIndex(
    (item) => compareId(item.id, message.id) >= 0,
  );
  if (position === -1) return [...list, message];
  if (list[position]?.id === message.id) return list;
  return [...list.slice(0, position), message, ...list.slice(position)];
};

export const withNewMessage = (
  list: ChatConversation[],
  message: ChatMessage,
  unread: boolean,
) => {
  const conversation = list.find((item) => item.id === message.conversation_id);
  if (
    !conversation ||
    (conversation.last_message &&
      compareId(conversation.last_message.id, message.id) >= 0)
  )
    return list;
  return [
    { ...conversation, last_message: message, unread },
    ...list.filter((item) => item !== conversation),
  ];
};

type AccountSearchStatus = 'idle' | 'searching' | 'empty' | 'failed';

const AccountSearchNotice: React.FC<{ status: AccountSearchStatus }> = ({
  status,
}) => {
  if (status === 'searching')
    return (
      <div className='chat-native__searching' role='status'>
        <CircularProgress size={16} strokeWidth={2} />
        <FormattedMessage
          id='chat.account_search_searching'
          defaultMessage='Searching…'
        />
      </div>
    );
  if (status === 'empty')
    return (
      <div className='chat-native__empty'>
        <FormattedMessage
          id='chat.account_search_no_results'
          defaultMessage='No accounts found.'
        />
      </div>
    );
  if (status === 'failed')
    return (
      <div className='chat-native__empty'>
        <FormattedMessage
          id='chat.account_search_failed'
          defaultMessage='Could not search for accounts. Try again.'
        />
      </div>
    );
  return null;
};

const SENT_INVITATIONS_PAGE = 40;
const fetchSentInvitations = async (
  conversationId: string,
  nextPage: PageCheckpoint,
  maxId?: string,
): Promise<ChatInvitation[] | undefined> => {
  const { data } = await api().get<ChatInvitation[]>(
    '/api/v1/chat/invitations',
    {
      params: {
        direction: 'sent',
        conversation_id: conversationId,
        ...(maxId ? { max_id: maxId } : {}),
      },
    },
  );
  const last = data.at(-1);
  if (!last || data.length !== SENT_INVITATIONS_PAGE) return data;
  if (!(await nextPage())) return undefined;
  const rest = await fetchSentInvitations(conversationId, nextPage, last.id);
  return rest ? [...data, ...rest] : undefined;
};

const ChatMessageMedia: React.FC<{
  attachments: ChatMedia[];
  onOpenMedia: (media: ImmutableList<unknown>, index: number) => void;
}> = ({ attachments, onOpenMedia }) => {
  const gallery = useMemo(
    () =>
      fromJS(
        attachments.filter((item) => item.url && item.type !== 'audio'),
      ) as ImmutableList<unknown>,
    [attachments],
  );

  return (
    <>
      {gallery.size > 0 && (
        <div className='chat-native__gallery'>
          <MediaGallery
            media={gallery}
            standalone={gallery.size === 1}
            onOpenMedia={onOpenMedia}
          />
        </div>
      )}
      {attachments.map((item) =>
        item.url && item.type === 'audio' ? (
          <div key={item.id} className='chat-native__attachment'>
            <audio controls src={item.url} />
          </div>
        ) : item.url ? null : (
          <div key={item.id} className='chat-native__attachment'>
            <span>{item.description ?? item.type}</span>
          </div>
        ),
      )}
    </>
  );
};

const waitForMedia = async (
  media: ChatMedia,
  signal: AbortSignal,
): Promise<ChatMedia> => {
  if (media.url) return media;
  const cancelled = () => signal.aborted;

  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (cancelled()) throw new Error('Upload no longer needed');
    const response = await api().get<ChatMedia>(`/api/v1/media/${media.id}`);
    if (cancelled()) throw new Error('Upload no longer needed');
    if (response.data.url) return response.data;
    await new Promise((resolve) => {
      const done = () => {
        window.clearTimeout(timer);
        signal.removeEventListener('abort', done);
        resolve(undefined);
      };
      const timer = window.setTimeout(done, 1000);
      signal.addEventListener('abort', done, { once: true });
      if (signal.aborted) done();
    });
  }

  throw new Error('Media processing timed out');
};

const InvitationRow: React.FC<{
  invitation: ChatInvitation;
  onAnswer: (invitation: ChatInvitation, action: 'accept' | 'reject') => void;
}> = ({ invitation, onAnswer }) => {
  const handleAccept = useCallback(() => {
    onAnswer(invitation, 'accept');
  }, [invitation, onAnswer]);
  const handleReject = useCallback(() => {
    onAnswer(invitation, 'reject');
  }, [invitation, onAnswer]);

  return (
    <ChatAccountRow
      className='chat-native__invitation'
      account={invitation.inviter}
      name={
        <TitleName>
          <ConversationName conversation={invitation.conversation} />
        </TitleName>
      }
      details={
        <FormattedMessage
          id='chat.invited_by'
          defaultMessage='Invited by {name}'
          values={{
            name: <ChatDisplayName account={invitation.inviter} />,
          }}
        />
      }
    >
      <Button compact onClick={handleAccept}>
        <FormattedMessage id='chat.accept' defaultMessage='Accept' />
      </Button>
      <Button compact secondary onClick={handleReject}>
        <FormattedMessage id='chat.reject' defaultMessage='Reject' />
      </Button>
    </ChatAccountRow>
  );
};

const PendingInvitationRow: React.FC<{
  invitation: ChatInvitation;
  invitee: ChatAccount;
  onCancel: (invitation: ChatInvitation) => void;
}> = ({ invitation, invitee, onCancel }) => {
  const handleCancel = useCallback(() => {
    onCancel(invitation);
  }, [invitation, onCancel]);

  return (
    <ChatAccountRow
      className='chat-native__member'
      account={invitee}
      target={{ kind: 'profile' }}
    >
      <Badge
        variant='warning'
        label={
          <FormattedMessage
            id='chat.invitation_pending'
            defaultMessage='Invited'
          />
        }
      />
      <Button compact secondary onClick={handleCancel}>
        <FormattedMessage
          id='chat.cancel_invitation'
          defaultMessage='Cancel invitation'
        />
      </Button>
    </ChatAccountRow>
  );
};

const SelectedAccountCard: React.FC<{
  account: ChatAccount;
  onRemove: (accountId: string) => void;
}> = ({ account, onRemove }) => {
  const intl = useIntl();
  const handleRemove = useCallback(() => {
    onRemove(account.id);
  }, [account.id, onRemove]);

  return (
    <ChatAccountRow className='chat-native__account-card' account={account}>
      <IconButton
        icon='times'
        iconComponent={CloseIcon}
        title={intl.formatMessage(messages.removeAccount)}
        onClick={handleRemove}
      />
    </ChatAccountRow>
  );
};

interface ReactionGroup {
  reaction: string;
  url?: string;
  staticUrl?: string;
  sensitive: boolean;
  accounts: ChatAccount[];
  mine: boolean;
}

const groupReactions = (reactions: ChatReaction[]) => {
  const groups = new Map<string, ReactionGroup>();
  reactions.forEach((item) => {
    const group = groups.get(item.reaction) ?? {
      reaction: item.reaction,
      url: item.url,
      staticUrl: item.static_url,
      sensitive: Boolean(item.is_sensitive),
      accounts: [],
      mine: false,
    };
    group.url ??= item.url;
    group.staticUrl ??= item.static_url;
    group.accounts.push(item.account);
    if (item.account.id === me) group.mine = true;
    groups.set(item.reaction, group);
  });
  return Array.from(groups.values());
};

const MessageReactions: React.FC<{
  messageId: string;
  reactions: ChatReaction[];
  canReact: boolean;
  onRemove: (event: MouseEvent<HTMLButtonElement>) => void;
  onAdd: (messageId: string, emoji: PickedEmoji) => void;
}> = ({ messageId, reactions, canReact, onRemove, onAdd }) => {
  const groups = useMemo(() => groupReactions(reactions), [reactions]);
  const handleAdd = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const reaction = event.currentTarget.dataset.reaction;
      if (reaction) onAdd(messageId, { native: reaction });
    },
    [messageId, onAdd],
  );

  return (
    <AnimateEmojiProvider className='reactions-bar chat-native__reactions'>
      {groups.map((group) => {
        const accounts = group.accounts
          .map((account) => `@${account.acct}`)
          .join(', ');
        const label = `${group.reaction} ${accounts}`;
        const contents = (
          <>
            <span className='reactions-bar__item__emoji'>
              {group.url ? (
                <img
                  draggable='false'
                  className={classNames('emojione custom-emoji', {
                    'sensitive-custom-emoji': group.sensitive,
                  })}
                  src={group.staticUrl ?? group.url}
                  alt={group.reaction}
                />
              ) : (
                textToEmojis(group.reaction)
              )}
            </span>
            <span className='reactions-bar__item__count'>
              {group.accounts.length}
            </span>
          </>
        );

        if (group.mine)
          return (
            <button
              key={group.reaction}
              type='button'
              className='reactions-bar__item active'
              aria-pressed
              aria-label={label}
              title={accounts}
              data-message-id={messageId}
              data-reaction={group.reaction}
              data-account-id={me}
              onClick={onRemove}
            >
              {contents}
            </button>
          );

        if (canReact)
          return (
            <button
              key={group.reaction}
              type='button'
              className='reactions-bar__item'
              aria-pressed={false}
              aria-label={label}
              title={accounts}
              data-reaction={group.reaction}
              onClick={handleAdd}
            >
              {contents}
            </button>
          );

        return (
          <span
            key={group.reaction}
            className='reactions-bar__item chat-native__reaction-static'
            role='img'
            aria-label={label}
            title={accounts}
          >
            {contents}
          </span>
        );
      })}
    </AnimateEmojiProvider>
  );
};

type MessageAction = 'reply' | 'edit' | 'copy' | 'delete';

const hasText = (message: ChatMessage) => Boolean(message.content?.trim());

const writeToClipboard = async (text: string) => {
  await navigator.clipboard.writeText(text);
};

const scrollsConversation = (event: KeyboardEvent<HTMLTextAreaElement>) => {
  if (
    !navigator.userAgent.includes('Macintosh') ||
    event.shiftKey ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey
  )
    return false;
  const box = event.currentTarget;
  if (event.key === 'Home') return box.scrollTop <= 0;
  if (event.key === 'End')
    return box.scrollTop + box.clientHeight >= box.scrollHeight - 1;
  return false;
};

const ReplyQuote: React.FC<{
  messageId: string;
  target?: ChatMessage;
  onClick: (event: MouseEvent<HTMLButtonElement>) => void;
}> = ({ messageId, target, onClick }) => (
  <button
    type='button'
    className='chat-native__reply-quote'
    data-message-id={messageId}
    onClick={onClick}
  >
    {target ? (
      <>
        <strong>
          <ChatDisplayName account={target.account} />
        </strong>
        <span>
          {target.deleted_at ? (
            <FormattedMessage
              id='chat.message_deleted'
              defaultMessage='This message was deleted.'
            />
          ) : (
            <EmojiText text={target.content ?? ''} emojis={target.emojis} />
          )}
        </span>
      </>
    ) : (
      <FormattedMessage
        id='chat.replying'
        defaultMessage='Replying to message'
      />
    )}
  </button>
);

const MessageActionButton: React.FC<{
  messageId: string;
  action: MessageAction;
  title: string;
  icon: IconProp;
  onAction: (id: string, action: MessageAction) => void;
}> = ({ messageId, action, title, icon, onAction }) => {
  const handleClick = useCallback(() => {
    onAction(messageId, action);
  }, [action, messageId, onAction]);

  return (
    <IconButton
      title={title}
      icon={action}
      iconComponent={icon}
      onClick={handleClick}
    />
  );
};

const SEARCH_DEBOUNCE_MS = 250;
const RUN_GAP_MS = 17 * 60 * 1000;

const startsDay = (list: ChatMessage[], index: number) => {
  const current = list[index];
  const previous = list[index - 1];
  if (!current || !previous) return true;
  return (
    new Date(previous.created_at).toDateString() !==
    new Date(current.created_at).toDateString()
  );
};

const startsRun = (list: ChatMessage[], index: number) => {
  const current = list[index];
  const previous = list[index - 1];
  if (!current || !previous) return true;
  return (
    previous.account.id !== current.account.id ||
    Date.parse(current.created_at) - Date.parse(previous.created_at) >
      RUN_GAP_MS ||
    startsDay(list, index)
  );
};

const endsRun = (list: ChatMessage[], index: number) =>
  index === list.length - 1 || startsRun(list, index + 1);

const MESSAGE_PAGE_SIZE = 40;
const MESSAGE_RESYNC_PAGES = 25;

const createStore = <T,>(initial: T) => {
  let current = initial;
  const listeners = new Set<() => void>();

  return {
    get: () => current,
    set: (next: T) => {
      if (next === current) return;
      current = next;
      listeners.forEach((listener) => {
        listener();
      });
    },
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
};

const createJumpButtonState = () => {
  const store = createStore({ away: false, unseen: false });

  return {
    ...store,
    update: (next: { away?: boolean; unseen?: boolean }) => {
      const current = store.get();
      const away = next.away ?? current.away;
      const unseen = next.unseen ?? current.unseen;
      if (away !== current.away || unseen !== current.unseen)
        store.set({ away, unseen });
    },
  };
};

const JumpToNewestButton: React.FC<{
  state: ReturnType<typeof createJumpButtonState>;
  onClick: () => void;
}> = ({ state, onClick }) => {
  const intl = useIntl();
  const { away, unseen } = useSyncExternalStore(state.subscribe, state.get);

  if (!away) return null;

  return (
    <button
      type='button'
      className={classNames('chat-native__jump', {
        'chat-native__jump--unseen': unseen,
      })}
      aria-label={intl.formatMessage(
        unseen ? messages.newMessages : messages.jumpToNewest,
      )}
      title={intl.formatMessage(messages.jumpToNewest)}
      onClick={onClick}
    >
      <Icon id='arrow-down' icon={ArrowDownwardIcon} />
      {unseen && <span>{intl.formatMessage(messages.newMessages)}</span>}
    </button>
  );
};

type ComposerText = ReturnType<typeof createStore<string>>;

const isTooLong = (text: string) =>
  Array.from(text.trim()).length > MAX_MESSAGE_LENGTH;

const pastePlainText = (event: ClipboardEvent<HTMLDivElement>) => {
  const target = event.target;
  if (
    !(
      target instanceof HTMLTextAreaElement ||
      target instanceof HTMLInputElement
    )
  )
    return;
  if (
    target instanceof HTMLInputElement &&
    !['text', 'search', 'url', 'tel', 'password'].includes(target.type)
  )
    return;
  if (target.disabled || target.readOnly) return;
  const clipboard = event.clipboardData;
  if (
    clipboard.files.length ||
    Array.from(clipboard.items).some((item) => item.kind === 'file')
  )
    return;
  if (
    !clipboard.types.includes('text/plain') ||
    !clipboard.types.includes('text/uri-list')
  )
    return;
  const plain = clipboard.getData('text/plain');
  const uri = clipboard.getData('text/uri-list');
  if (!plain || !uri || plain === uri) return;
  try {
    const decoded = decodeURIComponent(uri);
    const scheme = /^[a-z][a-z\d+.-]*:/i.exec(plain)?.[0];
    if (!scheme) return;
    if (
      decoded.slice(0, scheme.length).toLowerCase() !== scheme.toLowerCase() ||
      decoded.slice(scheme.length) !== plain.slice(scheme.length)
    )
      return;
  } catch {
    return;
  }
  event.preventDefault();
  // eslint-disable-next-line @typescript-eslint/no-deprecated, @typescript-eslint/unbound-method
  const insertText = document.execCommand;
  if (
    typeof insertText === 'function' &&
    insertText.call(document, 'insertText', false, plain)
  )
    return;
  target.setRangeText(
    plain,
    target.selectionStart ?? 0,
    target.selectionEnd ?? 0,
    'end',
  );
  target.dispatchEvent(
    new InputEvent('input', {
      bubbles: true,
      inputType: 'insertFromPaste',
      data: plain,
    }),
  );
};

const foldSearch = (value: string) =>
  Array.from(value, (character) =>
    character === 'İ' ? 'i' : character.toLowerCase(),
  ).join('');

const ComposerBox: React.FC<{
  text: ComposerText;
  onKeyDown: (event: KeyboardEvent<HTMLTextAreaElement>) => void;
  onPaste: (event: ClipboardEvent<HTMLTextAreaElement>) => void;
  placeholder: string;
  disabled: boolean;
}> = ({ text, onKeyDown, onPaste, placeholder, disabled }) => {
  const value = useSyncExternalStore(text.subscribe, text.get);
  const handleChange = useCallback(
    (event: ChangeEvent<HTMLTextAreaElement>) => {
      text.set(event.target.value);
    },
    [text],
  );

  return (
    <Textarea
      name='search'
      minRows={1}
      maxRows={6}
      value={value}
      onChange={handleChange}
      onKeyDown={onKeyDown}
      onPaste={onPaste}
      placeholder={placeholder}
      disabled={disabled}
    />
  );
};

const ComposerTooLongNotice: React.FC<{ text: ComposerText }> = ({ text }) => {
  const count = useSyncExternalStore(text.subscribe, () =>
    isTooLong(text.get()) ? Array.from(text.get().trim()).length : 0,
  );

  if (!count) return null;

  return (
    <div className='chat-native__error'>
      <FormattedMessage
        id='chat.message_too_long'
        defaultMessage='This message is too long ({count}/{max} characters).'
        values={{ count, max: MAX_MESSAGE_LENGTH }}
      />
    </div>
  );
};

const ComposerSendButton: React.FC<{
  text: ComposerText;
  hasOtherContent: boolean;
  disabled: boolean;
  label: string;
}> = ({ text, hasOtherContent, disabled, label }) => {
  const sendable = useSyncExternalStore(
    text.subscribe,
    () =>
      !isTooLong(text.get()) && (hasOtherContent || Boolean(text.get().trim())),
  );

  return (
    <Button type='submit' disabled={disabled || !sendable}>
      {label}
    </Button>
  );
};

export const Chat: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const { conversationId } = useParams<{ conversationId?: string }>();
  const history = useHistory();

  useEffect(() => {
    trackChatHistory(history);
  }, [history]);

  return (
    <ChatSession key={conversationId ?? 'home'} multiColumn={multiColumn} />
  );
};

const ChatSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const history = useHistory();
  const location = useLocation<
    | {
        chatMessageId?: string;
        chatCreatedConversation?: ChatConversation;
      }
    | undefined
  >();
  const [scroll] = useState(() =>
    createChatScroll(location.state?.chatMessageId ?? null),
  );
  const jumpTargetId = useSyncExternalStore(scroll.subscribe, scroll.targetId);
  const dispatch = useAppDispatch();
  const { conversationId: routeId, view: roomView } = useParams<{
    conversationId?: string;
    view?: string;
  }>();
  const creating = routeId === 'new';
  const conversationId = creating ? undefined : routeId;
  const { signedIn } = useIdentity();
  const [conversations, setConversations] = useState<ChatConversation[]>(() => {
    const created = location.state?.chatCreatedConversation;
    return created && created.id === conversationId ? [created] : [];
  });
  const [nextConversationId, setNextConversationId] =
    useState<ConversationCursor | null>(null);
  const nextConversationIdRef = useRef<ConversationCursor | null>(null);
  const updateNextConversationId = useCallback(
    (id: ConversationCursor | null) => {
      nextConversationIdRef.current = id;
      setNextConversationId(id);
    },
    [],
  );
  const [olderMessageId, setOlderMessageId] = useState<string | null>(null);
  const olderMessageIdRef = useRef<string | null>(null);
  const updateOlderMessageId = useCallback((id: string | null) => {
    olderMessageIdRef.current = id;
    setOlderMessageId(id);
  }, []);
  const [loadingMore, setLoadingMore] = useState(false);
  const [activeTab, setActiveTab] = useState<ChatHomeTab>('home');
  const [messagesList, setMessagesList] = useState<ChatMessage[]>([]);
  const [messagesLoaded, setMessagesLoaded] = useState(false);
  const [directAccountQuery, setDirectAccountQuery] = useState('');
  const [directAccount, setDirectAccount] = useState<ChatAccount | null>(null);
  const [accountResults, setAccountResults] = useState<ChatAccount[]>([]);
  const [accountSearchStatus, setAccountSearchStatus] =
    useState<AccountSearchStatus>('idle');
  const [jumpButton] = useState(createJumpButtonState);
  const [groupTitle, setGroupTitle] = useState('');
  const [groupAccountQuery, setGroupAccountQuery] = useState('');
  const [groupAccountResults, setGroupAccountResults] = useState<ChatAccount[]>(
    [],
  );
  const [groupAccounts, setGroupAccounts] = useState<ChatAccount[]>([]);
  const [composerText] = useState(() => createStore(''));
  const [media, setMedia] = useState<ChatMedia[]>([]);
  const [replyToId, setReplyToId] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [invitations, setInvitations] = useState<ChatInvitation[]>([]);
  const [chatSettings, setChatSettings] = useState<ChatSettings | null>(null);
  const [inviteAccountQuery, setInviteAccountQuery] = useState('');
  const [inviteAccountResults, setInviteAccountResults] = useState<
    ChatAccount[]
  >([]);
  const [inviteAccount, setInviteAccount] = useState<ChatAccount | null>(null);
  const [removingMemberId, setRemovingMemberId] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [sentInvitations, setSentInvitations] = useState<ChatInvitation[]>([]);
  const [sentInvitationsVersion, setSentInvitationsVersion] = useState(0);
  const [groupEdit, setGroupEdit] = useState<{
    conversationId: string;
    title: string;
    description: string;
  } | null>(null);
  const [newChatMode, setNewChatMode] = useState<'direct' | 'group'>('direct');
  const [searchOpen, setSearchOpen] = useState(false);
  const longPress = useLongPressOpensToolbar();
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<ChatMessage[]>([]);
  const [searchedQuery, setSearchedQuery] = useState<string | null>(null);
  const [conversationMissing, setConversationMissing] = useState(false);
  const [roomEnding, setRoomEnding] = useState<RoomEnding | null>(null);
  const [conversationsLoaded, setConversationsLoaded] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sendError, setSendError] = useState<string | null>(null);
  const [readingError, setReadingError] = useState(false);
  const isMounted = useRef(true);
  const stillMounted = useCallback(() => isMounted.current, []);
  const uploadAbort = useRef<AbortController | null>(null);
  const textBeforeEdit = useRef<string | null>(null);
  const deletedMessages = useRef(new Map<string, string>());
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesListRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const composerRef = useRef<HTMLFormElement>(null);
  const searchRequestRef = useRef(0);
  const searchTimeoutRef = useRef<number | null>(null);
  const messageSearchTimeoutRef = useRef<number | undefined>(undefined);
  const latestMessageSearch = useRef(0);

  const applyTombstone = useCallback((message: ChatMessage): ChatMessage => {
    if (message.deleted_at && !deletedMessages.current.has(message.id)) {
      deletedMessages.current.set(message.id, message.deleted_at);
    }
    const deletedAt = deletedMessages.current.get(message.id);
    if (!deletedAt) return message;

    return {
      ...message,
      content: null,
      deleted_at: deletedAt,
      media_attachments: [],
      reactions: [],
    };
  }, []);

  const knownConversationIds = useRef<Set<string> | null>(null);
  const conversationVersions = useRef(new Map<string, number>());
  const endedConversations = useRef(new Set<string>());
  useEffect(() => {
    if (conversationsLoaded)
      knownConversationIds.current = new Set(
        conversations.map((item) => item.id),
      );
  }, [conversations, conversationsLoaded]);

  const pendingMessageUpdates = useRef(new Set<MessageUpdate[]>());
  const latestMessageRequest = useRef(0);
  const appliedMessageGeneration = useRef(0);
  const shownMessagesRef = useRef<ChatMessage[]>([]);
  useEffect(() => {
    shownMessagesRef.current = messagesList;
  }, [messagesList]);
  const conversationPages = useRef(1);
  const latestConversationRequest = useRef(0);
  const appliedConversationGeneration = useRef(0);
  const updateMessages = useCallback((update: MessageUpdate) => {
    pendingMessageUpdates.current.forEach((updates) => updates.push(update));
    setMessagesList(update);
  }, []);
  const pendingSearchUpdates = useRef(
    new Set<{ query: string; updates: MessageUpdate[] }>(),
  );
  const displayedSearchQuery = useRef('');
  const updateSearchResults = useCallback((update: SearchUpdate) => {
    pendingSearchUpdates.current.forEach(({ query, updates }) =>
      updates.push((items) => update(items, query)),
    );
    const query = displayedSearchQuery.current;
    setSearchResults((items) => update(items, query));
  }, []);
  const pendingConversationUpdates = useRef(new Set<ConversationUpdate[]>());
  const pendingConversationMessages = useRef(new Set<Set<string>>());
  const updateConversations = useCallback((update: ConversationUpdate) => {
    pendingConversationUpdates.current.forEach((updates) =>
      updates.push(update),
    );
    setConversations(update);
  }, []);
  const pendingInvitationUpdates = useRef(new Set<InvitationUpdate[]>());
  const latestInvitationRequest = useRef(0);
  const updateInvitations = useCallback((update: InvitationUpdate) => {
    pendingInvitationUpdates.current.forEach((updates) => updates.push(update));
    setInvitations(update);
  }, []);
  const pendingSentInvitationUpdates = useRef(new Set<InvitationUpdate[]>());
  const updateSentInvitations = useCallback((update: InvitationUpdate) => {
    pendingSentInvitationUpdates.current.forEach((updates) =>
      updates.push(update),
    );
    setSentInvitations(update);
  }, []);

  const openingReads = useRef(new Set<Promise<unknown>>());
  const whileOpening = useCallback(<T,>(read: Promise<T>) => {
    openingReads.current.add(read);
    void read
      .catch(() => undefined)
      .finally(() => {
        openingReads.current.delete(read);
      });
    return read;
  }, []);

  const [retries] = useState(() =>
    createRetries(undefined, chatCooldownsFor(me ?? '')),
  );
  useEffect(() => {
    const followVisibility = () => {
      if (isVisible()) retries.show();
      else retries.hide();
    };
    document.addEventListener('visibilitychange', followVisibility);
    return () => {
      document.removeEventListener('visibilitychange', followVisibility);
      retries.stop();
    };
  }, [retries]);

  const failedReads = useRef(new Set<string>());
  const olderPageRateLimited = useRef(false);
  const readFailed = useCallback((read: string) => {
    failedReads.current.add(read);
    setReadingError(true);
  }, []);
  const readRecovered = useCallback((read: string) => {
    failedReads.current.delete(read);
    if (failedReads.current.size === 0) setReadingError(false);
  }, []);

  const readMarks = useRef(new Map<string, ReadMark>());
  const sendReadMark = useCallback(
    async (id: string) => {
      const mark = readMarks.current.get(id);
      if (!mark) return;
      const marked = mark.upTo;
      mark.sending = marked;
      mark.again = false;
      try {
        await api().post(`/api/v1/chat/conversations/${id}/read`, {
          message_id: marked,
        });
      } finally {
        mark.sending = undefined;
      }
      const current = readMarks.current.get(id);
      if (current === mark && !current.again) readMarks.current.delete(id);
      updateConversations((current) =>
        current.map((item) =>
          item.id === id &&
          (!item.last_message || compareId(item.last_message.id, marked) <= 0)
            ? { ...item, unread: false }
            : item,
        ),
      );
    },
    [updateConversations],
  );
  const markRead = useCallback(
    (id: string, asked?: string) => {
      if (!asked) return;
      const mark = readMarks.current.get(id);
      if (!mark) {
        readMarks.current.set(id, { upTo: asked, again: false });
        void retries
          .keepTrying(`read:${id}`, () => sendReadMark(id), {
            gaveUp: () => {
              readMarks.current.delete(id);
            },
          })
          .catch(() => undefined);
        return;
      }
      if (compareId(asked, mark.upTo) > 0) mark.upTo = asked;
      if (mark.sending === undefined) return;
      const covered = compareId(asked, mark.sending) <= 0;
      if (!covered) {
        mark.again = true;
        void retries
          .keepTrying(`read:${id}`, () => sendReadMark(id))
          .catch(() => undefined);
      }
    },
    [retries, sendReadMark],
  );
  useEffect(() => {
    if (!conversationId) return undefined;
    const marks = readMarks.current;
    return () => {
      retries.cancel(`read:${conversationId}`);
      marks.delete(conversationId);
    };
  }, [conversationId, retries]);

  const continuousUpTo = useRef<string | undefined>(undefined);
  const initialMessageSnapshotWasEmpty = useRef(false);
  const firstMessagesRead = useRef(false);
  const readSinceStreamWentLive = useRef(false);
  const advanceContinuousUpTo = useCallback((id?: string) => {
    if (
      id &&
      (!continuousUpTo.current || compareId(id, continuousUpTo.current) > 0)
    )
      continuousUpTo.current = id;
  }, []);

  const unreadWhileAway = useRef(false);
  const pendingVisibleRead = useRef<{
    room: string;
    message: string;
    notify: boolean;
  } | null>(null);
  const [visibleReadRevision, setVisibleReadRevision] = useState(0);
  const queueVisibleRead = useCallback(
    (room: string, message?: string, notify = false) => {
      if (!message) return;
      pendingVisibleRead.current = { room, message, notify };
      setVisibleReadRevision((revision) => revision + 1);
    },
    [],
  );
  const attemptVisibleRead = useCallback(() => {
    const pending = pendingVisibleRead.current;
    if (!pending || pending.room !== conversationId || !scroll.following())
      return;
    if (!scroll.messageVisible(pending.message)) return;
    pendingVisibleRead.current = null;
    unreadWhileAway.current = false;
    jumpButton.update({ unseen: false });
    markRead(pending.room, pending.message);
  }, [conversationId, jumpButton, markRead, scroll]);

  const conversation = useMemo(
    () => conversations.find((item) => item.id === conversationId),
    [conversationId, conversations],
  );
  const messagesById = useMemo(
    () => new Map(messagesList.map((item) => [item.id, item])),
    [messagesList],
  );
  const replyTarget = useMemo(
    () => messagesList.find((item) => item.id === replyToId),
    [messagesList, replyToId],
  );
  const visibleConversations = useMemo(() => {
    if (activeTab === 'joiningRooms') {
      return conversations.filter(
        (item) => item.type === 'group' && item.current_role === 'member',
      );
    }
    if (activeTab === 'ownedRooms') {
      return conversations.filter(
        (item) => item.type === 'group' && item.current_role === 'owner',
      );
    }
    return conversations;
  }, [activeTab, conversations]);

  useEffect(
    () => () => {
      if (searchTimeoutRef.current !== null)
        window.clearTimeout(searchTimeoutRef.current);
    },
    [],
  );

  const searchAccounts = useCallback(
    (query: string, setter: (accounts: ChatAccount[]) => void) => {
      const normalized = query.trim();
      const requestId = searchRequestRef.current + 1;
      searchRequestRef.current = requestId;
      setAccountSearchStatus(normalized.length < 2 ? 'idle' : 'searching');

      if (searchTimeoutRef.current !== null) {
        window.clearTimeout(searchTimeoutRef.current);
      }

      if (normalized.length < 2) {
        setter([]);
        return;
      }

      searchTimeoutRef.current = window.setTimeout(() => {
        void api()
          .get<{ accounts: ChatAccount[] }>('/api/v2/search', {
            params: {
              q: normalized,
              type: 'accounts',
              resolve: true,
              limit: 8,
            },
          })
          .then((response) => {
            if (requestId !== searchRequestRef.current) return;
            const accounts = response.data.accounts.filter(
              (account) => account.id !== me,
            );
            setter(accounts);
            setAccountSearchStatus(accounts.length === 0 ? 'empty' : 'idle');
          })
          .catch(() => {
            if (requestId !== searchRequestRef.current) return;
            setter([]);
            setAccountSearchStatus('failed');
          });
      }, SEARCH_DEBOUNCE_MS);
    },
    [],
  );

  useEffect(() => {
    const controller = new AbortController();
    uploadAbort.current = controller;
    isMounted.current = true;
    return () => {
      isMounted.current = false;
      controller.abort();
    };
  }, []);

  const navigateIfActive = useCallback(
    (path: string, created?: ChatConversation) => {
      if (!isMounted.current) return;
      if (created) history.replace(path, { chatCreatedConversation: created });
      else leaveChatRoute(history, path);
    },
    [history],
  );

  useEffect(() => {
    if (!location.state?.chatCreatedConversation) return;
    const state = { ...location.state };
    delete state.chatCreatedConversation;
    history.replace({ ...location, state });
  }, [history, location]);

  const refreshConversation = useCallback(
    (id: string) => {
      if (!stillMounted()) return;
      const version = conversationVersions.current.get(id) ?? 0;
      void retries
        .keepTrying(`conversation:${id}`, async () => {
          const updates: ConversationUpdate[] = [];
          pendingConversationUpdates.current.add(updates);
          try {
            const { data } = await api().get<ChatConversation>(
              `/api/v1/chat/conversations/${id}`,
            );
            if ((conversationVersions.current.get(id) ?? 0) !== version) return;
            const latest = updates
              .reduce((items, update) => update(items), [data])
              .find((item) => item.id === id);
            pendingConversationUpdates.current.delete(updates);
            if (latest) {
              endedConversations.current.delete(id);
              updateConversations((current) =>
                upsertConversation(current, latest),
              );
            }
          } catch (loadError) {
            if (
              (loadError as { response?: { status?: number } } | null)?.response
                ?.status === 429
            )
              throw loadError;
            if ((conversationVersions.current.get(id) ?? 0) !== version) return;
            if (isNotFound(loadError))
              updateConversations((current) =>
                current.filter((item) => item.id !== id),
              );
          } finally {
            pendingConversationUpdates.current.delete(updates);
          }
        })
        .catch(() => undefined);
    },
    [retries, stillMounted, updateConversations],
  );

  const loadConversations = useCallback(
    async (nextPage: PageCheckpoint) => {
      const requestId = ++latestConversationRequest.current;
      const updates: ConversationUpdate[] = [];
      const activeRooms = new Set<string>();
      pendingConversationUpdates.current.add(updates);
      pendingConversationMessages.current.add(activeRooms);
      const loaded: ChatConversation[] = [];
      const loadedIds = new Set<string>();
      let cursor: ConversationCursor | null = null;
      let restarted = false;
      let missing = false;
      let ending: RoomEnding | null = null;
      try {
        for (let page = 0; page < conversationPages.current; page++) {
          if (
            page > 0 &&
            (!(await nextPage()) ||
              requestId !== latestConversationRequest.current)
          )
            return false;
          let data: ChatConversation[];
          let cursorMessageId: string | undefined;
          try {
            const response = await api().get<ChatConversation[]>(
              '/api/v1/chat/conversations',
              cursor ? { params: cursorParams(cursor) } : undefined,
            );
            data = response.data;
            cursorMessageId = conversationCursorHeader(response);
          } catch (error) {
            if (!cursor || restarted || !isNotFound(error)) throw error;
            if (
              !(await nextPage()) ||
              requestId !== latestConversationRequest.current
            )
              return false;
            restarted = true;
            loaded.length = 0;
            loadedIds.clear();
            cursor = null;
            page = -1;
            continue;
          }
          data.forEach((item) => {
            if (!loadedIds.has(item.id)) {
              loadedIds.add(item.id);
              loaded.push(item);
            }
          });
          const last = data.at(-1);
          cursor =
            data.length === 20 && last
              ? conversationCursor(last, cursorMessageId)
              : null;
          if (!cursor) break;
        }
        if (
          conversationId &&
          !loaded.some((item) => item.id === conversationId)
        ) {
          if (
            !(await nextPage()) ||
            requestId !== latestConversationRequest.current
          )
            return false;
          try {
            const selected = await api().get<ChatConversation>(
              `/api/v1/chat/conversations/${conversationId}`,
            );
            loaded.push(selected.data);
          } catch (loadError) {
            if (!isNotFound(loadError)) throw loadError;
            missing = true;
            ending = roomEndingOf(loadError);
          }
        }
      } catch (loadError) {
        if (requestId !== latestConversationRequest.current) {
          retries.recordFailure('conversations', loadError);
          return false;
        }
        throw loadError;
      } finally {
        pendingConversationUpdates.current.delete(updates);
        pendingConversationMessages.current.delete(activeRooms);
      }
      if (requestId !== latestConversationRequest.current) return;
      appliedConversationGeneration.current += 1;
      updateNextConversationId(cursor);
      setConversationMissing(missing);
      setRoomEnding(ending);
      if (missing && !ending) setError('load');
      const reconciled = updates.reduce(
        (items, update) => update(items),
        loaded,
      );
      reconciled.forEach((item) => {
        endedConversations.current.delete(item.id);
      });
      setConversations(reconciled);
      setConversationsLoaded(true);
      readRecovered('conversations');
      readRecovered('conversations:more');
      activeRooms.forEach((id) => {
        if (!reconciled.some((item) => item.id === id)) refreshConversation(id);
      });
      return true;
    },
    [
      conversationId,
      readRecovered,
      refreshConversation,
      retries,
      updateNextConversationId,
    ],
  );

  const pollConversations = useCallback(
    async (nextPage: PageCheckpoint) => {
      if (conversationPages.current <= 1) return loadConversations(nextPage);
      const requestId = latestConversationRequest.current;
      const appliedGeneration = appliedConversationGeneration.current;
      const updates: ConversationUpdate[] = [];
      pendingConversationUpdates.current.add(updates);
      try {
        const { data } = await api().get<ChatConversation[]>(
          '/api/v1/chat/conversations',
        );
        if (
          requestId !== latestConversationRequest.current ||
          appliedGeneration !== appliedConversationGeneration.current
        )
          return false;
        const fresh = updates.reduce((items, update) => update(items), data);
        const freshIds = new Set(fresh.map((item) => item.id));
        fresh.forEach((item) => {
          endedConversations.current.delete(item.id);
        });
        setConversations((current) => [
          ...fresh,
          ...current.filter((item) => !freshIds.has(item.id)),
        ]);
        readRecovered('conversations');
        return true;
      } finally {
        pendingConversationUpdates.current.delete(updates);
      }
    },
    [loadConversations, readRecovered],
  );

  const loadConversationsForAction = useCallback(async () => {
    if (!stillMounted()) return undefined;
    if (retries.limited('conversations')) {
      if (!retries.planned('conversations'))
        void retries
          .keepTrying('conversations', loadConversations, {
            failed: () => {
              readFailed('conversations');
            },
          })
          .catch(() => undefined);
      return undefined;
    }
    try {
      return await retries.runPages('conversations', loadConversations);
    } catch {
      if (!isMounted.current) return undefined;
      readFailed('conversations');
      void retries
        .keepTrying('conversations', loadConversations, {
          failed: () => {
            readFailed('conversations');
          },
        })
        .catch(() => undefined);
      return undefined;
    }
  }, [loadConversations, readFailed, retries, stillMounted]);

  const loadMoreConversations = useCallback(() => {
    if (!nextConversationId || loadingMore) return;
    setLoadingMore(true);
    let requestId = latestConversationRequest.current;
    let appliedGeneration = appliedConversationGeneration.current;
    const updates: ConversationUpdate[] = [];
    pendingConversationUpdates.current.add(updates);
    void retries
      .runPages('conversations', () => {
        requestId = latestConversationRequest.current;
        appliedGeneration = appliedConversationGeneration.current;
        const cursor = nextConversationIdRef.current;
        if (!cursor) return Promise.resolve(undefined);
        return api().get<ChatConversation[]>('/api/v1/chat/conversations', {
          params: cursorParams(cursor),
        });
      })
      .then((response) => {
        pendingConversationUpdates.current.delete(updates);
        if (
          !response ||
          requestId !== latestConversationRequest.current ||
          appliedGeneration !== appliedConversationGeneration.current
        )
          return;
        conversationPages.current += 1;
        updateConversations((current) =>
          updates.reduce(
            (items, update) => update(items),
            [
              ...current,
              ...response.data.filter(
                (item) => !current.some((existing) => existing.id === item.id),
              ),
            ],
          ),
        );
        const last = response.data.at(-1);
        updateNextConversationId(
          response.data.length === 20 && last
            ? conversationCursor(last, conversationCursorHeader(response))
            : null,
        );
        readRecovered('conversations:more');
      })
      .catch(async (error: unknown) => {
        if (
          isMounted.current &&
          requestId === latestConversationRequest.current &&
          appliedGeneration === appliedConversationGeneration.current
        ) {
          if (isNotFound(error)) await loadConversationsForAction();
          else readFailed('conversations:more');
        }
      })
      .finally(() => {
        pendingConversationUpdates.current.delete(updates);
        setLoadingMore(false);
      });
  }, [
    loadConversationsForAction,
    loadingMore,
    nextConversationId,
    readFailed,
    readRecovered,
    retries,
    updateConversations,
    updateNextConversationId,
  ]);

  const loadInvitations = useCallback(async () => {
    const requestId = ++latestInvitationRequest.current;
    const updates: InvitationUpdate[] = [];
    pendingInvitationUpdates.current.add(updates);
    try {
      const response = await api().get<ChatInvitation[]>(
        '/api/v1/chat/invitations',
      );
      if (requestId !== latestInvitationRequest.current) return false;
      setInvitations(
        updates.reduce((items, update) => update(items), response.data),
      );
      readRecovered('invitations');
      return true;
    } catch (error) {
      if (requestId !== latestInvitationRequest.current) {
        retries.recordFailure('invitations', error);
        return false;
      }
      throw error;
    } finally {
      pendingInvitationUpdates.current.delete(updates);
    }
  }, [readRecovered, retries]);

  const loadMessages = useCallback(async () => {
    if (!conversationId) return false;
    const updates: MessageUpdate[] = [];
    pendingMessageUpdates.current.add(updates);
    const requestId = ++latestMessageRequest.current;
    const liveWhenAsked = isChatStreamLive();
    const response = await api()
      .get<ChatMessage[]>(
        `/api/v1/chat/conversations/${conversationId}/messages`,
      )
      .catch((error: unknown) => {
        pendingMessageUpdates.current.delete(updates);
        throw error;
      });
    pendingMessageUpdates.current.delete(updates);
    if (requestId !== latestMessageRequest.current) return false;
    firstMessagesRead.current = true;
    appliedMessageGeneration.current += 1;
    updateOlderMessageId(
      response.data.length === 40 ? (response.data[0]?.id ?? null) : null,
    );
    initialMessageSnapshotWasEmpty.current = response.data.length === 0;
    advanceContinuousUpTo(response.data.at(-1)?.id);
    readSinceStreamWentLive.current = liveWhenAsked && isChatStreamLive();
    setMessagesList(
      updates.reduce(
        (items, update) => update(items),
        response.data.map(applyTombstone),
      ),
    );
    setMessagesLoaded(true);
    if (isMounted.current)
      queueVisibleRead(conversationId, response.data.at(-1)?.id);
    return true;
  }, [
    advanceContinuousUpTo,
    applyTombstone,
    conversationId,
    queueVisibleRead,
    updateOlderMessageId,
  ]);

  const resyncMessages = useCallback(
    async (nextPage: PageCheckpoint, latestOnly = false) => {
      if (!conversationId) return;
      const updates: MessageUpdate[] = [];
      pendingMessageUpdates.current.add(updates);
      const requestId = ++latestMessageRequest.current;
      const liveWhenAsked = isChatStreamLive();
      const oldestShown = shownMessagesRef.current[0]?.id;
      const continuous = continuousUpTo.current;
      const mustReachStart = initialMessageSnapshotWasEmpty.current;
      const from =
        latestOnly && continuous
          ? continuous
          : oldestShown && continuous
            ? compareId(oldestShown, continuous) < 0
              ? oldestShown
              : continuous
            : (oldestShown ?? continuous);
      const pageLimit = latestOnly
        ? MESSAGE_RESYNC_PAGES
        : MESSAGE_RESYNC_PAGES +
          Math.ceil(shownMessagesRef.current.length / MESSAGE_PAGE_SIZE);
      const loaded: ChatMessage[] = [];
      let reachedStart = false;
      let meetsKnown = false;
      try {
        for (let page = 0; page < pageLimit; page++) {
          if (page > 0 && !(await nextPage())) return;
          const { data }: { data: ChatMessage[] } = await api().get<
            ChatMessage[]
          >(
            `/api/v1/chat/conversations/${conversationId}/messages`,
            loaded[0] ? { params: { max_id: loaded[0].id } } : undefined,
          );
          loaded.unshift(...data);
          reachedStart = data.length < MESSAGE_PAGE_SIZE;
          const oldestLoaded = loaded[0]?.id;
          meetsKnown =
            !mustReachStart &&
            oldestLoaded !== undefined &&
            from !== undefined &&
            compareId(oldestLoaded, from) <= 0;
          if (reachedStart || meetsKnown || (!mustReachStart && !from)) break;
        }
      } finally {
        pendingMessageUpdates.current.delete(updates);
      }
      if (requestId !== latestMessageRequest.current) return;
      initialMessageSnapshotWasEmpty.current = loaded.length === 0;
      setMessagesLoaded(true);
      advanceContinuousUpTo(loaded.at(-1)?.id);
      readSinceStreamWentLive.current = liveWhenAsked && isChatStreamLive();
      readRecovered('messages');

      const fetched = updates.reduce(
        (items, update) => update(items),
        loaded.map(applyTombstone),
      );
      const oldestFetched = fetched[0]?.id;
      if (meetsKnown && oldestFetched !== undefined) {
        setMessagesList((current) => [
          ...current.filter((item) => compareId(item.id, oldestFetched) < 0),
          ...fetched,
        ]);
      } else {
        const newestPage = reachedStart
          ? fetched
          : fetched.slice(-MESSAGE_PAGE_SIZE);
        appliedMessageGeneration.current += 1;
        setMessagesList(newestPage);
        updateOlderMessageId(reachedStart ? null : (newestPage[0]?.id ?? null));
      }

      if (!scroll.follows()) {
        const shownIds = new Set(
          shownMessagesRef.current.map((item) => item.id),
        );
        if (
          fetched.some(
            (item) => item.account.id !== me && !shownIds.has(item.id),
          )
        ) {
          jumpButton.update({ unseen: true });
          unreadWhileAway.current = true;
        }
        return;
      }
      if (isMounted.current)
        queueVisibleRead(conversationId, loaded.at(-1)?.id);
    },
    [
      advanceContinuousUpTo,
      applyTombstone,
      conversationId,
      jumpButton,
      queueVisibleRead,
      readRecovered,
      scroll,
      updateOlderMessageId,
    ],
  );

  const catchUpMessages = useCallback(
    (nextPage: PageCheckpoint) => resyncMessages(nextPage, true),
    [resyncMessages],
  );

  const markSeenOnReturn = useCallback(() => {
    if (!unreadWhileAway.current || !conversationId || !isVisible()) return;
    const newest = shownMessagesRef.current.at(-1)?.id;
    if (!newest || !scroll.messageVisible(newest)) return;
    unreadWhileAway.current = false;
    pendingVisibleRead.current = null;
    jumpButton.update({ unseen: false });
    markRead(conversationId, newest);
  }, [conversationId, jumpButton, markRead, scroll]);

  const loadOlderMessages = useCallback(() => {
    if (!olderMessageId || !conversationId || loadingMore) return;
    setLoadingMore(true);
    const updates: MessageUpdate[] = [];
    pendingMessageUpdates.current.add(updates);
    let requestId = latestMessageRequest.current;
    let appliedGeneration = appliedMessageGeneration.current;
    void retries
      .runPages(`messages:${conversationId}`, () => {
        requestId = latestMessageRequest.current;
        appliedGeneration = appliedMessageGeneration.current;
        const cursor = olderMessageIdRef.current;
        if (!cursor) return Promise.resolve(undefined);
        return api().get<ChatMessage[]>(
          `/api/v1/chat/conversations/${conversationId}/messages`,
          { params: { max_id: cursor } },
        );
      })
      .then((response) => {
        pendingMessageUpdates.current.delete(updates);
        if (
          !response ||
          requestId !== latestMessageRequest.current ||
          appliedGeneration !== appliedMessageGeneration.current
        )
          return;
        const { data } = response;
        const older = updates.reduce(
          (items, update) => update(items),
          data.map(applyTombstone),
        );
        scroll.dispatch({ type: 'olderArriving' });
        updateMessages((current) => [
          ...older.filter(
            (item) => !current.some((existing) => existing.id === item.id),
          ),
          ...current,
        ]);
        updateOlderMessageId(data.length === 40 ? (data[0]?.id ?? null) : null);
        olderPageRateLimited.current = false;
        readRecovered('messages');
      })
      .catch((error: unknown) => {
        if (
          isMounted.current &&
          requestId === latestMessageRequest.current &&
          appliedGeneration === appliedMessageGeneration.current
        ) {
          olderPageRateLimited.current =
            (error as { response?: { status?: number } } | null)?.response
              ?.status === 429;
          readFailed('messages');
          if (olderPageRateLimited.current && scroll.seeking())
            void retries
              .keepTrying(`messages:${conversationId}`, resyncMessages, {
                failed: () => {
                  readFailed('messages');
                },
              })
              .catch(() => undefined);
        }
      })
      .finally(() => {
        pendingMessageUpdates.current.delete(updates);
        setLoadingMore(false);
      });
  }, [
    applyTombstone,
    conversationId,
    loadingMore,
    olderMessageId,
    readFailed,
    readRecovered,
    resyncMessages,
    retries,
    scroll,
    updateMessages,
    updateOlderMessageId,
  ]);

  const keepReading = useCallback(
    <T,>(read: string, run: (nextPage: PageCheckpoint) => Promise<T>) =>
      retries
        .keepTrying(read, run, {
          failed: () => {
            readFailed(read);
          },
        })
        .catch(() => undefined),
    [readFailed, retries],
  );

  useEffect(() => {
    void whileOpening(
      keepReading('conversations', async (nextPage) => {
        if (await loadConversations(nextPage)) readRecovered('conversations');
      }),
    );
    void whileOpening(keepReading('invitations', loadInvitations));
    void keepReading('settings', async () => {
      const settingsResponse = await api().get<ChatSettings>(
        '/api/v1/chat/settings',
      );
      setChatSettings(settingsResponse.data);
      readRecovered('settings');
    });
    return () => {
      retries.cancel('conversations');
      retries.cancel('invitations');
      retries.cancel('settings');
    };
  }, [
    keepReading,
    loadConversations,
    loadInvitations,
    readRecovered,
    retries,
    whileOpening,
  ]);

  const readFirstMessages = useCallback(async () => {
    if (!(await loadMessages())) throw new Error('A newer read took over');
    readRecovered('messages');
  }, [loadMessages, readRecovered]);

  useEffect(() => {
    if (!conversationId) return undefined;
    const read = `messages:${conversationId}`;
    void whileOpening(
      retries
        .keepTrying(read, readFirstMessages, {
          failed: () => {
            readFailed('messages');
          },
        })
        .catch(() => undefined),
    );
    return () => {
      retries.cancel(read);
    };
  }, [conversationId, readFailed, readFirstMessages, retries, whileOpening]);

  const hasUnread = Boolean(conversation?.unread);
  useEffect(() => {
    if (!conversationId || !hasUnread) return;

    const markReadWhenShown = () => {
      if (!isVisible() || !scroll.following()) return;
      queueVisibleRead(conversationId, shownMessagesRef.current.at(-1)?.id);
    };

    document.addEventListener('visibilitychange', markReadWhenShown);
    return () => {
      document.removeEventListener('visibilitychange', markReadWhenShown);
    };
  }, [conversationId, hasUnread, queueVisibleRead, scroll]);

  useEffect(
    () =>
      subscribeChatStream(({ event, payload }) => {
        const value = payload as Partial<ChatMessage> &
          Partial<ChatReaction> & {
            conversation_id?: string;
            message_id?: string;
            account_id?: string;
            reason?: RoomEnding;
          };
        const eventConversationId = value.conversation_id;
        if (event === 'chat.message') {
          if (!eventConversationId) return;
          pendingConversationMessages.current.forEach((rooms) =>
            rooms.add(eventConversationId),
          );
          const message = applyTombstone(value as ChatMessage);
          const isOpen = eventConversationId === conversationId;
          const fromOther = value.account?.id !== me;
          const seen = isOpen && isVisible() && scroll.follows();
          updateConversations((current) =>
            withNewMessage(current, message, fromOther),
          );
          if (knownConversationIds.current?.has(eventConversationId) === false)
            refreshConversation(eventConversationId);
          if (!isOpen) return;
          if (isChatStreamLive() && readSinceStreamWentLive.current)
            advanceContinuousUpTo(value.id);
          updateMessages((current) => insertMessage(current, message));
          if (!seen && fromOther) {
            jumpButton.update({ unseen: true });
            unreadWhileAway.current = true;
          }
          if (value.id && fromOther && seen)
            queueVisibleRead(conversationId, value.id, true);
        } else if (event === 'chat.message_update') {
          const message = applyTombstone(value as ChatMessage);
          updateSearchResults((current, query) => {
            const matchesSearch =
              message.content &&
              foldSearch(message.content).includes(foldSearch(query));
            return current.flatMap((item) =>
              item.id !== message.id ? [item] : matchesSearch ? [message] : [],
            );
          });
          updateConversations((current) =>
            current.map((item) =>
              item.id === eventConversationId &&
              item.last_message?.id === value.id
                ? { ...item, last_message: message }
                : item,
            ),
          );
          if (eventConversationId !== conversationId) return;
          updateMessages((current) =>
            current.map((item) => (item.id === value.id ? message : item)),
          );
        } else if (event === 'chat.message_delete') {
          if (!value.id) return;
          const id = value.id;
          updateSearchResults((current) =>
            current.filter((item) => item.id !== id),
          );
          deletedMessages.current.set(value.id, new Date().toISOString());
          updateConversations((current) =>
            current.map((item) =>
              item.id === eventConversationId &&
              item.last_message &&
              item.last_message.id === value.id
                ? { ...item, last_message: applyTombstone(item.last_message) }
                : item,
            ),
          );
          if (eventConversationId !== conversationId) return;
          updateMessages((current) =>
            current.map((item) =>
              item.id === value.id ? applyTombstone(item) : item,
            ),
          );
        } else if (event === 'chat.message_hide') {
          if (!value.id) return;
          const id = value.id;
          updateSearchResults((current) =>
            current.filter((item) => item.id !== id),
          );
          deletedMessages.current.set(value.id, new Date().toISOString());
          if (eventConversationId) refreshConversation(eventConversationId);
          if (eventConversationId !== conversationId) return;
          updateMessages((current) =>
            current.filter((item) => item.id !== value.id),
          );
        } else if (event === 'chat.conversation_update') {
          const updated = payload as Partial<ChatConversation>;
          if (updated.id && endedConversations.current.has(updated.id)) return;
          if (updated.accounts) {
            updateConversations((current) =>
              withConversationUpdate(current, updated as ChatConversation),
            );
          } else if (updated.id) {
            refreshConversation(updated.id);
          }
        } else if (event === 'chat.reaction') {
          if (!value.message_id || !value.account?.id || !value.reaction)
            return;
          const reaction = value as ChatReaction;
          updateMessages((current) =>
            current.map((item) =>
              item.id === reaction.message_id && !item.deleted_at
                ? {
                    ...item,
                    reactions: [
                      ...item.reactions.filter(
                        (existing) =>
                          existing.account.id !== reaction.account.id ||
                          existing.reaction !== reaction.reaction,
                      ),
                      reaction,
                    ],
                  }
                : item,
            ),
          );
        } else if (event === 'chat.reaction_delete' && value.message_id) {
          const deleted = value as unknown as {
            message_id: string;
            account_id: string;
            reaction: string;
          };

          updateMessages((current) =>
            current.map((item) =>
              item.id === deleted.message_id
                ? {
                    ...item,
                    reactions: item.reactions.filter(
                      (existing) =>
                        existing.account.id !== deleted.account_id ||
                        existing.reaction !== deleted.reaction,
                    ),
                  }
                : item,
            ),
          );
        } else if (event === 'chat.conversation_delete') {
          if (value.conversation_id) {
            const id = value.conversation_id;
            pendingConversationMessages.current.forEach((rooms) =>
              rooms.delete(id),
            );
            updateSearchResults((current) =>
              current.filter((item) => item.conversation_id !== id),
            );
            conversationVersions.current.set(
              id,
              (conversationVersions.current.get(id) ?? 0) + 1,
            );
            endedConversations.current.add(id);
            retries.cancel(`conversation:${id}`);
          }
          updateConversations((current) =>
            current.filter((item) => item.id !== value.conversation_id),
          );
          updateInvitations((current) =>
            current.filter(
              (item) => item.conversation.id !== value.conversation_id,
            ),
          );
          if (value.conversation_id !== conversationId) return;
          if (!value.reason) {
            leaveChatRoute(history, '/chat');
            return;
          }
          latestConversationRequest.current += 1;
          setConversationMissing(true);
          setRoomEnding(value.reason);
        } else if (event === 'chat.read' && value.conversation_id) {
          updateConversations((current) =>
            current.map((item) =>
              item.id === value.conversation_id &&
              value.message_id &&
              (!item.last_message ||
                compareId(item.last_message.id, value.message_id) <= 0)
                ? { ...item, unread: false }
                : item,
            ),
          );
        } else if (event === 'chat.invitation') {
          void keepReading('invitations', loadInvitations);
        } else if (event === 'chat.invitation_update') {
          if (eventConversationId === conversationId)
            setSentInvitationsVersion((version) => version + 1);
        } else if (
          event === CHAT_STREAM_RECONNECTED ||
          event === CHAT_STREAM_POLLED
        ) {
          const latestOnly = event === CHAT_STREAM_POLLED;
          readSinceStreamWentLive.current = false;
          if (!latestOnly) setSentInvitationsVersion((version) => version + 1);
          const readAgain = () => {
            if (!latestOnly || !retries.planned('conversations')) {
              if (retries.planned('conversations'))
                latestConversationRequest.current += 1;
              const readConversations = latestOnly
                ? pollConversations
                : loadConversations;
              void retries
                .keepTrying('conversations', async (nextPage) => {
                  if (await readConversations(nextPage))
                    readRecovered('conversations');
                })
                .catch(() => undefined);
            }
            retries.wake('conversations');
            void retries
              .keepTrying('invitations', loadInvitations)
              .catch(() => undefined);
            retries.wake('invitations');
            if (conversationId) {
              const read = `messages:${conversationId}`;
              if (!latestOnly || !retries.planned(read))
                void retries
                  .keepTrying(
                    read,
                    !firstMessagesRead.current
                      ? readFirstMessages
                      : latestOnly
                        ? catchUpMessages
                        : resyncMessages,
                  )
                  .catch(() => undefined);
              retries.wake(read);
            }
          };
          if (openingReads.current.size > 0) {
            void Promise.allSettled(openingReads.current).then(() => {
              if (isMounted.current) readAgain();
            });
          } else {
            readAgain();
          }
        } else if (event !== 'chat.notification' && eventConversationId) {
          refreshConversation(eventConversationId);
        }
      }),
    [
      advanceContinuousUpTo,
      applyTombstone,
      conversationId,
      history,
      jumpButton,
      keepReading,
      catchUpMessages,
      loadConversations,
      loadInvitations,
      pollConversations,
      queueVisibleRead,
      readFirstMessages,
      readRecovered,
      refreshConversation,
      resyncMessages,
      retries,
      scroll,
      updateConversations,
      updateInvitations,
      updateMessages,
      updateSearchResults,
    ],
  );

  const finishEditing = useCallback(() => {
    setEditingId(null);
    composerText.set(textBeforeEdit.current ?? '');
    textBeforeEdit.current = null;
  }, [composerText]);

  const isArchived = Boolean(conversation?.archived);
  const recipientSuspended =
    conversation?.type === 'direct' &&
    conversation.accounts.some((item) => item.id !== me && item.suspended);
  const editingTargetDeleted = messagesList.some(
    (message) => message.id === editingId && message.deleted_at,
  );
  const editingCannotGoOn =
    Boolean(editingId) && (isArchived || editingTargetDeleted);
  useLayoutEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (editingCannotGoOn) finishEditing();
  }, [editingCannotGoOn, finishEditing]);
  if (replyToId && isArchived) setReplyToId(null);

  const newestMessage = messagesList.at(-1);
  const newestMessageId = newestMessage?.id;
  const newestMessageConversationId = newestMessage?.conversation_id;
  const newestMessageIsMine = newestMessage?.account.id === me;

  const isGroupOwner =
    conversation?.type === 'group' && conversation.current_role === 'owner';
  const isManagingRoom =
    (roomView === 'members' && conversation?.type === 'group') ||
    (roomView === 'settings' && isGroupOwner);
  const jumpTargetLoaded = Boolean(
    jumpTargetId && messagesById.has(jumpTargetId),
  );
  const readNewestWhenShown = useCallback(() => {
    queueVisibleRead(conversationId ?? '', newestMessageId);
  }, [conversationId, newestMessageId, queueVisibleRead]);
  const forgetSearchedMessage = useCallback(() => {
    const current = history.location as typeof location;
    if (!current.state?.chatMessageId) return;
    const state = { ...current.state };
    delete state.chatMessageId;
    history.replace({ ...current, state });
  }, [history]);
  useChatScroll(scroll, {
    endRef: messagesEndRef,
    listRef: messagesListRef,
    composerRef,
    jumpButton,
    attachKey: `${conversationId ?? ''}:${roomView ?? ''}:${conversationMissing}:${isManagingRoom}`,
    screen:
      newestMessageConversationId === conversationId
        ? `${conversationId}:${roomView ?? ''}`
        : null,
    newestId: newestMessageId,
    newestIsMine: newestMessageIsMine,
    oldestId: messagesList[0]?.id,
    targetShown: jumpTargetLoaded,
    onReadCheck: attemptVisibleRead,
    onReturn: markSeenOnReturn,
    onReadNewest: readNewestWhenShown,
    onForgetSearch: forgetSearchedMessage,
  });

  useEffect(() => {
    attemptVisibleRead();
    if (
      pendingVisibleRead.current &&
      pendingVisibleRead.current.room === conversationId &&
      pendingVisibleRead.current.notify
    ) {
      unreadWhileAway.current = true;
      jumpButton.update({ unseen: true });
    }
  }, [attemptVisibleRead, conversationId, jumpButton, visibleReadRevision]);

  useEffect(() => {
    if (
      !jumpTargetId ||
      jumpTargetLoaded ||
      !messagesLoaded ||
      loadingMore ||
      (olderMessageId &&
        (!failedReads.current.has('messages') || olderPageRateLimited.current))
    )
      return;
    scroll.dispatch({ type: 'targetMissing' });
  }, [
    jumpTargetId,
    jumpTargetLoaded,
    loadingMore,
    messagesLoaded,
    olderMessageId,
    readingError,
    scroll,
  ]);

  useEffect(() => {
    if (
      !jumpTargetId ||
      jumpTargetLoaded ||
      newestMessageConversationId !== conversationId ||
      error ||
      sendError ||
      readingError
    )
      return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadOlderMessages();
  }, [
    conversationId,
    error,
    sendError,
    readingError,
    jumpTargetId,
    jumpTargetLoaded,
    loadOlderMessages,
    newestMessageConversationId,
  ]);

  const handleJumpToNewest = useCallback(() => {
    scroll.dispatch({ type: 'jumpToNewest' });
  }, [scroll]);

  const handleReplyQuoteClick = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const targetId = event.currentTarget.dataset.messageId;
      if (targetId) scroll.dispatch({ type: 'quoteClicked', id: targetId });
    },
    [scroll],
  );

  const handleBack = useCallback(() => {
    leaveChatRoute(
      history,
      roomView && conversationId ? `/chat/${conversationId}` : '/chat',
    );
  }, [conversationId, history, roomView]);

  const handleBackToChats = useCallback(
    (event: MouseEvent<HTMLAnchorElement>) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey) return;
      if (event.shiftKey || event.altKey) return;
      event.preventDefault();
      leaveChatRoute(history, '/chat');
    },
    [history],
  );

  const listsSentInvitations = roomView === 'members' && isGroupOwner;

  useEffect(() => {
    if (!conversationId || !listsSentInvitations) return undefined;

    let current = true;
    const read = `sent:${conversationId}`;
    void keepReading(read, async (nextPage) => {
      const updates: InvitationUpdate[] = [];
      pendingSentInvitationUpdates.current.add(updates);
      try {
        const found = await fetchSentInvitations(conversationId, nextPage);
        if (!current || !found) return;
        setSentInvitations(
          updates.reduce((items, update) => update(items), found),
        );
        readRecovered(read);
      } finally {
        pendingSentInvitationUpdates.current.delete(updates);
      }
    });
    return () => {
      current = false;
      retries.cancel(read);
      readRecovered(read);
    };
  }, [
    conversationId,
    keepReading,
    listsSentInvitations,
    readRecovered,
    retries,
    sentInvitationsVersion,
  ]);

  const shownSentInvitations = listsSentInvitations
    ? sentInvitations
        .filter((invitation) => invitation.conversation.id === conversationId)
        .reverse()
    : [];

  const createDirect = useCallback(async () => {
    if (!directAccount) return;
    setLoading(true);
    setError(null);
    try {
      const response = await api().post<ChatConversation>(
        '/api/v1/chat/conversations',
        {
          type: 'direct',
          account_ids: [directAccount.id],
        },
      );
      navigateIfActive(`/chat/${response.data.id}`, response.data);
      setDirectAccount(null);
      setDirectAccountQuery('');
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [directAccount, navigateIfActive]);

  const composerMedia = editingId ? [] : media;
  const hasOtherContent =
    composerMedia.length > 0 ||
    messagesList.some(
      (message) =>
        message.id === editingId &&
        !message.deleted_at &&
        message.media_attachments.length > 0,
    );

  const send = useCallback(async () => {
    const text = composerText.get();
    if (
      !conversationId ||
      loading ||
      uploading ||
      recipientSuspended ||
      !(text.trim() || hasOtherContent) ||
      isTooLong(text)
    )
      return;
    setLoading(true);
    const sentMedia = editingId ? [] : media.map((item) => item.id);
    try {
      const response = editingId
        ? await api().patch<ChatMessage>(`/api/v1/chat/messages/${editingId}`, {
            text: text.trim(),
          })
        : await api().post<ChatMessage>(
            `/api/v1/chat/conversations/${conversationId}/messages`,
            {
              text: text.trim(),
              reply_to_id: replyToId,
              media_ids: sentMedia,
            },
          );
      setSendError(null);
      const message = applyTombstone(response.data);
      updateMessages((current) =>
        current.some((item) => item.id === message.id)
          ? current.map((item) => (item.id === message.id ? message : item))
          : insertMessage(current, message),
      );
      if (editingId) {
        finishEditing();
      } else {
        const withoutSent = (current: string) =>
          current.startsWith(text) ? current.slice(text.length) : current;
        if (textBeforeEdit.current === null)
          composerText.set(withoutSent(composerText.get()));
        else textBeforeEdit.current = withoutSent(textBeforeEdit.current);
        setMedia((current) =>
          current.filter((item) => !sentMedia.includes(item.id)),
        );
      }
      setReplyToId(null);
    } catch (sendError) {
      setSendError(isRefused(sendError) ? 'refused' : 'send');
    } finally {
      setLoading(false);
    }
  }, [
    applyTombstone,
    composerText,
    conversationId,
    editingId,
    finishEditing,
    hasOtherContent,
    loading,
    media,
    recipientSuspended,
    replyToId,
    updateMessages,
    uploading,
  ]);

  const handleComposerSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      void send();
    },
    [send],
  );

  const handleComposerMouseDown = useCallback(
    (event: MouseEvent<HTMLFormElement>) => {
      const form = event.currentTarget;
      const target = event.target as Element;
      if (
        (target === form || target.closest('button[type="submit"]')) &&
        document.activeElement === form.querySelector('textarea')
      )
        event.preventDefault();
    },
    [],
  );

  const handleComposerKeyDown = useCallback(
    (event: KeyboardEvent<HTMLTextAreaElement>) => {
      if (scrollsConversation(event)) {
        event.preventDefault();
        return;
      }
      if (
        event.key !== 'Enter' ||
        event.nativeEvent.isComposing ||
        // eslint-disable-next-line @typescript-eslint/no-deprecated
        event.keyCode === 229
      )
        return;
      const sends =
        event.ctrlKey ||
        event.metaKey ||
        (!event.shiftKey && !event.altKey && !usesTouchKeyboard());
      if (!sends) return;
      event.preventDefault();
      void send();
    },
    [send],
  );

  const handleDirectSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      void createDirect();
    },
    [createDirect],
  );

  const handleDirectAccountQueryChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const value = event.target.value;
      setDirectAccount(null);
      setDirectAccountQuery(value);
      searchAccounts(value, setAccountResults);
    },
    [searchAccounts],
  );

  const handleAccountResult = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.accountId;
      const account = accountResults.find((item) => item.id === id);
      if (!account) return;
      setDirectAccount(account);
      setDirectAccountQuery('');
      searchAccounts('', setAccountResults);
    },
    [accountResults, searchAccounts],
  );

  const handleRemoveDirectAccount = useCallback(() => {
    setDirectAccount(null);
    setDirectAccountQuery('');
  }, []);

  const handleGroupTitleChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setGroupTitle(event.target.value);
    },
    [],
  );

  const handleGroupEditTitleChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      if (!conversation) return;
      setGroupEdit({
        conversationId: conversation.id,
        title: event.target.value,
        description: groupEdit?.description ?? conversation.description ?? '',
      });
    },
    [conversation, groupEdit?.description],
  );

  const handleGroupEditDescriptionChange = useCallback(
    (event: ChangeEvent<HTMLTextAreaElement>) => {
      if (!conversation) return;
      setGroupEdit({
        conversationId: conversation.id,
        title: groupEdit?.title ?? conversation.title ?? '',
        description: event.target.value,
      });
    },
    [conversation, groupEdit?.title],
  );

  const handleGroupAccountQueryChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setGroupAccountQuery(event.target.value);
      searchAccounts(event.target.value, setGroupAccountResults);
    },
    [searchAccounts],
  );

  const handleGroupAccountResult = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.accountId;
      const account = groupAccountResults.find((item) => item.id === id);
      if (!account) return;
      setGroupAccounts((current) =>
        current.some((item) => item.id === account.id)
          ? current
          : [...current, account],
      );
      setGroupAccountQuery('');
      searchAccounts('', setGroupAccountResults);
    },
    [groupAccountResults, searchAccounts],
  );

  const handleRemoveGroupAccount = useCallback((id: string) => {
    setGroupAccounts((current) =>
      current.filter((account) => account.id !== id),
    );
  }, []);

  const handleInviteAccountQueryChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setInviteAccount(null);
      setInviteAccountQuery(event.target.value);
      searchAccounts(event.target.value, setInviteAccountResults);
    },
    [searchAccounts],
  );

  const handleInviteAccountResult = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.accountId;
      const account = inviteAccountResults.find((item) => item.id === id);
      if (!account) return;
      setInviteAccount(account);
      setInviteAccountQuery('');
      searchAccounts('', setInviteAccountResults);
    },
    [inviteAccountResults, searchAccounts],
  );

  const handleRemoveInviteAccount = useCallback(() => {
    setInviteAccount(null);
    setInviteAccountQuery('');
  }, []);

  const handleAttachClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const cancelMessageSearch = useCallback(() => {
    window.clearTimeout(messageSearchTimeoutRef.current);
    latestMessageSearch.current += 1;
  }, []);

  const handleSearchToggle = useCallback(() => {
    cancelMessageSearch();
    setSearchOpen((open) => !open);
    setSearchQuery('');
    setSearchResults([]);
    setSearchedQuery(null);
  }, [cancelMessageSearch]);

  useEffect(() => cancelMessageSearch, [cancelMessageSearch]);

  useEffect(() => {
    if (searchOpen) searchInputRef.current?.focus();
  }, [searchOpen]);

  const handleNewChatMode = useCallback(
    (event: SyntheticEvent<HTMLButtonElement>) => {
      setNewChatMode(event.currentTarget.dataset.mode as 'direct' | 'group');
    },
    [],
  );

  const runMessageSearch = useCallback(
    (query: string) => {
      cancelMessageSearch();
      const requestId = latestMessageSearch.current;
      const updates: MessageUpdate[] = [];
      const pending = { query, updates };
      pendingSearchUpdates.current.add(pending);
      setError(null);
      void api()
        .get<ChatMessage[]>('/api/v1/chat/messages/search', {
          params: { q: query, limit: 40 },
        })
        .then((response) => {
          if (requestId !== latestMessageSearch.current) return;
          displayedSearchQuery.current = query;
          setSearchResults(
            updates.reduce((items, update) => update(items), response.data),
          );
          setSearchedQuery(query);
        })
        .catch(() => {
          if (requestId === latestMessageSearch.current) setError('search');
        })
        .finally(() => {
          pendingSearchUpdates.current.delete(pending);
        });
    },
    [cancelMessageSearch],
  );

  const handleSearchChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const query = event.target.value.trim();
      setSearchQuery(event.target.value);
      cancelMessageSearch();
      if (query) {
        messageSearchTimeoutRef.current = window.setTimeout(() => {
          runMessageSearch(query);
        }, SEARCH_DEBOUNCE_MS);
      } else {
        setSearchResults([]);
        setSearchedQuery(null);
      }
    },
    [cancelMessageSearch, runMessageSearch],
  );

  const handleSearchSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      const query = searchQuery.trim();
      if (query) runMessageSearch(query);
    },
    [runMessageSearch, searchQuery],
  );

  const handleSearchResult = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const { conversationId: id, messageId } = event.currentTarget.dataset;
      if (id) history.push(`/chat/${id}`, { chatMessageId: messageId });
    },
    [history],
  );

  const createGroup = useCallback(async () => {
    if (!groupTitle.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const response = await api().post<ChatConversation>(
        '/api/v1/chat/conversations',
        {
          type: 'group',
          title: groupTitle.trim(),
          account_ids: groupAccounts.map((account) => account.id),
        },
      );
      navigateIfActive(`/chat/${response.data.id}`, response.data);
      setGroupTitle('');
      setGroupAccountQuery('');
      setGroupAccounts([]);
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [groupAccounts, groupTitle, navigateIfActive]);

  const handleGroupSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      void createGroup();
    },
    [createGroup],
  );

  const uploadFiles = useCallback(
    (files: File[]) => {
      if (!chatSettings || files.length === 0) return;
      if (files.length + media.length > chatSettings.max_attachments) {
        setError('too_many_attachments');
        return;
      }
      const signal = uploadAbort.current?.signal;
      if (!signal || signal.aborted) return;
      setError(null);
      setUploading(true);
      let remaining = files.length;
      files.forEach((file) => {
        void (async () => {
          const body = new FormData();
          body.append('file', file);
          const response = await api().post<ChatMedia>('/api/v2/media', body);
          return waitForMedia(response.data, signal);
        })()
          .then((uploaded) => {
            if (!signal.aborted) setMedia((current) => [...current, uploaded]);
          })
          .catch(() => {
            if (!signal.aborted) setError('upload');
          })
          .finally(() => {
            remaining -= 1;
            if (!signal.aborted && remaining === 0) setUploading(false);
          });
      });
    },
    [chatSettings, media.length],
  );

  const handleMediaChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const files = Array.from(event.target.files ?? []);
      event.target.value = '';
      uploadFiles(files);
    },
    [uploadFiles],
  );

  const handleComposerPaste = useCallback(
    (event: ClipboardEvent<HTMLTextAreaElement>) => {
      const files = Array.from(event.clipboardData.files).filter((file) =>
        /^(image|video|audio)\//.test(file.type),
      );
      if (files.length === 0) return;
      event.preventDefault();
      if (loading || uploading || editingId || isArchived) return;
      uploadFiles(files);
    },
    [editingId, isArchived, loading, uploadFiles, uploading],
  );

  const handleMessageAction = useCallback(
    (id: string, action: MessageAction) => {
      const message = messagesList.find((item) => item.id === id);
      if (!message) return;
      setError(null);

      if (action === 'copy') {
        void writeToClipboard(message.content ?? '').then(
          () => {
            dispatch(showAlert({ message: messages.copied }));
          },
          () => {
            setError('copy');
          },
        );
      } else if (action === 'reply') {
        if (editingId) finishEditing();
        setReplyToId(id);
      } else if (action === 'edit') {
        textBeforeEdit.current ??= composerText.get();
        setEditingId(id);
        setReplyToId(null);
        composerText.set(message.content ?? '');
      } else {
        const deletionNotice = (deletesForEveryone: boolean | null) => {
          if (deletesForEveryone === null)
            return intl.formatMessage({
              id: 'chat.delete_message_confirm_unknown',
              defaultMessage:
                "It may disappear for everyone or only for you, depending on this server's settings. This can't be undone.",
            });
          return deletesForEveryone
            ? intl.formatMessage({
                id: 'chat.delete_message_confirm',
                defaultMessage:
                  "It will show as deleted for everyone in this chat. This can't be undone.",
              })
            : intl.formatMessage({
                id: 'chat.hide_message_confirm',
                defaultMessage:
                  "It will disappear only for you. Others in this chat can still see it. This can't be undone.",
              });
        };
        const confirmDeletion = (deletesForEveryone: boolean | null) => {
          dispatch(
            openModal({
              modalType: 'CONFIRM',
              modalProps: {
                title: intl.formatMessage({
                  id: 'chat.delete_message',
                  defaultMessage: 'Delete this message?',
                }),
                message: deletionNotice(deletesForEveryone),
                confirm: intl.formatMessage(messages.delete),
                onConfirm: () => {
                  void api()
                    .delete(`/api/v1/chat/messages/${id}`)
                    .then(() => {
                      deletedMessages.current.set(id, new Date().toISOString());
                      updateMessages((current) =>
                        current.map((item) =>
                          item.id === id ? applyTombstone(item) : item,
                        ),
                      );
                      refreshConversation(message.conversation_id);
                    })
                    .catch(() => {
                      setError('delete');
                    });
                },
              },
            }),
          );
        };
        void api()
          .get<ChatMessage>(`/api/v1/chat/messages/${id}`)
          .then(({ data }) => data.deletes_for_everyone ?? null)
          .catch(() => null)
          .then(confirmDeletion);
      }
    },
    [
      applyTombstone,
      composerText,
      dispatch,
      editingId,
      finishEditing,
      intl,
      messagesList,
      refreshConversation,
      updateMessages,
    ],
  );

  const handleOpenMedia = useCallback(
    (attachments: ImmutableList<unknown>, index: number) => {
      dispatch(
        openModal({
          modalType: 'MEDIA',
          modalProps: { media: attachments, index },
        }),
      );
    },
    [dispatch],
  );

  const handleEmojiPick = useCallback(
    (messageId: string, emoji: PickedEmoji) => {
      const reaction = reactionFromEmoji(emoji);

      if (!reaction) return;
      const alreadyReacted = messagesList
        .find((item) => item.id === messageId)
        ?.reactions.some(
          (existing) =>
            existing.account.id === me && existing.reaction === reaction,
        );
      if (alreadyReacted) return;
      setError(null);

      void api()
        .post<ChatReaction>(`/api/v1/chat/messages/${messageId}/reactions`, {
          reaction,
        })
        .then((response) => {
          updateMessages((current) =>
            current.map((item) =>
              item.id === messageId && !item.deleted_at
                ? {
                    ...item,
                    reactions: [
                      ...item.reactions.filter(
                        (existing) =>
                          existing.account.id !== response.data.account.id ||
                          existing.reaction !== response.data.reaction,
                      ),
                      response.data,
                    ],
                  }
                : item,
            ),
          );
        })
        .catch(() => {
          setError('reaction');
        });
    },
    [messagesList, updateMessages],
  );

  const handleReactionClick = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const messageId = event.currentTarget.dataset.messageId;
      const reaction = event.currentTarget.dataset.reaction;
      const accountId = event.currentTarget.dataset.accountId;

      if (!messageId || !reaction || accountId !== me) return;
      setError(null);

      void api()
        .delete(
          `/api/v1/chat/messages/${messageId}/reactions/${encodeURIComponent(reaction)}`,
        )
        .then(() => {
          updateMessages((current) =>
            current.map((item) =>
              item.id === messageId
                ? {
                    ...item,
                    reactions: item.reactions.filter(
                      (existing) =>
                        existing.account.id !== me ||
                        existing.reaction !== reaction,
                    ),
                  }
                : item,
            ),
          );
        })
        .catch(() => {
          setError('reaction');
        });
    },
    [updateMessages],
  );

  const handleRemoveMedia = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.mediaId;
      setMedia((current) => current.filter((item) => item.id !== id));
    },
    [],
  );

  const handleCancelComposeMode = useCallback(() => {
    setReplyToId(null);
    if (editingId) finishEditing();
  }, [editingId, finishEditing]);

  const answerInvitation = useCallback(
    (invitation: ChatInvitation, action: 'accept' | 'reject') => {
      setError(null);
      void api()
        .post<ChatConversation | undefined>(
          `/api/v1/chat/invitations/${invitation.id}/${action}`,
        )
        .then(({ data }) => {
          updateInvitations((current) =>
            current.filter((item) => item.id !== invitation.id),
          );
          if (action === 'accept' && data?.id) {
            endedConversations.current.delete(data.id);
            updateConversations((current) => upsertConversation(current, data));
          }
          dispatch(
            showAlert({
              message:
                action === 'accept'
                  ? messages.invitationAccepted
                  : messages.invitationRejected,
              values: { group: conversationName(invitation.conversation) },
            }),
          );
          return loadConversationsForAction();
        })
        .catch(() => {
          setError('invite');
        });
    },
    [
      dispatch,
      loadConversationsForAction,
      updateConversations,
      updateInvitations,
    ],
  );

  const cancelInvitation = useCallback(
    (invitation: ChatInvitation) => {
      setError(null);
      void api()
        .delete(`/api/v1/chat/invitations/${invitation.id}`)
        .then(() => {
          updateSentInvitations((current) =>
            current.filter((item) => item.id !== invitation.id),
          );
          dispatch(
            showAlert({
              message: messages.invitationCancelled,
              values: {
                account: invitation.invitee
                  ? invitation.invitee.display_name || invitation.invitee.acct
                  : '',
              },
            }),
          );
        })
        .catch(() => {
          setError('invite');
        });
    },
    [dispatch, updateSentInvitations],
  );

  const handleInviteSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!conversationId || !inviteAccount) return;
      setError(null);
      void api()
        .post<ChatInvitation | undefined>(
          `/api/v1/chat/conversations/${conversationId}/invitations`,
          {
            account_id: inviteAccount.id,
          },
        )
        .then(({ data }) => {
          if (data?.id)
            updateSentInvitations((current) => [
              data,
              ...current.filter((item) => item.id !== data.id),
            ]);
          dispatch(
            showAlert({
              message: messages.inviteSent,
              values: {
                account: inviteAccount.display_name || inviteAccount.acct,
              },
            }),
          );
          setInviteAccount(null);
          setInviteAccountQuery('');
          setSentInvitationsVersion((version) => version + 1);
        })
        .catch((inviteError: unknown) => {
          setError(isRefused(inviteError) ? 'refused' : 'invite');
        });
    },
    [conversationId, dispatch, inviteAccount, updateSentInvitations],
  );

  const handleGroupEditSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!conversationId || !conversation) return;
      const title =
        groupEdit?.conversationId === conversation.id
          ? groupEdit.title
          : (conversation.title ?? '');
      const description =
        groupEdit?.conversationId === conversation.id
          ? groupEdit.description
          : (conversation.description ?? '');
      if (!title.trim()) return;
      setError(null);
      void api()
        .patch<ChatConversation>(
          `/api/v1/chat/conversations/${conversationId}`,
          {
            title: title.trim(),
            description: description.trim(),
          },
        )
        .then(({ data }) => {
          updateConversations((current) =>
            current.map((item) => (item.id === data.id ? data : item)),
          );
          dispatch(showAlert({ message: messages.groupSaved }));
          setGroupEdit(null);
          return loadConversationsForAction();
        })
        .catch(() => {
          setError('update');
        });
    },
    [
      conversation,
      conversationId,
      dispatch,
      groupEdit,
      loadConversationsForAction,
      updateConversations,
    ],
  );

  const handlePolicyChange = useCallback(
    (event: ChangeEvent<HTMLSelectElement>) => {
      setError(null);
      void api()
        .patch<ChatSettings>('/api/v1/chat/settings', {
          policy: event.target.value,
        })
        .then((response) => {
          setChatSettings((current) =>
            current
              ? { ...current, policy: response.data.policy }
              : response.data,
          );
        })
        .catch(() => {
          setError('settings');
        });
    },
    [],
  );

  const toggleSettings = useMemo(
    () =>
      ImmutableMap({
        allow_group_invites: chatSettings?.allow_group_invites ?? false,
        notifications: chatSettings?.notifications ?? false,
      }),
    [chatSettings?.allow_group_invites, chatSettings?.notifications],
  );

  const handleSettingToggle = useCallback(
    (path: string[], checked: boolean) => {
      const key = path[0];
      if (key !== 'notifications' && key !== 'allow_group_invites') return;
      if (
        key === 'notifications' &&
        checked &&
        'Notification' in window &&
        Notification.permission === 'default'
      ) {
        void Notification.requestPermission();
      }
      setError(null);
      void api()
        .patch<ChatSettings>('/api/v1/chat/settings', {
          [key]: checked,
        })
        .then((response) => {
          setChatSettings((current) =>
            current ? { ...current, [key]: response.data[key] } : response.data,
          );
        })
        .catch(() => {
          setError('settings');
        });
    },
    [],
  );

  const postRoomAction = useCallback(
    (action: 'mute' | 'unmute' | 'archive' | 'unarchive') => {
      if (!conversationId) return;
      setError(null);
      void api()
        .post<ChatConversation | undefined>(
          `/api/v1/chat/conversations/${conversationId}/${action}`,
        )
        .then(({ data }) => {
          updateConversations((current) =>
            current.map((item) => {
              if (item.id !== conversationId) return item;
              if (action === 'mute' || action === 'unmute')
                return { ...item, muted: action === 'mute' };
              return data?.id === item.id ? data : item;
            }),
          );
          return loadConversationsForAction();
        })
        .catch(() => {
          setError('update');
        });
    },
    [conversationId, loadConversationsForAction, updateConversations],
  );

  const confirmArchive = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'CONFIRM',
        modalProps: {
          title: intl.formatMessage(messages.archiveConfirmTitle),
          message: intl.formatMessage(messages.archiveConfirm),
          confirm: intl.formatMessage(messages.archive),
          onConfirm: () => {
            postRoomAction('archive');
          },
        },
      }),
    );
  }, [dispatch, intl, postRoomAction]);

  const handleReopen = useCallback(() => {
    postRoomAction('unarchive');
  }, [postRoomAction]);

  const confirmThenLeave = useCallback(
    (path: string, title: string, message: string) => {
      dispatch(
        openModal({
          modalType: 'CONFIRM',
          modalProps: {
            title,
            message,
            confirm: title,
            onConfirm: () => {
              setError(null);
              void api()
                .delete(path)
                .then(() => {
                  navigateIfActive('/chat');
                })
                .catch(() => {
                  setError('update');
                });
            },
          },
        }),
      );
    },
    [dispatch, navigateIfActive],
  );

  const removeMember = useCallback(
    (member: ChatAccount) => {
      if (
        conversation?.type !== 'group' ||
        conversation.current_role !== 'owner' ||
        removingMemberId ||
        member.id === me
      )
        return;

      dispatch(
        openModal({
          modalType: 'CONFIRM',
          modalProps: {
            title: intl.formatMessage(
              {
                id: 'chat.remove_member_label',
                defaultMessage: 'Remove {name} from group',
              },
              { name: member.display_name || member.acct },
            ),
            message: intl.formatMessage(
              {
                id: 'chat.remove_member_confirm',
                defaultMessage:
                  'Remove {name} from this group? They will need another invitation to rejoin.',
              },
              { name: member.display_name || member.acct },
            ),
            confirm: intl.formatMessage({
              id: 'chat.remove_member',
              defaultMessage: 'Remove',
            }),
            onConfirm: () => {
              setError(null);
              setRemovingMemberId(member.id);
              void api()
                .delete<ChatConversation>(
                  `/api/v1/chat/conversations/${conversation.id}/members/${member.id}`,
                )
                .then(({ data }) => {
                  updateConversations((current) =>
                    current.map((item) => (item.id === data.id ? data : item)),
                  );
                })
                .catch(() => {
                  setError('remove_member');
                })
                .finally(() => {
                  setRemovingMemberId(null);
                });
            },
          },
        }),
      );
    },
    [conversation, dispatch, intl, removingMemberId, updateConversations],
  );

  const memberMenu = useCallback(
    (member: ChatAccount): MenuItem[] => [
      {
        text: intl.formatMessage(
          {
            id: 'chat.remove_member_label',
            defaultMessage: 'Remove {name} from group',
          },
          { name: member.display_name || member.acct },
        ),
        dangerous: true,
        action: () => {
          removeMember(member);
        },
      },
    ],
    [intl, removeMember],
  );

  const roomMenu = useMemo((): MenuItem[] => {
    if (!conversation) return [];
    const isGroup = conversation.type === 'group';
    const isOwner = isGroup && conversation.current_role === 'owner';
    const path = `/chat/${conversation.id}`;
    const endGroupTitle = isOwner
      ? intl.formatMessage({
          id: 'chat.delete_group',
          defaultMessage: 'Delete group',
        })
      : intl.formatMessage({
          id: 'chat.leave_group',
          defaultMessage: 'Leave group',
        });

    return [
      {
        text: conversation.muted
          ? intl.formatMessage({ id: 'chat.unmute', defaultMessage: 'Unmute' })
          : intl.formatMessage({ id: 'chat.mute', defaultMessage: 'Mute' }),
        action: () => {
          postRoomAction(conversation.muted ? 'unmute' : 'mute');
        },
      },
      ...(isGroup
        ? [
            {
              text: intl.formatMessage(
                { id: 'chat.members', defaultMessage: 'Members ({count})' },
                { count: conversation.accounts.length },
              ),
              to: `${path}/members`,
            },
          ]
        : []),
      ...(isOwner
        ? [
            {
              text: intl.formatMessage({
                id: 'chat.group_settings',
                defaultMessage: 'Group settings',
              }),
              to: `${path}/settings`,
            },
            {
              text: intl.formatMessage(
                conversation.archived ? messages.unarchive : messages.archive,
              ),
              action: conversation.archived ? handleReopen : confirmArchive,
            },
          ]
        : []),
      ...(isGroup && !(isOwner && roleplayMode)
        ? [
            null,
            {
              text: endGroupTitle,
              dangerous: true,
              action: () => {
                confirmThenLeave(
                  isOwner
                    ? `/api/v1/chat/conversations/${conversation.id}`
                    : `/api/v1/chat/conversations/${conversation.id}/leave`,
                  endGroupTitle,
                  intl.formatMessage(
                    isOwner
                      ? messages.deleteGroupConfirm
                      : {
                          id: 'chat.leave_group_confirm',
                          defaultMessage:
                            'Leave this group? You will need another invitation to rejoin.',
                        },
                  ),
                );
              },
            },
          ]
        : []),
    ];
  }, [
    confirmArchive,
    confirmThenLeave,
    conversation,
    handleReopen,
    intl,
    postRoomAction,
  ]);
  const handleOpenConversation = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.conversationId;
      if (id) history.push(`/chat/${id}`);
    },
    [history],
  );

  const handleTabChange = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const tab = event.currentTarget.dataset.tab as ChatHomeTab | undefined;
      if (tab) setActiveTab(tab);
    },
    [],
  );

  if (!signedIn) return <NotSignedInIndicator />;

  const visibleError = error ?? sendError;
  const errorNotice = (Boolean(visibleError) || readingError) &&
    !roomEnding && (
      <div className='chat-native__error' role='alert'>
        {visibleError === 'refused' ? (
          <FormattedMessage
            id='chat.error_refused'
            defaultMessage="This account can't receive this."
          />
        ) : visibleError === 'copy' ? (
          <FormattedMessage
            id='chat.error_copy'
            defaultMessage='The message could not be copied.'
          />
        ) : visibleError === 'too_many_attachments' ? (
          <FormattedMessage
            id='chat.error_too_many_attachments'
            defaultMessage='You can attach up to {max} files.'
            values={{ max: chatSettings?.max_attachments ?? 0 }}
          />
        ) : (
          <FormattedMessage
            id='chat.error'
            defaultMessage='The chat request could not be completed.'
          />
        )}
      </div>
    );
  const composerShown =
    Boolean(conversationId) && !conversationMissing && !isManagingRoom;

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='chat'
        iconComponent={ChatIcon}
        title={
          creating ? (
            intl.formatMessage(messages.newChat)
          ) : roomView === 'members' && conversation?.type === 'group' ? (
            intl.formatMessage(
              { id: 'chat.members', defaultMessage: 'Members ({count})' },
              { count: conversation.accounts.length },
            )
          ) : roomView === 'settings' && isGroupOwner ? (
            intl.formatMessage({
              id: 'chat.group_settings',
              defaultMessage: 'Group settings',
            })
          ) : conversation ? (
            <ConversationTitle conversation={conversation} linked />
          ) : (
            intl.formatMessage(messages.heading)
          )
        }
        multiColumn={multiColumn}
        showBackButton={Boolean(conversationId) || creating}
        onBack={conversationId || creating ? handleBack : undefined}
        extraButton={
          !conversationId && !creating ? (
            <>
              <button
                type='button'
                className={classNames('column-header__button', {
                  active: searchOpen,
                })}
                title={intl.formatMessage(messages.search)}
                aria-label={intl.formatMessage(messages.search)}
                aria-expanded={searchOpen}
                onClick={handleSearchToggle}
              >
                <Icon id='search' icon={SearchIcon} />
              </button>
              <Link
                to='/chat/new'
                className='column-header__button'
                title={intl.formatMessage(messages.newChat)}
                aria-label={intl.formatMessage(messages.newChat)}
              >
                <Icon id='plus' icon={AddIcon} />
              </Link>
            </>
          ) : conversation && !isManagingRoom ? (
            <Dropdown
              scrollKey='chat-room'
              items={roomMenu}
              title={intl.formatMessage(messages.more)}
            >
              <button
                type='button'
                className='column-header__button'
                title={intl.formatMessage(messages.more)}
                aria-label={intl.formatMessage(messages.more)}
              >
                <Icon id='ellipsis-h' icon={MoreHorizIcon} />
              </button>
            </Dropdown>
          ) : undefined
        }
      >
        {!conversationId && !creating && chatSettings && (
          <div className='column-settings chat-native-settings'>
            <section>
              <h3>{intl.formatMessage(messages.settings)}</h3>
              <SelectField
                label={
                  <FormattedMessage
                    id='chat.policy'
                    defaultMessage='Who can start a direct chat'
                  />
                }
                value={chatSettings.policy}
                onChange={handlePolicyChange}
              >
                <option value='everyone'>
                  {intl.formatMessage({
                    id: 'chat.policy.everyone',
                    defaultMessage: 'Everyone',
                  })}
                </option>
                <option value='followers'>
                  {intl.formatMessage({
                    id: 'chat.policy.followers',
                    defaultMessage: 'Followers',
                  })}
                </option>
                <option value='following'>
                  {intl.formatMessage({
                    id: 'chat.policy.following',
                    defaultMessage: 'People I follow',
                  })}
                </option>
                <option value='mutual'>
                  {intl.formatMessage({
                    id: 'chat.policy.mutuals',
                    defaultMessage: 'Mutual follows',
                  })}
                </option>
                <option value='none'>
                  {intl.formatMessage({
                    id: 'chat.policy.nobody',
                    defaultMessage: 'Nobody',
                  })}
                </option>
              </SelectField>
            </section>
            <section>
              <div className='column-settings__row'>
                <SettingToggle
                  prefix='chat'
                  settings={toggleSettings}
                  settingPath={['allow_group_invites']}
                  onChange={handleSettingToggle}
                  label={
                    <FormattedMessage
                      id='chat.allow_group_invites'
                      defaultMessage='Allow group invitations'
                    />
                  }
                />
                <SettingToggle
                  prefix='chat'
                  settings={toggleSettings}
                  settingPath={['notifications']}
                  onChange={handleSettingToggle}
                  label={
                    <FormattedMessage
                      id='chat.notifications'
                      defaultMessage='Notify me about new chat messages'
                    />
                  }
                />
              </div>
            </section>
          </div>
        )}
      </ColumnHeader>

      <div className='scrollable chat-native' onPaste={pastePlainText}>
        {conversationId && conversationMissing ? (
          roomEnding && (
            <div className='chat-native__empty'>
              <p>
                {roomEnding === 'deleted' ? (
                  <FormattedMessage
                    id='chat.room_deleted'
                    defaultMessage='This group was deleted.'
                  />
                ) : (
                  <FormattedMessage
                    id='chat.room_removed'
                    defaultMessage='You have left this group. An invitation is required to rejoin.'
                  />
                )}
              </p>
              <Link
                className='button chat-native__ended-back'
                to='/chat'
                onClick={handleBackToChats}
              >
                <FormattedMessage
                  id='chat.room_ended_back'
                  defaultMessage='Back to chats'
                />
              </Link>
            </div>
          )
        ) : conversationId ? (
          roomView === 'members' && conversation?.type === 'group' ? (
            <section className='chat-native__members'>
              {isGroupOwner && (
                <>
                  <form
                    className='chat-native__invite'
                    onSubmit={handleInviteSubmit}
                  >
                    <input
                      value={inviteAccountQuery}
                      onChange={handleInviteAccountQueryChange}
                      placeholder={intl.formatMessage(messages.accountSearch)}
                      disabled={conversation.archived}
                    />
                    <Button
                      type='submit'
                      disabled={conversation.archived || !inviteAccount}
                    >
                      <FormattedMessage
                        id='chat.invite'
                        defaultMessage='Invite'
                      />
                    </Button>
                    {inviteAccount && (
                      <div className='chat-native__selected-accounts'>
                        <SelectedAccountCard
                          account={inviteAccount}
                          onRemove={handleRemoveInviteAccount}
                        />
                      </div>
                    )}
                  </form>
                  {inviteAccountQuery.trim().length >= 2 && (
                    <AccountSearchNotice status={accountSearchStatus} />
                  )}
                  {inviteAccountResults.length > 0 && (
                    <div className='chat-native__account-results'>
                      {inviteAccountResults.map((account) => (
                        <ChatAccountRow
                          key={account.id}
                          account={account}
                          target={{
                            kind: 'button',
                            'data-account-id': account.id,
                            onClick: handleInviteAccountResult,
                          }}
                        />
                      ))}
                    </div>
                  )}
                </>
              )}
              {conversation.accounts.map((account) => (
                <ChatAccountRow
                  key={account.id}
                  className='chat-native__member'
                  account={account}
                  target={{ kind: 'profile' }}
                >
                  {isRemoteAccount(account) && (
                    <Badge
                      variant='subtle'
                      label={
                        <FormattedMessage
                          id='chat.remote'
                          defaultMessage='Remote'
                        />
                      }
                    />
                  )}
                  {isGroupOwner && account.id !== me && (
                    <Dropdown
                      scrollKey='chat-members'
                      icon='ellipsis-h'
                      iconComponent={MoreHorizIcon}
                      title={intl.formatMessage(messages.more)}
                      disabled={removingMemberId !== null}
                      items={memberMenu(account)}
                    />
                  )}
                </ChatAccountRow>
              ))}
              {shownSentInvitations.map(
                (invitation) =>
                  invitation.invitee && (
                    <PendingInvitationRow
                      key={invitation.id}
                      invitation={invitation}
                      invitee={invitation.invitee}
                      onCancel={cancelInvitation}
                    />
                  ),
              )}
            </section>
          ) : roomView === 'settings' && isGroupOwner ? (
            <section className='chat-native__group-settings'>
              <form
                className='chat-native__group-edit'
                onSubmit={handleGroupEditSubmit}
              >
                <input
                  name='search'
                  autoComplete='off'
                  value={
                    groupEdit?.conversationId === conversation.id
                      ? groupEdit.title
                      : (conversation.title ?? '')
                  }
                  onChange={handleGroupEditTitleChange}
                  placeholder={intl.formatMessage(messages.groupTitle)}
                  maxLength={256}
                  disabled={conversation.archived}
                />
                <textarea
                  name='search'
                  value={
                    groupEdit?.conversationId === conversation.id
                      ? groupEdit.description
                      : (conversation.description ?? '')
                  }
                  onChange={handleGroupEditDescriptionChange}
                  placeholder={intl.formatMessage({
                    id: 'chat.group_description',
                    defaultMessage: 'Group description',
                  })}
                  maxLength={2048}
                  disabled={conversation.archived}
                />
                <Button
                  type='submit'
                  disabled={
                    conversation.archived ||
                    !(
                      groupEdit?.conversationId === conversation.id
                        ? groupEdit.title
                        : (conversation.title ?? '')
                    ).trim()
                  }
                >
                  <FormattedMessage
                    id='chat.save_group'
                    defaultMessage='Save group details'
                  />
                </Button>
              </form>
            </section>
          ) : (
            <>
              {olderMessageId && (
                <LoadMore onClick={loadOlderMessages} loading={loadingMore} />
              )}
              <div
                className='chat-native__messages'
                ref={messagesListRef}
                {...longPress}
              >
                {conversation &&
                  messagesLoaded &&
                  messagesList.length === 0 &&
                  !olderMessageId && (
                    <div className='empty-column-indicator'>
                      <span>
                        <FormattedMessage
                          id='chat.no_messages'
                          defaultMessage='No messages yet.'
                        />
                        {!isArchived && !recipientSuspended && (
                          <>
                            {' '}
                            <FormattedMessage
                              id='chat.no_messages_send_first'
                              defaultMessage='Send the first one.'
                            />
                          </>
                        )}
                        {isGroupOwner && !isArchived && (
                          <>
                            <br />
                            <FormattedMessage
                              id='chat.no_messages_invites'
                              defaultMessage='People you invite join once they accept. You can see who hasn’t yet under Members in the ⋯ menu.'
                            />
                          </>
                        )}
                      </span>
                    </div>
                  )}
                {messagesList.map((message, index) => (
                  <Fragment key={message.id}>
                    {startsDay(messagesList, index) && (
                      <div className='chat-native__date'>
                        {intl.formatDate(message.created_at, {
                          year: 'numeric',
                          month: 'long',
                          day: 'numeric',
                          weekday: 'long',
                        })}
                      </div>
                    )}
                    <article
                      id={`chat-message-${message.id}`}
                      className={classNames('chat-native__message', {
                        'chat-native__message--highlighted':
                          message.id === jumpTargetId,
                        'chat-native__message--mine': message.account.id === me,
                        'chat-native__message--continued': !startsRun(
                          messagesList,
                          index,
                        ),
                      })}
                    >
                      {message.account.id !== me &&
                        (startsRun(messagesList, index) ? (
                          <ChatAvatar account={message.account} withLink />
                        ) : (
                          <span className='chat-native__avatar-space' />
                        ))}
                      <div className='chat-native__message-content'>
                        {message.account.id !== me &&
                          startsRun(messagesList, index) && (
                            <strong>
                              <ChatDisplayName account={message.account} />
                            </strong>
                          )}
                        <div className='chat-native__bubble-wrap'>
                          <div className='chat-native__bubble' tabIndex={-1}>
                            {message.reply_to_id && !message.deleted_at && (
                              <ReplyQuote
                                messageId={message.reply_to_id}
                                target={messagesById.get(message.reply_to_id)}
                                onClick={handleReplyQuoteClick}
                              />
                            )}
                            <p>
                              {message.deleted_at ? (
                                <FormattedMessage
                                  id='chat.message_deleted'
                                  defaultMessage='This message was deleted.'
                                />
                              ) : (
                                <EmojiText
                                  text={message.content ?? ''}
                                  emojis={message.emojis}
                                />
                              )}
                            </p>
                            <ChatMessageMedia
                              attachments={message.media_attachments}
                              onOpenMedia={handleOpenMedia}
                            />
                          </div>
                          {!message.deleted_at &&
                            (!isArchived || hasText(message)) && (
                              <div className='chat-native__actions-rail'>
                                <div className='chat-native__actions'>
                                  {!isArchived && (
                                    <MessageActionButton
                                      messageId={message.id}
                                      action='reply'
                                      title={intl.formatMessage(messages.reply)}
                                      icon={ReplyIcon}
                                      onAction={handleMessageAction}
                                    />
                                  )}
                                  {!isArchived && message.account.id !== me && (
                                    <span className='chat-native__react-picker'>
                                      <ChatEmojiPicker
                                        messageId={message.id}
                                        onPick={handleEmojiPick}
                                      />
                                    </span>
                                  )}
                                  {!isArchived &&
                                    message.account.id === me &&
                                    message.editable !== false && (
                                      <MessageActionButton
                                        messageId={message.id}
                                        action='edit'
                                        title={intl.formatMessage(
                                          messages.edit,
                                        )}
                                        icon={EditIcon}
                                        onAction={handleMessageAction}
                                      />
                                    )}
                                  {hasText(message) && (
                                    <MessageActionButton
                                      messageId={message.id}
                                      action='copy'
                                      title={intl.formatMessage(messages.copy)}
                                      icon={ContentCopyIcon}
                                      onAction={handleMessageAction}
                                    />
                                  )}
                                  {!isArchived && message.account.id === me && (
                                    <MessageActionButton
                                      messageId={message.id}
                                      action='delete'
                                      title={intl.formatMessage(
                                        messages.delete,
                                      )}
                                      icon={DeleteIcon}
                                      onAction={handleMessageAction}
                                    />
                                  )}
                                </div>
                              </div>
                            )}
                        </div>
                        {message.reactions.length > 0 && (
                          <MessageReactions
                            messageId={message.id}
                            reactions={message.reactions}
                            canReact={!isArchived && message.account.id !== me}
                            onRemove={handleReactionClick}
                            onAdd={handleEmojiPick}
                          />
                        )}
                        <div className='chat-native__message-footer'>
                          {endsRun(messagesList, index) && (
                            <time
                              dateTime={message.created_at}
                              title={new Date(
                                message.created_at,
                              ).toLocaleString()}
                            >
                              {intl.formatTime(message.created_at, {
                                hour: 'numeric',
                                minute: '2-digit',
                              })}
                            </time>
                          )}
                          {message.edited_at && !message.deleted_at && (
                            <span className='chat-native__edited'>
                              <FormattedMessage
                                id='chat.message_edited'
                                defaultMessage='Edited'
                              />
                            </span>
                          )}
                        </div>
                      </div>
                    </article>
                  </Fragment>
                ))}
              </div>
              {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
              <form
                className='chat-native__composer'
                ref={composerRef}
                onSubmit={handleComposerSubmit}
                onMouseDown={handleComposerMouseDown}
              >
                {errorNotice}
                <JumpToNewestButton
                  state={jumpButton}
                  onClick={handleJumpToNewest}
                />
                {conversation?.archived && (
                  <div className='chat-native__notice'>
                    <span>
                      <FormattedMessage
                        id='chat.archived'
                        defaultMessage='This group is archived.'
                      />
                    </span>
                    {isGroupOwner && (
                      <button type='button' onClick={handleReopen}>
                        {intl.formatMessage(messages.unarchive)}
                      </button>
                    )}
                  </div>
                )}
                {recipientSuspended && (
                  <div className='chat-native__notice'>
                    <FormattedMessage
                      id='chat.recipient_suspended'
                      defaultMessage='This account is suspended.'
                    />
                  </div>
                )}
                {(replyToId ?? editingId) && (
                  <div className='chat-native__compose-mode'>
                    {editingId ? (
                      <FormattedMessage
                        id='chat.editing'
                        defaultMessage='Editing message'
                      />
                    ) : (
                      <div>
                        <span>
                          {replyTarget ? (
                            <FormattedMessage
                              id='chat.replying_to'
                              defaultMessage='Replying to {account}'
                              values={{
                                account: (
                                  <ChatDisplayName
                                    account={replyTarget.account}
                                  />
                                ),
                              }}
                            />
                          ) : (
                            <FormattedMessage
                              id='chat.replying'
                              defaultMessage='Replying to message'
                            />
                          )}
                        </span>
                        <span>
                          {replyTarget && !replyTarget.deleted_at ? (
                            <EmojiText
                              text={replyTarget.content ?? ''}
                              emojis={replyTarget.emojis}
                            />
                          ) : (
                            intl.formatMessage({
                              id: 'chat.message_deleted',
                              defaultMessage: 'This message was deleted.',
                            })
                          )}
                        </span>
                      </div>
                    )}
                    <button type='button' onClick={handleCancelComposeMode}>
                      <FormattedMessage
                        id='chat.cancel'
                        defaultMessage='Cancel'
                      />
                    </button>
                  </div>
                )}
                {composerMedia.length > 0 && (
                  <div className='chat-native__media-preview'>
                    {composerMedia.map((attachment) => (
                      <div key={attachment.id}>
                        {attachment.type === 'audio' && attachment.url ? (
                          <audio controls src={attachment.url} />
                        ) : (attachment.type === 'video' ||
                            attachment.type === 'gifv') &&
                          attachment.url ? (
                          <video
                            controls
                            src={attachment.url}
                            poster={attachment.preview_url ?? undefined}
                          />
                        ) : (
                          <img
                            src={attachment.preview_url ?? attachment.url ?? ''}
                            alt={attachment.description ?? ''}
                          />
                        )}
                        <button
                          type='button'
                          data-media-id={attachment.id}
                          onClick={handleRemoveMedia}
                        >
                          <FormattedMessage
                            id='chat.remove_attachment'
                            defaultMessage='Remove attachment'
                          />
                        </button>
                      </div>
                    ))}
                  </div>
                )}
                <div className='chat-native__compose-field'>
                  <IconButton
                    title={intl.formatMessage(messages.attach)}
                    icon='photo'
                    iconComponent={PhotoLibraryIcon}
                    onClick={handleAttachClick}
                    disabled={
                      loading ||
                      uploading ||
                      Boolean(editingId) ||
                      Boolean(conversation?.archived) ||
                      !chatSettings ||
                      media.length >= chatSettings.max_attachments
                    }
                  />
                  <input
                    ref={fileInputRef}
                    type='file'
                    hidden
                    multiple
                    onChange={handleMediaChange}
                    accept='image/*,video/*,audio/*'
                  />
                  <ComposerBox
                    text={composerText}
                    onKeyDown={handleComposerKeyDown}
                    onPaste={handleComposerPaste}
                    placeholder={intl.formatMessage(messages.placeholder)}
                    disabled={isArchived}
                  />
                </div>
                <ComposerTooLongNotice text={composerText} />
                <ComposerSendButton
                  text={composerText}
                  hasOtherContent={hasOtherContent}
                  disabled={
                    Boolean(conversation?.archived) ||
                    recipientSuspended ||
                    loading ||
                    uploading ||
                    composerMedia.some((item) => !item.url)
                  }
                  label={intl.formatMessage(
                    editingId ? messages.save : messages.send,
                  )}
                />
              </form>
              <div className='chat-native__end' ref={messagesEndRef} />
            </>
          )
        ) : creating ? (
          <>
            <div className='account__section-headline chat-native__new-modes'>
              <button
                type='button'
                data-mode='direct'
                className={classNames({ active: newChatMode === 'direct' })}
                aria-pressed={newChatMode === 'direct'}
                onClick={handleNewChatMode}
              >
                {intl.formatMessage(messages.newDirect)}
              </button>
              <button
                type='button'
                data-mode='group'
                className={classNames({ active: newChatMode === 'group' })}
                aria-pressed={newChatMode === 'group'}
                onClick={handleNewChatMode}
              >
                {intl.formatMessage(messages.newGroup)}
              </button>
            </div>
            <section id='chat-new-panel' className='chat-native__new-panel'>
              {newChatMode === 'direct' ? (
                <>
                  <form
                    className='chat-native__new'
                    onSubmit={handleDirectSubmit}
                  >
                    <div className='chat-native__form-row'>
                      <input
                        value={directAccountQuery}
                        onChange={handleDirectAccountQueryChange}
                        placeholder={intl.formatMessage(messages.accountSearch)}
                      />
                      <Button
                        type='submit'
                        disabled={loading || !directAccount}
                      >
                        {intl.formatMessage(messages.open)}
                      </Button>
                    </div>
                    {directAccount && (
                      <div className='chat-native__selected-accounts'>
                        <SelectedAccountCard
                          account={directAccount}
                          onRemove={handleRemoveDirectAccount}
                        />
                      </div>
                    )}
                  </form>
                  {directAccountQuery.trim().length >= 2 && (
                    <AccountSearchNotice status={accountSearchStatus} />
                  )}
                  {accountResults.length > 0 && (
                    <div className='chat-native__account-results'>
                      {accountResults.map((account) => (
                        <ChatAccountRow
                          key={account.id}
                          account={account}
                          target={{
                            kind: 'button',
                            'data-account-id': account.id,
                            onClick: handleAccountResult,
                          }}
                        />
                      ))}
                    </div>
                  )}
                </>
              ) : (
                <>
                  <form
                    className='chat-native__new'
                    onSubmit={handleGroupSubmit}
                  >
                    <div className='chat-native__form-row'>
                      <input
                        name='search'
                        autoComplete='off'
                        value={groupTitle}
                        onChange={handleGroupTitleChange}
                        placeholder={intl.formatMessage(messages.groupTitle)}
                      />
                    </div>
                    <div className='chat-native__form-row'>
                      <input
                        name='search'
                        autoComplete='off'
                        value={groupAccountQuery}
                        onChange={handleGroupAccountQueryChange}
                        placeholder={intl.formatMessage(messages.accountSearch)}
                      />
                      <Button
                        type='submit'
                        disabled={loading || !groupTitle.trim()}
                      >
                        {intl.formatMessage(messages.create)}
                      </Button>
                    </div>
                    {groupAccounts.length > 0 && (
                      <div className='chat-native__selected-accounts'>
                        {groupAccounts.map((account) => (
                          <SelectedAccountCard
                            key={account.id}
                            account={account}
                            onRemove={handleRemoveGroupAccount}
                          />
                        ))}
                      </div>
                    )}
                  </form>
                  {groupAccountQuery.trim().length >= 2 && (
                    <AccountSearchNotice status={accountSearchStatus} />
                  )}
                  {groupAccountResults.length > 0 && (
                    <div className='chat-native__account-results'>
                      {groupAccountResults.map((account) => (
                        <ChatAccountRow
                          key={account.id}
                          account={account}
                          target={{
                            kind: 'button',
                            'data-account-id': account.id,
                            onClick: handleGroupAccountResult,
                          }}
                        />
                      ))}
                    </div>
                  )}
                </>
              )}
            </section>
          </>
        ) : (
          <>
            <nav
              className='account__section-headline chat-native__tabs'
              aria-label={intl.formatMessage(messages.heading)}
            >
              {(
                [
                  ['home', HomeIcon, messages.tabHome],
                  ['invitations', GroupIcon, messages.tabInvitations],
                  ['joiningRooms', GroupsIcon, messages.tabJoiningRooms],
                  ['ownedRooms', SettingsIcon, messages.tabOwnedRooms],
                ] as const
              ).map(([tab, icon, tabMessage]) => (
                <button
                  key={tab}
                  type='button'
                  data-tab={tab}
                  className={activeTab === tab ? 'active' : undefined}
                  aria-current={activeTab === tab ? 'page' : undefined}
                  onClick={handleTabChange}
                >
                  <span>{intl.formatMessage(tabMessage)}</span>
                  <IconWithBadge
                    id={tab}
                    icon={icon}
                    count={tab === 'invitations' ? invitations.length : 0}
                    className=''
                  />
                </button>
              ))}
            </nav>
            {activeTab === 'invitations' && invitations.length > 0 && (
              <section className='chat-native__invitations'>
                {invitations.map((invitation) => (
                  <InvitationRow
                    key={invitation.id}
                    invitation={invitation}
                    onAnswer={answerInvitation}
                  />
                ))}
              </section>
            )}
            {activeTab === 'invitations' && invitations.length === 0 && (
              <div className='chat-native__empty'>
                <FormattedMessage
                  id='chat.no_invitations'
                  defaultMessage='You have no chat invitations.'
                />
              </div>
            )}
            {searchOpen && (
              <>
                <div className='chat-native__toolbar'>
                  <form
                    className='chat-native__search'
                    role='search'
                    onSubmit={handleSearchSubmit}
                  >
                    <Icon id='search' icon={SearchIcon} />
                    <input
                      ref={searchInputRef}
                      type='search'
                      name='search'
                      autoComplete='off'
                      value={searchQuery}
                      onChange={handleSearchChange}
                      placeholder={intl.formatMessage(messages.search)}
                      aria-label={intl.formatMessage(messages.search)}
                    />
                  </form>
                </div>
                {searchedQuery && searchResults.length === 0 && (
                  <div className='chat-native__empty'>
                    <FormattedMessage
                      id='chat.search_no_results'
                      defaultMessage='No messages found.'
                    />
                  </div>
                )}
                {searchResults.length > 0 && (
                  <div className='chat-native__search-results'>
                    {searchResults.map((result) => (
                      <ChatAccountRow
                        key={result.id}
                        account={result.account}
                        target={{
                          kind: 'button',
                          'data-conversation-id': result.conversation_id,
                          'data-message-id': result.id,
                          onClick: handleSearchResult,
                        }}
                        details={
                          <EmojiText
                            text={result.content ?? ''}
                            emojis={result.emojis}
                          />
                        }
                      />
                    ))}
                  </div>
                )}
              </>
            )}
            {activeTab !== 'invitations' && (
              <div className='chat-native__conversations'>
                {visibleConversations.map((item) => (
                  <button
                    key={item.id}
                    type='button'
                    className={classNames(
                      'conversation focusable chat-native__conversation',
                      { unread: item.unread },
                    )}
                    data-conversation-id={item.id}
                    onClick={handleOpenConversation}
                  >
                    <span className='conversation__avatar'>
                      <ConversationPicture conversation={item} size={48} />
                    </span>
                    <span className='conversation__content'>
                      <span className='conversation__content__info'>
                        <span className='conversation__content__relative-time'>
                          {item.unread && (
                            <span
                              className='conversation__unread'
                              role='img'
                              aria-label={intl.formatMessage(messages.unread)}
                            />
                          )}
                          {item.last_message && (
                            <RelativeTimestamp
                              timestamp={item.last_message.created_at}
                            />
                          )}
                        </span>
                        <span className='conversation__content__names'>
                          <ConversationTitle conversation={item} />
                        </span>
                      </span>
                      <span className='chat-native__conversation-preview'>
                        {item.archived && (
                          <Badge
                            variant='subtle'
                            label={
                              <FormattedMessage
                                id='chat.archived_badge'
                                defaultMessage='Archived'
                              />
                            }
                          />
                        )}
                        {item.last_message?.content && (
                          <EmojiText
                            text={item.last_message.content}
                            emojis={item.last_message.emojis}
                          />
                        )}
                      </span>
                    </span>
                  </button>
                ))}
                {nextConversationId && (
                  <LoadMore
                    onClick={loadMoreConversations}
                    loading={loadingMore}
                  />
                )}
                {conversationsLoaded && visibleConversations.length === 0 && (
                  <div className='chat-native__empty'>
                    {activeTab === 'home' ? (
                      <FormattedMessage
                        id='chat.no_history'
                        defaultMessage='You have no chat history yet.'
                      />
                    ) : (
                      <FormattedMessage
                        id='chat.no_rooms'
                        defaultMessage='There are no groups here.'
                      />
                    )}
                  </div>
                )}
              </div>
            )}
          </>
        )}
        {!composerShown && errorNotice}
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};
