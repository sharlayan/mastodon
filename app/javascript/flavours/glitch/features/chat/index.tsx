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
  KeyboardEvent,
  MouseEvent,
  SyntheticEvent,
  TouchEvent,
} from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useHistory, useLocation, useParams } from 'react-router-dom';

import type { List as ImmutableList } from 'immutable';
import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';
import Textarea from 'react-textarea-autosize';

import PhotoLibraryIcon from '@/material-icons/400-20px/photo_library.svg?react';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ChatIcon from '@/material-icons/400-24px/chat.svg?react';
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
import { compareId } from 'flavours/glitch/compare_id';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Button } from 'flavours/glitch/components/button';
import { CircularProgress } from 'flavours/glitch/components/circular_progress';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import type { IconProp } from 'flavours/glitch/components/icon';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadMore } from 'flavours/glitch/components/load_more';
import MediaGallery from 'flavours/glitch/components/media_gallery';
import { NotSignedInIndicator } from 'flavours/glitch/components/not_signed_in_indicator';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import { useIdentity } from 'flavours/glitch/identity_context';
import { me } from 'flavours/glitch/initial_state';
import type { MenuItem } from 'flavours/glitch/models/dropdown_menu';
import { useAppDispatch } from 'flavours/glitch/store';

import { createRetries } from './retry';
import type { PageCheckpoint } from './retry';
import {
  CHAT_STREAM_RECONNECTED,
  isChatStreamLive,
  subscribeChatStream,
} from './stream';

interface ChatAccount {
  id: string;
  acct: string;
  display_name: string;
  avatar: string;
  avatar_static: string;
  suspended?: boolean;
}

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
  editable?: boolean;
  deletes_for_everyone?: boolean;
}

type MessageUpdate = (messages: ChatMessage[]) => ChatMessage[];
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

// A room's read mark that has yet to reach the server.
interface ReadMark {
  // The newest message the reader has actually reached.
  upTo: string;
  // What the request on its way marks, while one is.
  sending?: string;
  // Asked for again while a request was on its way, for more than it marks.
  again: boolean;
}

// A room change remounts the screen, but a server's deadline belongs to the account.
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

// The picture is not a link: these names sit inside buttons, and a button cannot hold a link.
const AccountSummary: React.FC<{
  account: ChatAccount;
  detail?: string;
}> = ({ account, detail }) => (
  <>
    <Avatar account={account} size={36} />
    <span className='chat-native__account-names'>
      <strong>{account.display_name || account.acct}</strong>
      <span title={detail === undefined ? `@${account.acct}` : undefined}>
        {detail ?? `@${account.acct}`}
      </span>
    </span>
  </>
);

const directPartner = (conversation: ChatConversation) =>
  conversation.type === 'direct'
    ? conversation.accounts.find((account) => account.id !== me)
    : undefined;

// A name alone cannot tell apart two people on different servers. The address is cut off when it does not fit, so the
// whole of it is in its title, and in the profile it links to where nothing can be hovered over.
const ConversationTitle: React.FC<{
  conversation: ChatConversation;
  linked?: boolean;
}> = ({ conversation, linked = false }) => {
  const partner = directPartner(conversation);
  if (conversation.title || !partner?.display_name) {
    const name = conversationName(conversation);
    return linked ? name : <strong>{name}</strong>;
  }

  const address = `@${partner.acct}`;
  const Title = linked ? 'span' : 'strong';
  return (
    <Title className='chat-native__conversation-title'>
      <span>{partner.display_name}</span>
      {linked ? (
        <Link
          to={`/${address}`}
          title={address}
          data-hover-card-account={partner.id}
        >
          {address}
        </Link>
      ) : (
        <span title={address}>{address}</span>
      )}
    </Title>
  );
};

// A group has no one person to show, but its row still lines up with the direct chats.
const ConversationPicture: React.FC<{ conversation: ChatConversation }> = ({
  conversation,
}) => {
  const other = directPartner(conversation);

  return other ? (
    <Avatar account={other} size={36} />
  ) : (
    <span className='chat-native__room-picture'>
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

export const upsertConversation = (
  list: ChatConversation[],
  conversation: ChatConversation,
) => {
  if (list.some((item) => item.id === conversation.id))
    return list.map((item) =>
      item.id === conversation.id ? conversation : item,
    );
  const position = list.findIndex(
    (item) => compareConversations(conversation, item) < 0,
  );
  return position === -1
    ? [...list, conversation]
    : [...list.slice(0, position), conversation, ...list.slice(position)];
};

export const withNewMessage = (
  list: ChatConversation[],
  message: ChatMessage,
  unread: boolean,
) => {
  const conversation = list.find((item) => item.id === message.conversation_id);
  if (!conversation) return list;
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

// The API gives a page of these at a time, and the members screen has to show them all.
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

const waitForMedia = async (media: ChatMedia): Promise<ChatMedia> => {
  if (media.url) return media;

  for (let attempt = 0; attempt < 30; attempt += 1) {
    const response = await api().get<ChatMedia>(`/api/v1/media/${media.id}`);
    if (response.data.url) return response.data;
    await new Promise((resolve) => {
      window.setTimeout(resolve, 1000);
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
    <div className='chat-native__invitation'>
      <Avatar account={invitation.inviter} size={36} />
      <div className='chat-native__account-names'>
        <strong>{conversationName(invitation.conversation)}</strong>
        <span>
          <FormattedMessage
            id='chat.invited_by'
            defaultMessage='Invited by {name}'
            values={{
              name: invitation.inviter.display_name || invitation.inviter.acct,
            }}
          />
        </span>
      </div>
      <div className='account__relationship'>
        <Button compact onClick={handleAccept}>
          <FormattedMessage id='chat.accept' defaultMessage='Accept' />
        </Button>
        <Button compact secondary onClick={handleReject}>
          <FormattedMessage id='chat.reject' defaultMessage='Reject' />
        </Button>
      </div>
    </div>
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
    <div className='chat-native__member'>
      <Avatar account={invitee} size={36} withLink />
      <div>
        <strong>{invitee.display_name || invitee.acct}</strong>
        <span title={`@${invitee.acct}`}>@{invitee.acct}</span>
      </div>
      <small className='chat-native__state-badge'>
        <FormattedMessage
          id='chat.invitation_pending'
          defaultMessage='Invited'
        />
      </small>
      <Button compact secondary onClick={handleCancel}>
        <FormattedMessage
          id='chat.cancel_invitation'
          defaultMessage='Cancel invitation'
        />
      </Button>
    </div>
  );
};

type MessageAction = 'reply' | 'edit' | 'copy' | 'delete';

const hasText = (message: ChatMessage) => Boolean(message.content?.trim());

// Being async turns a browser without a clipboard into a failed copy, like one that refuses.
const writeToClipboard = async (text: string) => {
  await navigator.clipboard.writeText(text);
};

// On a Mac, Home and End scroll instead of moving the caret. What the box has no room left to scroll goes on to the
// conversation, which jumps to its first or last message from wherever it was being read.
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

const LONG_PRESS_MS = 500;
const LONG_PRESS_MOVE_PX = 10;

// Android Chrome reveals the toolbar by itself on a long press, and iOS Safari does not. Nothing else there would
// answer the finger now that the text cannot be selected, so a long press opens it on every browser.
// A picture keeps its browser menu: it is left alone.
const useLongPressOpensToolbar = () => {
  const press = useRef<{ timer: number; x: number; y: number } | null>(null);

  const cancel = useCallback(() => {
    if (press.current) window.clearTimeout(press.current.timer);
    press.current = null;
  }, []);

  useEffect(() => cancel, [cancel]);

  const onTouchStart = useCallback(
    (event: TouchEvent<HTMLElement>) => {
      cancel();
      const touch = event.touches[0];
      const target = event.target as Element;
      const bubble = target.closest<HTMLElement>('.chat-native__bubble');
      if (
        !touch ||
        event.touches.length > 1 ||
        !bubble ||
        target.closest('.chat-native__gallery, .chat-native__attachment')
      )
        return;

      press.current = {
        x: touch.clientX,
        y: touch.clientY,
        timer: window.setTimeout(() => {
          press.current = null;
          bubble.focus({ preventScroll: true });
        }, LONG_PRESS_MS),
      };
    },
    [cancel],
  );

  const onTouchMove = useCallback(
    (event: TouchEvent<HTMLElement>) => {
      const touch = event.touches[0];
      if (
        press.current &&
        touch &&
        Math.hypot(
          touch.clientX - press.current.x,
          touch.clientY - press.current.y,
        ) > LONG_PRESS_MOVE_PX
      )
        cancel();
    },
    [cancel],
  );

  return {
    onTouchStart,
    onTouchMove,
    onTouchEnd: cancel,
    onTouchCancel: cancel,
  };
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
        <strong>{target.account.display_name || target.account.acct}</strong>
        <span>
          {target.deleted_at ? (
            <FormattedMessage
              id='chat.message_deleted'
              defaultMessage='This message was deleted.'
            />
          ) : (
            target.content
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

const FOLLOW_NEWEST_DISTANCE = 240;
const MESSAGE_PAGE_SIZE = 40;
const MESSAGE_RESYNC_PAGES = 25;
const HIGHLIGHT_DURATION_MS = 3000;

const usesTouchKeyboard = () =>
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(pointer: coarse)').matches;

const scrollToNewest = (end: HTMLElement | null) => {
  if (typeof end?.scrollIntoView === 'function') {
    end.scrollIntoView({ block: 'end' });
  }
};

// For what changes while the reader scrolls or types. Kept in the room's own state, it would draw every message again
// each time, which a slow phone shows as a stutter. Only what shows it follows it.
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

const ComposerBox: React.FC<{
  text: ComposerText;
  onKeyDown: (event: KeyboardEvent<HTMLTextAreaElement>) => void;
  placeholder: string;
  disabled: boolean;
}> = ({ text, onKeyDown, placeholder, disabled }) => {
  const value = useSyncExternalStore(text.subscribe, text.get);
  const handleChange = useCallback(
    (event: ChangeEvent<HTMLTextAreaElement>) => {
      text.set(event.target.value);
    },
    [text],
  );

  return (
    <Textarea
      // iOS 27 Safari reads an address in the text around a box (one letter of Korean is enough)
      // and offers contacts' addresses in place of words; autocomplete="off" does not stop it.
      name='search'
      minRows={1}
      maxRows={6}
      value={value}
      onChange={handleChange}
      onKeyDown={onKeyDown}
      placeholder={placeholder}
      disabled={disabled}
    />
  );
};

const ComposerTooLongNotice: React.FC<{ text: ComposerText }> = ({ text }) => {
  // Stays at zero while the message fits, so that a letter typed draws nothing here.
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

  return (
    <ChatSession key={conversationId ?? 'home'} multiColumn={multiColumn} />
  );
};

const ChatSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const history = useHistory();
  const location = useLocation<{ chatMessageId?: string } | undefined>();
  const [jumpTargetId, setJumpTargetId] = useState<string | null>(
    location.state?.chatMessageId ?? null,
  );
  const dispatch = useAppDispatch();
  const { conversationId: routeId, view: roomView } = useParams<{
    conversationId?: string;
    view?: string;
  }>();
  const creating = routeId === 'new';
  const conversationId = creating ? undefined : routeId;
  const { signedIn } = useIdentity();
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [nextConversationId, setNextConversationId] = useState<string | null>(
    null,
  );
  const [olderMessageId, setOlderMessageId] = useState<string | null>(null);
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
  const [draftBeforeEdit, setDraftBeforeEdit] = useState<{
    text: string;
    media: ChatMedia[];
  } | null>(null);
  const deletedMessages = useRef(new Map<string, string>());
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const scrolledConversationIdRef = useRef<string | undefined>(undefined);
  const messagesListRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const composerRef = useRef<HTMLFormElement>(null);
  const followingNewestRef = useRef(true);
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
  useEffect(() => {
    if (conversationsLoaded)
      knownConversationIds.current = new Set(
        conversations.map((item) => item.id),
      );
  }, [conversations, conversationsLoaded]);

  const pendingMessageUpdates = useRef(new Set<MessageUpdate[]>());
  const latestMessageRequest = useRef(0);
  const shownMessagesRef = useRef<ChatMessage[]>([]);
  useEffect(() => {
    shownMessagesRef.current = messagesList;
  }, [messagesList]);
  const conversationPages = useRef(1);
  const latestConversationRequest = useRef(0);
  const updateMessages = useCallback((update: MessageUpdate) => {
    pendingMessageUpdates.current.forEach((updates) => updates.push(update));
    setMessagesList(update);
  }, []);
  const pendingConversationUpdates = useRef(new Set<ConversationUpdate[]>());
  const updateConversations = useCallback((update: ConversationUpdate) => {
    pendingConversationUpdates.current.forEach((updates) =>
      updates.push(update),
    );
    setConversations(update);
  }, []);

  // What the screen asked for on opening and has no answer to yet.
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

  // What the screen asks for by itself is tried again by the screen, not only when the stream
  // comes back: the stream may have come back, and said so, before this screen was there.
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

  // Reads the screen made by itself that failed, and that reading again can make up for.
  // Unlike marking a room read, what they bring is missing from the screen, so that is said.
  const failedReads = useRef(new Set<string>());
  const readFailed = useCallback((read: string) => {
    failedReads.current.add(read);
    setReadingError(true);
  }, []);
  const readRecovered = useCallback((read: string) => {
    failedReads.current.delete(read);
    if (failedReads.current.size === 0) setReadingError(false);
  }, []);

  // Marking a room read is never asked for by hand. As with the timelines' read markers
  // (actions/markers.ts), a failure is not shown: the room stays unread here, and the mark is
  // sent again, by itself a few times, and after that on the next occasion for it.
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
      // The try planned next takes this along.
      if (mark.sending === undefined) return;
      // One is on its way; another goes after it unless it already covers this.
      const covered = compareId(asked, mark.sending) <= 0;
      if (!covered) {
        mark.again = true;
        // Let the retry scheduler check visibility before the next request.
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

  // The newest message up to which nothing is missing, going by what the server answered
  // and what the live stream brought. The screen can hold newer ones with a gap before
  // them: what was sent from here, or what arrived before the server had subscribed.
  const continuousUpTo = useRef<string | undefined>(undefined);
  // The stream only follows on from what was read after it went live.
  const readSinceStreamWentLive = useRef(false);
  const advanceContinuousUpTo = useCallback((id?: string) => {
    if (
      id &&
      (!continuousUpTo.current || compareId(id, continuousUpTo.current) > 0)
    )
      continuousUpTo.current = id;
  }, []);

  // What came in while the reader was further up, which they have not read until they are back down.
  const unreadWhileAway = useRef(false);

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
    isMounted.current = true;
    return () => {
      isMounted.current = false;
    };
  }, []);

  const navigateIfActive = useCallback(
    (path: string) => {
      if (isMounted.current) history.push(path);
    },
    [history],
  );

  const loadConversations = useCallback(
    async (nextPage: PageCheckpoint) => {
      const requestId = ++latestConversationRequest.current;
      const updates: ConversationUpdate[] = [];
      pendingConversationUpdates.current.add(updates);
      const loaded: ChatConversation[] = [];
      let cursor: string | null = null;
      let missing = false;
      let ending: RoomEnding | null = null;
      try {
        for (let page = 0; page < conversationPages.current; page++) {
          if (page > 0 && !(await nextPage())) return false;
          const { data }: { data: ChatConversation[] } = await api().get<
            ChatConversation[]
          >(
            '/api/v1/chat/conversations',
            cursor ? { params: { max_id: cursor } } : undefined,
          );
          loaded.push(...data);
          cursor = data.length === 20 ? (data.at(-1)?.id ?? null) : null;
          if (!cursor) break;
        }
        if (
          conversationId &&
          !loaded.some((item) => item.id === conversationId)
        ) {
          if (!(await nextPage())) return false;
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
      } finally {
        pendingConversationUpdates.current.delete(updates);
      }
      if (requestId !== latestConversationRequest.current) return;
      setNextConversationId(cursor);
      setConversationMissing(missing);
      setRoomEnding(ending);
      if (missing && !ending) setError('load');
      setConversations(
        updates.reduce((items, update) => update(items), loaded),
      );
      setConversationsLoaded(true);
      return true;
    },
    [conversationId],
  );

  const loadConversationsForAction = useCallback(
    () => retries.runPages('conversations', loadConversations),
    [loadConversations, retries],
  );

  const refreshConversations = useCallback(() => {
    loadConversationsForAction().catch(() => {
      setError('load');
    });
  }, [loadConversationsForAction]);

  const refreshConversation = useCallback(
    (id: string) => {
      // Bursts share a plan, and the scheduler checks the page before a follow-up.
      void retries
        .keepTrying(`conversation:${id}`, async () => {
          try {
            const { data } = await api().get<ChatConversation>(
              `/api/v1/chat/conversations/${id}`,
            );
            updateConversations((current) => upsertConversation(current, data));
          } catch (loadError) {
            if (isNotFound(loadError))
              updateConversations((current) =>
                current.filter((item) => item.id !== id),
              );
            else if (
              (loadError as { response?: { status?: number } } | null)?.response
                ?.status === 429
            )
              throw loadError;
          }
        })
        .catch(() => undefined);
    },
    [retries, updateConversations],
  );

  const loadMoreConversations = useCallback(() => {
    if (!nextConversationId || loadingMore) return;
    setLoadingMore(true);
    void api()
      .get<ChatConversation[]>('/api/v1/chat/conversations', {
        params: { max_id: nextConversationId },
      })
      .then(({ data }) => {
        conversationPages.current += 1;
        updateConversations((current) => [
          ...current,
          ...data.filter(
            (item) => !current.some((existing) => existing.id === item.id),
          ),
        ]);
        setNextConversationId(
          data.length === 20 ? (data.at(-1)?.id ?? null) : null,
        );
      })
      .catch(() => {
        setError('load');
      })
      .finally(() => {
        setLoadingMore(false);
      });
  }, [loadingMore, nextConversationId, updateConversations]);

  const loadInvitations = useCallback(async () => {
    const response = await api().get<ChatInvitation[]>(
      '/api/v1/chat/invitations',
    );
    setInvitations(response.data);
  }, []);

  // Whether what it read is what the screen shows: a newer read can take over.
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
    setOlderMessageId(
      response.data.length === 40 ? (response.data[0]?.id ?? null) : null,
    );
    advanceContinuousUpTo(response.data.at(-1)?.id);
    readSinceStreamWentLive.current = liveWhenAsked && isChatStreamLive();
    setMessagesList(
      updates.reduce(
        (items, update) => update(items),
        response.data.map(applyTombstone),
      ),
    );
    setMessagesLoaded(true);
    if (isVisible() && isMounted.current)
      markRead(conversationId, response.data.at(-1)?.id);
    return true;
  }, [advanceContinuousUpTo, applyTombstone, conversationId, markRead]);

  // Fetches what changed while nothing was arriving, without moving anyone from the older pages they are reading.
  const resyncMessages = useCallback(
    async (nextPage: PageCheckpoint) => {
      if (!conversationId) return;
      const updates: MessageUpdate[] = [];
      pendingMessageUpdates.current.add(updates);
      const requestId = ++latestMessageRequest.current;
      const liveWhenAsked = isChatStreamLive();
      const from = continuousUpTo.current;
      const loaded: ChatMessage[] = [];
      let reachedStart = false;
      let meetsKnown = false;
      try {
        for (let page = 0; page < MESSAGE_RESYNC_PAGES; page++) {
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
            oldestLoaded !== undefined &&
            from !== undefined &&
            compareId(oldestLoaded, from) <= 0;
          if (reachedStart || meetsKnown || from === undefined) break;
        }
      } finally {
        pendingMessageUpdates.current.delete(updates);
      }
      if (requestId !== latestMessageRequest.current) return;
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
        // Too much happened to bridge, so this starts again from the newest page.
        const newestPage = reachedStart
          ? fetched
          : fetched.slice(-MESSAGE_PAGE_SIZE);
        setMessagesList(newestPage);
        setOlderMessageId(reachedStart ? null : (newestPage[0]?.id ?? null));
      }

      if (!followingNewestRef.current) {
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
      if (isVisible() && isMounted.current)
        markRead(conversationId, loaded.at(-1)?.id);
    },
    [
      advanceContinuousUpTo,
      applyTombstone,
      conversationId,
      jumpButton,
      markRead,
      readRecovered,
    ],
  );

  const markSeenOnReturn = useCallback(() => {
    if (!unreadWhileAway.current || !conversationId || !isVisible()) return;
    unreadWhileAway.current = false;
    markRead(conversationId, shownMessagesRef.current.at(-1)?.id);
  }, [conversationId, markRead]);

  const loadOlderMessages = useCallback(() => {
    if (!olderMessageId || !conversationId || loadingMore) return;
    setLoadingMore(true);
    const updates: MessageUpdate[] = [];
    pendingMessageUpdates.current.add(updates);
    void api()
      .get<ChatMessage[]>(
        `/api/v1/chat/conversations/${conversationId}/messages`,
        { params: { max_id: olderMessageId } },
      )
      .then(({ data }) => {
        pendingMessageUpdates.current.delete(updates);
        const older = updates.reduce(
          (items, update) => update(items),
          data.map(applyTombstone),
        );
        updateMessages((current) => [
          ...older.filter(
            (item) => !current.some((existing) => existing.id === item.id),
          ),
          ...current,
        ]);
        setOlderMessageId(data.length === 40 ? (data[0]?.id ?? null) : null);
      })
      .catch(() => {
        setError('load');
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
    updateMessages,
  ]);

  // Read, by itself again while that fails.
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
    void whileOpening(
      keepReading('invitations', async () => {
        await Promise.resolve().then(loadInvitations);
        readRecovered('invitations');
      }),
    );
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

  useEffect(() => {
    if (!conversationId) return undefined;
    const read = `messages:${conversationId}`;
    void whileOpening(
      retries
        .keepTrying(
          read,
          async () => {
            // A newer read took over; this one goes on until that one has done.
            if (!(await loadMessages()))
              throw new Error('A newer read took over');
            readRecovered('messages');
          },
          {
            failed: () => {
              readFailed('messages');
            },
          },
        )
        .catch(() => undefined),
    );
    return () => {
      retries.cancel(read);
    };
  }, [
    conversationId,
    loadMessages,
    readFailed,
    readRecovered,
    retries,
    whileOpening,
  ]);

  const hasUnread = Boolean(conversation?.unread);
  useEffect(() => {
    if (!conversationId || !hasUnread) return;

    const markReadWhenShown = () => {
      if (!isVisible() || !followingNewestRef.current) return;
      markRead(conversationId, shownMessagesRef.current.at(-1)?.id);
    };

    document.addEventListener('visibilitychange', markReadWhenShown);
    return () => {
      document.removeEventListener('visibilitychange', markReadWhenShown);
    };
  }, [conversationId, hasUnread, markRead]);

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
          const message = applyTombstone(value as ChatMessage);
          const isOpen = eventConversationId === conversationId;
          const fromOther = value.account?.id !== me;
          const seen = isOpen && isVisible() && followingNewestRef.current;
          updateConversations((current) =>
            withNewMessage(current, message, fromOther && !seen),
          );
          if (knownConversationIds.current?.has(eventConversationId) === false)
            refreshConversation(eventConversationId);
          if (!isOpen) return;
          if (isChatStreamLive() && readSinceStreamWentLive.current)
            advanceContinuousUpTo(value.id);
          updateMessages((current) =>
            current.some((item) => item.id === value.id)
              ? current
              : [...current, message],
          );
          if (!followingNewestRef.current && fromOther) {
            jumpButton.update({ unseen: true });
            unreadWhileAway.current = true;
          }
          if (value.id && fromOther && seen) markRead(conversationId, value.id);
        } else if (event === 'chat.message_update') {
          const message = applyTombstone(value as ChatMessage);
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
          deletedMessages.current.set(value.id, new Date().toISOString());
          if (eventConversationId) refreshConversation(eventConversationId);
          if (eventConversationId !== conversationId) return;
          updateMessages((current) =>
            current.filter((item) => item.id !== value.id),
          );
        } else if (event === 'chat.conversation_update') {
          const updated = payload as Partial<ChatConversation>;
          if (updated.accounts) {
            updateConversations((current) =>
              upsertConversation(current, updated as ChatConversation),
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
          updateConversations((current) =>
            current.filter((item) => item.id !== value.conversation_id),
          );
          setInvitations((current) =>
            current.filter(
              (item) => item.conversation.id !== value.conversation_id,
            ),
          );
          if (value.conversation_id !== conversationId) return;
          if (!value.reason) {
            history.push('/chat');
            return;
          }
          // An answer on its way from before this must not bring the room back.
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
          void keepReading('invitations', async () => {
            await loadInvitations();
            readRecovered('invitations');
          });
        } else if (event === 'chat.invitation_update') {
          if (eventConversationId === conversationId)
            setSentInvitationsVersion((version) => version + 1);
        } else if (event === CHAT_STREAM_RECONNECTED) {
          readSinceStreamWentLive.current = false;
          setSentInvitationsVersion((version) => version + 1);
          // This also runs on every poll while offline, and the next one tries again.
          const readAgain = () => {
            // A queued reread supersedes the snapshot currently on its way.
            if (retries.planned('conversations'))
              latestConversationRequest.current += 1;
            void retries
              .keepTrying('conversations', async (nextPage) => {
                if (await loadConversations(nextPage))
                  readRecovered('conversations');
              })
              .catch(() => undefined);
            retries.wake('conversations');
            void retries
              .keepTrying('invitations', async () => {
                await loadInvitations();
                readRecovered('invitations');
              })
              .catch(() => undefined);
            retries.wake('invitations');
            if (conversationId) {
              void retries
                .keepTrying(`messages:${conversationId}`, resyncMessages)
                .catch(() => undefined);
              retries.wake(`messages:${conversationId}`);
            }
          };
          // Starting before the screen's first answers are back would throw them away, and
          // leave it empty if this failed.
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
      loadConversations,
      loadInvitations,
      markRead,
      readRecovered,
      refreshConversation,
      refreshConversations,
      resyncMessages,
      retries,
      updateConversations,
      updateMessages,
    ],
  );

  const finishEditing = useCallback(() => {
    setEditingId(null);
    composerText.set(draftBeforeEdit?.text ?? '');
    setMedia(draftBeforeEdit?.media ?? []);
    setDraftBeforeEdit(null);
  }, [composerText, draftBeforeEdit]);

  const isArchived = Boolean(conversation?.archived);
  const recipientSuspended =
    conversation?.type === 'direct' &&
    conversation.accounts.some((item) => item.id !== me && item.suspended);
  const editingTargetDeleted = messagesList.some(
    (message) => message.id === editingId && message.deleted_at,
  );
  const editingCannotGoOn =
    Boolean(editingId) && (isArchived || editingTargetDeleted);
  // After drawing, because it changes what the box shows, and before the screen shows it.
  useLayoutEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (editingCannotGoOn) finishEditing();
  }, [editingCannotGoOn, finishEditing]);
  if (replyToId && isArchived) setReplyToId(null);

  const newestMessage = messagesList.at(-1);
  const newestMessageId = newestMessage?.id;
  const newestMessageConversationId = newestMessage?.conversation_id;
  const newestMessageIsMine = newestMessage?.account.id === me;

  useEffect(() => {
    if (!newestMessageId || newestMessageConversationId !== conversationId)
      return;

    const screenKey = `${conversationId}:${roomView ?? ''}`;
    const openingRoom = scrolledConversationIdRef.current !== screenKey;
    scrolledConversationIdRef.current = screenKey;
    if (openingRoom) followingNewestRef.current = true;

    if (followingNewestRef.current || newestMessageIsMine) {
      scrollToNewest(messagesEndRef.current);
    }
  }, [
    conversationId,
    newestMessageConversationId,
    newestMessageId,
    newestMessageIsMine,
    roomView,
  ]);

  useEffect(() => {
    const end = messagesEndRef.current;
    const list = messagesListRef.current;
    if (!end || !list) return;

    const trackPosition = () => {
      const following =
        end.getBoundingClientRect().bottom - window.innerHeight <
        FOLLOW_NEWEST_DISTANCE;
      followingNewestRef.current = following;
      if (following) {
        jumpButton.update({ away: false, unseen: false });
        markSeenOnReturn();
      } else {
        jumpButton.update({ away: true });
      }
    };
    window.addEventListener('scroll', trackPosition, {
      capture: true,
      passive: true,
    });

    const observer =
      typeof ResizeObserver === 'function'
        ? new ResizeObserver(() => {
            if (followingNewestRef.current) scrollToNewest(end);
          })
        : null;
    observer?.observe(list);
    if (composerRef.current) observer?.observe(composerRef.current);

    return () => {
      window.removeEventListener('scroll', trackPosition, { capture: true });
      observer?.disconnect();
    };
  }, [
    conversationId,
    conversationMissing,
    jumpButton,
    markSeenOnReturn,
    roomView,
  ]);

  const jumpTargetLoaded = Boolean(
    jumpTargetId && messagesById.has(jumpTargetId),
  );

  useEffect(() => {
    if (!jumpTargetId || !jumpTargetLoaded) return;
    followingNewestRef.current = false;
    const target = document.getElementById(`chat-message-${jumpTargetId}`);
    if (typeof target?.scrollIntoView === 'function') {
      target.scrollIntoView({ block: 'center' });
    }
    const timeout = window.setTimeout(() => {
      setJumpTargetId(null);
    }, HIGHLIGHT_DURATION_MS);
    return () => {
      window.clearTimeout(timeout);
    };
  }, [jumpTargetId, jumpTargetLoaded]);

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
    followingNewestRef.current = true;
    jumpButton.update({ away: false, unseen: false });
    markSeenOnReturn();
    scrollToNewest(messagesEndRef.current);
  }, [jumpButton, markSeenOnReturn]);

  const handleReplyQuoteClick = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      setJumpTargetId(event.currentTarget.dataset.messageId ?? null);
    },
    [],
  );

  const handleBack = useCallback(() => {
    history.push(
      roomView && conversationId ? `/chat/${conversationId}` : '/chat',
    );
  }, [conversationId, history, roomView]);

  const isGroupOwner =
    conversation?.type === 'group' && conversation.current_role === 'owner';
  const isManagingRoom =
    (roomView === 'members' && conversation?.type === 'group') ||
    (roomView === 'settings' && isGroupOwner);
  const listsSentInvitations = roomView === 'members' && isGroupOwner;

  useEffect(() => {
    if (!conversationId || !listsSentInvitations) return undefined;

    let current = true;
    const read = `sent:${conversationId}`;
    void keepReading(read, async (nextPage) => {
      const found = await fetchSentInvitations(conversationId, nextPage);
      if (!current || !found) return;
      setSentInvitations(found);
      readRecovered(read);
    });
    return () => {
      current = false;
      // Away from the members screen, nothing on screen misses this list.
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

  // The newest comes first from the API, and here it joins the end of the list.
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
      await loadConversationsForAction();
      navigateIfActive(`/chat/${response.data.id}`);
      setDirectAccount(null);
      setDirectAccountQuery('');
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [directAccount, loadConversationsForAction, navigateIfActive]);

  const hasOtherContent =
    media.length > 0 ||
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
      !(text.trim() || hasOtherContent) ||
      isTooLong(text)
    )
      return;
    setLoading(true);
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
              media_ids: media.map((item) => item.id),
            },
          );
      setSendError(null);
      const message = applyTombstone(response.data);
      updateMessages((current) =>
        current.some((item) => item.id === message.id)
          ? current.map((item) => (item.id === message.id ? message : item))
          : [...current, message],
      );
      if (editingId) {
        finishEditing();
      } else {
        // The box stays writable meanwhile: only what went out leaves it.
        const current = composerText.get();
        composerText.set(
          current.startsWith(text) ? current.slice(text.length) : current,
        );
        setMedia([]);
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

  // Pressing Send must not take the focus from the message box, or a phone's keyboard goes away with it. A disabled
  // button lets the press through to the form. With the focus elsewhere nothing changes, so no keyboard comes up.
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
      setAccountResults([]);
    },
    [accountResults],
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
      setGroupAccountResults([]);
    },
    [groupAccountResults],
  );

  const handleRemoveGroupAccount = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.accountId;
      setGroupAccounts((current) =>
        current.filter((account) => account.id !== id),
      );
    },
    [],
  );

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
      setInviteAccountResults([]);
    },
    [inviteAccountResults],
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
      setError(null);
      void api()
        .get<ChatMessage[]>('/api/v1/chat/messages/search', {
          params: { q: query, limit: 40 },
        })
        .then((response) => {
          if (requestId !== latestMessageSearch.current) return;
          setSearchResults(response.data);
          setSearchedQuery(query);
        })
        .catch(() => {
          if (requestId === latestMessageSearch.current) setError('search');
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
      await loadConversationsForAction();
      navigateIfActive(`/chat/${response.data.id}`);
      setGroupTitle('');
      setGroupAccountQuery('');
      setGroupAccounts([]);
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [groupAccounts, groupTitle, loadConversationsForAction, navigateIfActive]);

  const handleGroupSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      void createGroup();
    },
    [createGroup],
  );

  const handleMediaChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const files = Array.from(event.target.files ?? []);
      event.target.value = '';
      if (!chatSettings) return;
      if (files.length + media.length > chatSettings.max_attachments) {
        setError('too_many_attachments');
        return;
      }
      setError(null);
      setUploading(true);
      void Promise.all(
        files.map(async (file) => {
          const body = new FormData();
          body.append('file', file);
          const response = await api().post<ChatMedia>('/api/v2/media', body);
          return waitForMedia(response.data);
        }),
      )
        .then((uploaded) => {
          setMedia((current) => [...current, ...uploaded]);
        })
        .catch(() => {
          setError('upload');
        })
        .finally(() => {
          setUploading(false);
        });
    },
    [chatSettings, media.length],
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
        const draft = { text: composerText.get(), media };
        setDraftBeforeEdit((current) => current ?? draft);
        setEditingId(id);
        setReplyToId(null);
        setMedia([]);
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
        // Only the server knows what deleting will do right now.
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
      media,
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
        .post(`/api/v1/chat/invitations/${invitation.id}/${action}`)
        .then(() => {
          setInvitations((current) =>
            current.filter((item) => item.id !== invitation.id),
          );
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
    [dispatch, loadConversationsForAction],
  );

  const cancelInvitation = useCallback(
    (invitation: ChatInvitation) => {
      setError(null);
      void api()
        .delete(`/api/v1/chat/invitations/${invitation.id}`)
        .then(() => {
          setSentInvitations((current) =>
            current.filter((item) => item.id !== invitation.id),
          );
          dispatch(
            showAlert({
              message: messages.invitationCancelled,
              values: {
                account:
                  invitation.invitee?.display_name ??
                  invitation.invitee?.acct ??
                  '',
              },
            }),
          );
        })
        .catch(() => {
          setError('invite');
        });
    },
    [dispatch],
  );

  const handleInviteSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!conversationId || !inviteAccount) return;
      setError(null);
      void api()
        .post(`/api/v1/chat/conversations/${conversationId}/invitations`, {
          account_id: inviteAccount.id,
        })
        .then(() => {
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
    [conversationId, dispatch, inviteAccount],
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
        .then(() => {
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
          setChatSettings(response.data);
        })
        .catch(() => {
          setError('settings');
        });
    },
    [],
  );

  const handleSettingToggle = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const key = event.target.dataset.setting;
      if (!key) return;
      if (
        key === 'notifications' &&
        event.target.checked &&
        'Notification' in window &&
        Notification.permission === 'default'
      ) {
        void Notification.requestPermission();
      }
      setError(null);
      void api()
        .patch<ChatSettings>('/api/v1/chat/settings', {
          [key]: event.target.checked,
        })
        .then((response) => {
          setChatSettings(response.data);
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
        .post(`/api/v1/chat/conversations/${conversationId}/${action}`)
        .then(() => loadConversationsForAction())
        .catch(() => {
          setError('update');
        });
    },
    [conversationId, loadConversationsForAction],
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
      ...(isGroup
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

  // The room scrolls, and only the composer stays on screen wherever it is scrolled.
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
          <div className='chat-native-settings'>
            <h3>{intl.formatMessage(messages.settings)}</h3>
            <label>
              <FormattedMessage
                id='chat.policy'
                defaultMessage='Who can start a direct chat'
              />
              <select value={chatSettings.policy} onChange={handlePolicyChange}>
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
              </select>
            </label>
            <label>
              <input
                type='checkbox'
                data-setting='allow_group_invites'
                checked={chatSettings.allow_group_invites}
                onChange={handleSettingToggle}
              />
              <FormattedMessage
                id='chat.allow_group_invites'
                defaultMessage='Allow group invitations'
              />
            </label>
            <label>
              <input
                type='checkbox'
                data-setting='notifications'
                checked={chatSettings.notifications}
                onChange={handleSettingToggle}
              />
              <FormattedMessage
                id='chat.notifications'
                defaultMessage='Notify me about new chat messages'
              />
            </label>
          </div>
        )}
      </ColumnHeader>

      <div className='scrollable chat-native'>
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
              <Link className='button chat-native__ended-back' to='/chat'>
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
                        <div className='chat-native__account-card'>
                          <AccountSummary account={inviteAccount} />
                          <button
                            type='button'
                            onClick={handleRemoveInviteAccount}
                            aria-label={intl.formatMessage({
                              id: 'chat.remove_account',
                              defaultMessage: 'Remove selected account',
                            })}
                          >
                            ×
                          </button>
                        </div>
                      </div>
                    )}
                  </form>
                  {inviteAccountQuery.trim().length >= 2 && (
                    <AccountSearchNotice status={accountSearchStatus} />
                  )}
                  {inviteAccountResults.length > 0 && (
                    <div className='chat-native__account-results'>
                      {inviteAccountResults.map((account) => (
                        <button
                          key={account.id}
                          type='button'
                          data-account-id={account.id}
                          onClick={handleInviteAccountResult}
                        >
                          <AccountSummary account={account} />
                        </button>
                      ))}
                    </div>
                  )}
                </>
              )}
              {conversation.accounts.map((account) => (
                <div className='chat-native__member' key={account.id}>
                  <Avatar account={account} size={36} withLink />
                  <div>
                    <strong>{account.display_name || account.acct}</strong>
                    <span title={`@${account.acct}`}>@{account.acct}</span>
                  </div>
                  {isRemoteAccount(account) && (
                    <small className='chat-native__remote-badge'>
                      <FormattedMessage
                        id='chat.remote'
                        defaultMessage='Remote'
                      />
                    </small>
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
                </div>
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
                  // Keeps iOS 27 Safari from taking it for an address box; see ComposerBox.
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
                      <div className='chat-native__date' role='separator'>
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
                          <Avatar
                            account={message.account}
                            size={36}
                            withLink
                          />
                        ) : (
                          <span className='chat-native__avatar-space' />
                        ))}
                      <div className='chat-native__message-content'>
                        {message.account.id !== me &&
                          startsRun(messagesList, index) && (
                            <strong>
                              {message.account.display_name ||
                                message.account.acct}
                            </strong>
                          )}
                        <div className='chat-native__bubble-wrap'>
                          {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex */}
                          <div className='chat-native__bubble' tabIndex={0}>
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
                                message.content
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
                          <div className='chat-native__reactions'>
                            {message.reactions.map((reaction) => (
                              <button
                                key={`${reaction.account.id}-${reaction.reaction}`}
                                type='button'
                                className={
                                  reaction.account.id === me
                                    ? 'mine'
                                    : undefined
                                }
                                data-message-id={message.id}
                                data-reaction={reaction.reaction}
                                data-account-id={reaction.account.id}
                                onClick={handleReactionClick}
                                title={reaction.account.acct}
                              >
                                {reaction.url ? (
                                  <img
                                    className='emoji'
                                    src={reaction.static_url ?? reaction.url}
                                    alt={reaction.reaction}
                                  />
                                ) : (
                                  reaction.reaction
                                )}
                              </button>
                            ))}
                          </div>
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
              {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions -- only keeps the focus where it is */}
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
                        {replyTarget ? (
                          <FormattedMessage
                            id='chat.replying_to'
                            defaultMessage='Replying to {account}'
                            values={{
                              account:
                                replyTarget.account.display_name ||
                                replyTarget.account.acct,
                            }}
                          />
                        ) : (
                          <FormattedMessage
                            id='chat.replying'
                            defaultMessage='Replying to message'
                          />
                        )}
                        <span>
                          {replyTarget && !replyTarget.deleted_at
                            ? replyTarget.content
                            : intl.formatMessage({
                                id: 'chat.message_deleted',
                                defaultMessage: 'This message was deleted.',
                              })}
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
                {media.length > 0 && (
                  <div className='chat-native__media-preview'>
                    {media.map((attachment) => (
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
                    media.some((item) => !item.url)
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
          <section id='chat-new-panel' className='chat-native__new-panel'>
            <div className='chat-native__new-modes'>
              <button
                type='button'
                data-mode='direct'
                aria-pressed={newChatMode === 'direct'}
                onClick={handleNewChatMode}
              >
                {intl.formatMessage(messages.newDirect)}
              </button>
              <button
                type='button'
                data-mode='group'
                aria-pressed={newChatMode === 'group'}
                onClick={handleNewChatMode}
              >
                {intl.formatMessage(messages.newGroup)}
              </button>
            </div>
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
                    <Button type='submit' disabled={loading || !directAccount}>
                      {intl.formatMessage(messages.open)}
                    </Button>
                  </div>
                  {directAccount && (
                    <div className='chat-native__selected-accounts'>
                      <div className='chat-native__account-card'>
                        <AccountSummary account={directAccount} />
                        <button
                          type='button'
                          onClick={handleRemoveDirectAccount}
                          aria-label={intl.formatMessage({
                            id: 'chat.remove_account',
                            defaultMessage: 'Remove selected account',
                          })}
                        >
                          ×
                        </button>
                      </div>
                    </div>
                  )}
                </form>
                {directAccountQuery.trim().length >= 2 && (
                  <AccountSearchNotice status={accountSearchStatus} />
                )}
                {accountResults.length > 0 && (
                  <div className='chat-native__account-results'>
                    {accountResults.map((account) => (
                      <button
                        key={account.id}
                        type='button'
                        data-account-id={account.id}
                        onClick={handleAccountResult}
                      >
                        <AccountSummary account={account} />
                      </button>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <>
                <form className='chat-native__new' onSubmit={handleGroupSubmit}>
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
                        <div
                          className='chat-native__account-card'
                          key={account.id}
                        >
                          <AccountSummary account={account} />
                          <button
                            type='button'
                            data-account-id={account.id}
                            onClick={handleRemoveGroupAccount}
                            aria-label={intl.formatMessage({
                              id: 'chat.remove_account',
                              defaultMessage: 'Remove selected account',
                            })}
                          >
                            ×
                          </button>
                        </div>
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
                      <button
                        key={account.id}
                        type='button'
                        data-account-id={account.id}
                        onClick={handleGroupAccountResult}
                      >
                        <AccountSummary account={account} />
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </section>
        ) : (
          <>
            <nav
              className='chat-native__tabs'
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
                  <Icon id={tab} icon={icon} />
                  {intl.formatMessage(tabMessage)}
                  {tab === 'invitations' && invitations.length > 0 && (
                    <span>{invitations.length}</span>
                  )}
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
                      <button
                        key={result.id}
                        type='button'
                        data-conversation-id={result.conversation_id}
                        data-message-id={result.id}
                        onClick={handleSearchResult}
                      >
                        <AccountSummary
                          account={result.account}
                          detail={result.content ?? ''}
                        />
                      </button>
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
                    className={item.unread ? 'unread' : undefined}
                    data-conversation-id={item.id}
                    onClick={handleOpenConversation}
                  >
                    <ConversationPicture conversation={item} />
                    <span className='chat-native__account-names'>
                      <ConversationTitle conversation={item} />
                      <span>{item.last_message?.content}</span>
                    </span>
                    {item.archived && (
                      <small className='chat-native__state-badge'>
                        <FormattedMessage
                          id='chat.archived_badge'
                          defaultMessage='Archived'
                        />
                      </small>
                    )}
                    {item.unread && (
                      <i aria-label={intl.formatMessage(messages.unread)} />
                    )}
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
