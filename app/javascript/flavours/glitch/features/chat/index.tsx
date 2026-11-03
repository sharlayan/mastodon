import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ChangeEvent, MouseEvent, SyntheticEvent } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useHistory, useParams } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import PhotoLibraryIcon from '@/material-icons/400-20px/photo_library.svg?react';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import ChatIcon from '@/material-icons/400-24px/chat.svg?react';
import CheckIcon from '@/material-icons/400-24px/check.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import GroupsIcon from '@/material-icons/400-24px/groups.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import SearchIcon from '@/material-icons/400-24px/search.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import api from 'flavours/glitch/api';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadMore } from 'flavours/glitch/components/load_more';
import { NotSignedInIndicator } from 'flavours/glitch/components/not_signed_in_indicator';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import { useIdentity } from 'flavours/glitch/identity_context';
import { me } from 'flavours/glitch/initial_state';

import { subscribeChatStream } from './stream';

interface ChatAccount {
  id: string;
  acct: string;
  display_name: string;
}

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
}

type MessageUpdate = (messages: ChatMessage[]) => ChatMessage[];

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
}

interface ChatSettings {
  policy: 'everyone' | 'followers' | 'following' | 'mutual' | 'none';
  allow_group_invites: boolean;
  notifications: boolean;
  max_group_members: number;
  max_attachments: number;
  federation_enabled: boolean;
}

interface PickedEmoji {
  native?: string;
  colons?: string;
}

type ChatHomeTab = 'home' | 'invitations' | 'joiningRooms' | 'ownedRooms';

const messages = defineMessages({
  heading: { id: 'chat.title', defaultMessage: 'Chat' },
  newChat: { id: 'chat.new_chat', defaultMessage: 'New chat' },
  search: { id: 'chat.search', defaultMessage: 'Search messages' },
  newDirect: { id: 'chat.new_direct', defaultMessage: 'Start a direct chat' },
  open: { id: 'chat.open', defaultMessage: 'Open chat' },
  send: { id: 'chat.send', defaultMessage: 'Send' },
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

// Matches ChatMessage::MAX_TEXT_LENGTH, which counts code points after trimming.
const MAX_MESSAGE_LENGTH = 4096;

const isVisible = () => document.visibilityState !== 'hidden';
const isNotFound = (error: unknown) =>
  (error as { response?: { status?: number } }).response?.status === 404;

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

  return <EmojiPickerDropdown onPickEmoji={handlePick} />;
};

const conversationName = (conversation: ChatConversation) => {
  if (conversation.title) return conversation.title;

  return conversation.accounts
    .filter((account) => account.id !== me)
    .map((account) => account.display_name || account.acct)
    .join(', ');
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
  onAnswer: (id: string, action: 'accept' | 'reject') => void;
}> = ({ invitation, onAnswer }) => {
  const intl = useIntl();
  const handleAccept = useCallback(() => {
    onAnswer(invitation.id, 'accept');
  }, [invitation.id, onAnswer]);
  const handleReject = useCallback(() => {
    onAnswer(invitation.id, 'reject');
  }, [invitation.id, onAnswer]);

  return (
    <div className='chat-native__invitation'>
      <div>
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
        <IconButton
          title={intl.formatMessage({
            id: 'chat.accept',
            defaultMessage: 'Accept',
          })}
          icon='check'
          iconComponent={CheckIcon}
          onClick={handleAccept}
        />
        <IconButton
          title={intl.formatMessage({
            id: 'chat.reject',
            defaultMessage: 'Reject',
          })}
          icon='times'
          iconComponent={CloseIcon}
          onClick={handleReject}
        />
      </div>
    </div>
  );
};

const FOLLOW_NEWEST_DISTANCE = 240;

const scrollToNewest = (end: HTMLElement | null) => {
  if (typeof end?.scrollIntoView === 'function') {
    end.scrollIntoView({ block: 'end' });
  }
};

export const Chat: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const { conversationId } = useParams<{ conversationId?: string }>();

  // Each visit owns its messages, composer and pending async completions, even
  // when the router reuses Chat across room and home navigation.
  return (
    <ChatSession key={conversationId ?? 'home'} multiColumn={multiColumn} />
  );
};

const ChatSession: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const history = useHistory();
  const { conversationId: routeId } = useParams<{ conversationId?: string }>();
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
  const [directAccountQuery, setDirectAccountQuery] = useState('');
  const [directAccount, setDirectAccount] = useState<ChatAccount | null>(null);
  const [accountResults, setAccountResults] = useState<ChatAccount[]>([]);
  const [groupTitle, setGroupTitle] = useState('');
  const [groupAccountQuery, setGroupAccountQuery] = useState('');
  const [groupAccountResults, setGroupAccountResults] = useState<ChatAccount[]>(
    [],
  );
  const [groupAccounts, setGroupAccounts] = useState<ChatAccount[]>([]);
  const [text, setText] = useState('');
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
  const [groupEdit, setGroupEdit] = useState<{
    conversationId: string;
    title: string;
    description: string;
  } | null>(null);
  // Tied to the room, so settings opened in one room stay closed in the next.
  const [groupSettingsConversationId, setGroupSettingsConversationId] =
    useState<string | null>(null);
  const [newChatMode, setNewChatMode] = useState<'direct' | 'group'>('direct');
  const [searchOpen, setSearchOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<ChatMessage[]>([]);
  const [searchedQuery, setSearchedQuery] = useState<string | null>(null);
  const [conversationMissing, setConversationMissing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isMounted = useRef(true);
  // What was in the composer before an edit took it over.
  const [draftBeforeEdit, setDraftBeforeEdit] = useState<{
    text: string;
    media: ChatMedia[];
  } | null>(null);
  const deletedMessages = useRef(new Map<string, string>());
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const scrolledConversationIdRef = useRef<string | undefined>(undefined);
  const messagesListRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const followingNewestRef = useRef(true);
  const searchRequestRef = useRef(0);
  const searchTimeoutRef = useRef<number | null>(null);

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

  const pendingMessageUpdates = useRef(new Set<MessageUpdate[]>());
  const latestMessageRequest = useRef(0);
  const conversationPages = useRef(1);
  const latestConversationRequest = useRef(0);
  const updateMessages = useCallback((update: MessageUpdate) => {
    pendingMessageUpdates.current.forEach((updates) => updates.push(update));
    setMessagesList(update);
  }, []);

  const conversation = useMemo(
    () => conversations.find((item) => item.id === conversationId),
    [conversationId, conversations],
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

  const searchAccounts = useCallback(
    (query: string, setter: (accounts: ChatAccount[]) => void) => {
      const normalized = query.trim();
      const requestId = searchRequestRef.current + 1;
      searchRequestRef.current = requestId;

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
            setter(
              response.data.accounts.filter((account) => account.id !== me),
            );
          })
          .catch(() => {
            if (requestId === searchRequestRef.current) setter([]);
          });
      }, 250);
    },
    [],
  );

  useEffect(() => {
    isMounted.current = true;
    return () => {
      isMounted.current = false;
    };
  }, []);

  // A request can finish after the user moved on to something else.
  const navigateIfActive = useCallback(
    (path: string) => {
      if (isMounted.current) history.push(path);
    },
    [history],
  );

  const loadConversations = useCallback(async () => {
    const requestId = ++latestConversationRequest.current;
    const loaded: ChatConversation[] = [];
    let cursor: string | null = null;
    for (let page = 0; page < conversationPages.current; page++) {
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
    let missing = false;
    if (conversationId && !loaded.some((item) => item.id === conversationId)) {
      try {
        const selected = await api().get<ChatConversation>(
          `/api/v1/chat/conversations/${conversationId}`,
        );
        loaded.push(selected.data);
      } catch (loadError) {
        if (!isNotFound(loadError)) throw loadError;
        missing = true;
      }
    }
    // Events can start requests faster than they finish, in any order.
    if (requestId !== latestConversationRequest.current) return;
    setNextConversationId(cursor);
    setConversationMissing(missing);
    if (missing) setError('load');
    setConversations(loaded);
  }, [conversationId]);

  const refreshConversations = useCallback(() => {
    loadConversations().catch(() => {
      setError('load');
    });
  }, [loadConversations]);

  const loadMoreConversations = useCallback(() => {
    if (!nextConversationId || loadingMore) return;
    setLoadingMore(true);
    void api()
      .get<ChatConversation[]>('/api/v1/chat/conversations', {
        params: { max_id: nextConversationId },
      })
      .then(({ data }) => {
        conversationPages.current += 1;
        setConversations((current) => [
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
  }, [loadingMore, nextConversationId]);

  const loadInvitations = useCallback(async () => {
    const response = await api().get<ChatInvitation[]>(
      '/api/v1/chat/invitations',
    );
    setInvitations(response.data);
  }, []);

  const loadMessages = useCallback(async () => {
    if (!conversationId) return;
    // Replay mutations received after this request started so a delayed
    // snapshot cannot erase new messages, edits or reactions.
    const updates: MessageUpdate[] = [];
    pendingMessageUpdates.current.add(updates);
    const requestId = ++latestMessageRequest.current;
    const response = await api()
      .get<ChatMessage[]>(
        `/api/v1/chat/conversations/${conversationId}/messages`,
      )
      .catch((error: unknown) => {
        pendingMessageUpdates.current.delete(updates);
        throw error;
      });
    pendingMessageUpdates.current.delete(updates);
    if (requestId !== latestMessageRequest.current) return;
    setOlderMessageId(
      response.data.length === 40 ? (response.data[0]?.id ?? null) : null,
    );
    setMessagesList(
      updates.reduce(
        (items, update) => update(items),
        response.data.map(applyTombstone),
      ),
    );
    // Read state is caught up when the user comes back to this tab.
    if (!isVisible()) return;
    await api().post(`/api/v1/chat/conversations/${conversationId}/read`);
    setConversations((current) =>
      current.map((item) =>
        item.id === conversationId ? { ...item, unread: false } : item,
      ),
    );
  }, [applyTombstone, conversationId]);

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

  useEffect(() => {
    Promise.all([
      Promise.resolve().then(loadConversations),
      Promise.resolve().then(loadInvitations),
      api().get<ChatSettings>('/api/v1/chat/settings'),
    ])
      .then(([, , settingsResponse]) => {
        setChatSettings(settingsResponse.data);
      })
      .catch(() => {
        setError('load');
      });
  }, [loadConversations, loadInvitations]);

  useEffect(() => {
    void loadMessages().catch(() => {
      setError('load');
    });
  }, [loadMessages]);

  const hasUnread = Boolean(conversation?.unread);
  useEffect(() => {
    if (!conversationId || !hasUnread) return;

    const markRead = () => {
      if (!isVisible()) return;
      void api()
        .post(`/api/v1/chat/conversations/${conversationId}/read`)
        .then(() => {
          setConversations((current) =>
            current.map((item) =>
              item.id === conversationId ? { ...item, unread: false } : item,
            ),
          );
        })
        .catch(() => undefined);
    };

    document.addEventListener('visibilitychange', markRead);
    return () => {
      document.removeEventListener('visibilitychange', markRead);
    };
  }, [conversationId, hasUnread]);

  useEffect(
    () =>
      subscribeChatStream(({ event, payload }) => {
        const value = payload as Partial<ChatMessage> &
          Partial<ChatReaction> & {
            conversation_id?: string;
            message_id?: string;
            account_id?: string;
          };
        if (
          event === 'chat.message' &&
          value.conversation_id === conversationId
        ) {
          const message = applyTombstone(value as ChatMessage);
          updateMessages((current) =>
            current.some((item) => item.id === value.id)
              ? current
              : [...current, message],
          );
          // The sender's own messages are already read on the server, and a
          // background tab must not read messages on the user's behalf.
          if (value.id && value.account?.id !== me && isVisible()) {
            void api()
              .post(`/api/v1/chat/conversations/${conversationId}/read`, {
                message_id: value.id,
              })
              .catch(() => undefined)
              .then(() => {
                refreshConversations();
              });
          } else {
            refreshConversations();
          }
        } else if (
          event === 'chat.message_update' &&
          value.conversation_id === conversationId
        ) {
          const message = applyTombstone(value as ChatMessage);
          updateMessages((current) =>
            current.map((item) => (item.id === value.id ? message : item)),
          );
          refreshConversations();
        } else if (
          event === 'chat.message_delete' &&
          value.conversation_id === conversationId
        ) {
          if (!value.id) return;
          deletedMessages.current.set(value.id, new Date().toISOString());
          updateMessages((current) =>
            current.map((item) =>
              item.id === value.id ? applyTombstone(item) : item,
            ),
          );
          refreshConversations();
        } else if (
          event === 'chat.message_hide' &&
          value.conversation_id === conversationId
        ) {
          if (!value.id) return;
          deletedMessages.current.set(value.id, new Date().toISOString());
          updateMessages((current) =>
            current.filter((item) => item.id !== value.id),
          );
          refreshConversations();
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
          setConversations((current) =>
            current.filter((item) => item.id !== value.conversation_id),
          );
          setInvitations((current) =>
            current.filter(
              (item) => item.conversation.id !== value.conversation_id,
            ),
          );
          if (value.conversation_id === conversationId) history.push('/chat');
        } else if (event === 'chat.read' && value.conversation_id) {
          setConversations((current) =>
            current.map((item) =>
              item.id === value.conversation_id
                ? { ...item, unread: false }
                : item,
            ),
          );
        } else if (event === 'chat.invitation') {
          void loadInvitations().catch(() => {
            setError('load');
          });
          refreshConversations();
        } else if (event !== 'chat.notification' && event.startsWith('chat.')) {
          refreshConversations();
          if (value.conversation_id === conversationId)
            void loadMessages().catch(() => {
              setError('load');
            });
        }
      }),
    [
      applyTombstone,
      conversationId,
      history,
      loadInvitations,
      loadMessages,
      refreshConversations,
      updateMessages,
    ],
  );

  const finishEditing = useCallback(() => {
    setEditingId(null);
    setText(draftBeforeEdit?.text ?? '');
    setMedia(draftBeforeEdit?.media ?? []);
    setDraftBeforeEdit(null);
  }, [draftBeforeEdit]);

  // What the composer was working on can go away while it is on screen.
  const isArchived = Boolean(conversation?.archived);
  const editingTargetDeleted = messagesList.some(
    (message) => message.id === editingId && message.deleted_at,
  );
  if (editingId && (isArchived || editingTargetDeleted)) finishEditing();
  if (replyToId && isArchived) setReplyToId(null);

  const newestMessage = messagesList.at(-1);
  const newestMessageId = newestMessage?.id;
  const newestMessageConversationId = newestMessage?.conversation_id;
  const newestMessageIsMine = newestMessage?.account.id === me;

  // Keyed on the newest message, so loading older ones leaves the view alone.
  useEffect(() => {
    if (!newestMessageId || newestMessageConversationId !== conversationId)
      return;

    const openingRoom = scrolledConversationIdRef.current !== conversationId;
    scrolledConversationIdRef.current = conversationId;
    if (openingRoom) followingNewestRef.current = true;

    if (followingNewestRef.current || newestMessageIsMine) {
      scrollToNewest(messagesEndRef.current);
    }
  }, [
    conversationId,
    newestMessageConversationId,
    newestMessageId,
    newestMessageIsMine,
  ]);

  // Images and reactions add height after the scroll above, and no scroll event
  // says so. Scroll position is read from the window because which element
  // scrolls depends on the layout.
  useEffect(() => {
    const end = messagesEndRef.current;
    const list = messagesListRef.current;
    if (!end || !list) return;

    const trackPosition = () => {
      followingNewestRef.current =
        end.getBoundingClientRect().bottom - window.innerHeight <
        FOLLOW_NEWEST_DISTANCE;
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

    return () => {
      window.removeEventListener('scroll', trackPosition, { capture: true });
      observer?.disconnect();
    };
  }, [conversationId, conversationMissing]);

  const isGroupOwner =
    conversation?.type === 'group' && conversation.current_role === 'owner';
  const groupSettingsOpen =
    Boolean(conversationId) && groupSettingsConversationId === conversationId;
  const handleGroupSettingsToggle = useCallback(() => {
    setGroupSettingsConversationId((current) =>
      current === conversationId ? null : (conversationId ?? null),
    );
  }, [conversationId]);

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
      await loadConversations();
      navigateIfActive(`/chat/${response.data.id}`);
      setDirectAccount(null);
      setDirectAccountQuery('');
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [directAccount, loadConversations, navigateIfActive]);

  const isTooLong = Array.from(text.trim()).length > MAX_MESSAGE_LENGTH;
  const hasSendableContent =
    Boolean(text.trim()) ||
    media.length > 0 ||
    messagesList.some(
      (message) =>
        message.id === editingId &&
        !message.deleted_at &&
        message.media_attachments.length > 0,
    );

  const send = useCallback(async () => {
    if (!conversationId || !hasSendableContent || isTooLong) return;
    setLoading(true);
    setError(null);
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
      const message = applyTombstone(response.data);
      updateMessages((current) =>
        current.some((item) => item.id === message.id)
          ? current.map((item) => (item.id === message.id ? message : item))
          : [...current, message],
      );
      if (editingId) {
        finishEditing();
      } else {
        setText('');
        setMedia([]);
      }
      setReplyToId(null);
    } catch {
      setError('send');
    } finally {
      setLoading(false);
    }
  }, [
    applyTombstone,
    conversationId,
    editingId,
    finishEditing,
    hasSendableContent,
    isTooLong,
    media,
    replyToId,
    text,
    updateMessages,
  ]);

  const handleComposerSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
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

  const handleTextChange = useCallback(
    (event: ChangeEvent<HTMLTextAreaElement>) => {
      setText(event.target.value);
    },
    [],
  );

  const handleDirectAccountQueryChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const value = event.target.value;
      setDirectAccount(null);
      setDirectAccountQuery(value);
      if (value.trim().length < 2) {
        setAccountResults([]);
        return;
      }
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

  const handleSearchToggle = useCallback(() => {
    setSearchOpen((open) => !open);
    setSearchQuery('');
    setSearchResults([]);
    setSearchedQuery(null);
  }, []);

  useEffect(() => {
    if (searchOpen) searchInputRef.current?.focus();
  }, [searchOpen]);

  const handleNewChatMode = useCallback(
    (event: SyntheticEvent<HTMLButtonElement>) => {
      setNewChatMode(event.currentTarget.dataset.mode as 'direct' | 'group');
    },
    [],
  );

  const handleSearchChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setSearchQuery(event.target.value);
    },
    [],
  );

  const handleSearchSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      const query = searchQuery.trim();
      if (!query) return;
      setError(null);
      void api()
        .get<ChatMessage[]>('/api/v1/chat/messages/search', {
          params: { q: query, limit: 40 },
        })
        .then((response) => {
          setSearchResults(response.data);
          setSearchedQuery(query);
        })
        .catch(() => {
          setError('search');
        });
    },
    [searchQuery],
  );

  const handleSearchResult = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.conversationId;
      if (id) history.push(`/chat/${id}`);
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
      await loadConversations();
      navigateIfActive(`/chat/${response.data.id}`);
      setGroupTitle('');
      setGroupAccountQuery('');
      setGroupAccounts([]);
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [groupAccounts, groupTitle, loadConversations, navigateIfActive]);

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
        setError('upload');
        return;
      }
      setError(null);
      setLoading(true);
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
          setLoading(false);
        });
    },
    [chatSettings, media.length],
  );

  const handleMessageAction = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.messageId;
      const action = event.currentTarget.dataset.action;
      const message = messagesList.find((item) => item.id === id);
      if (!id || !message || !action) return;
      setError(null);

      if (action === 'reply') {
        if (editingId) finishEditing();
        setReplyToId(id);
      } else if (action === 'edit') {
        setDraftBeforeEdit((current) => current ?? { text, media });
        setEditingId(id);
        setReplyToId(null);
        setMedia([]);
        setText(message.content ?? '');
      } else if (action === 'delete') {
        void api()
          .delete(`/api/v1/chat/messages/${id}`)
          .then(() => {
            deletedMessages.current.set(id, new Date().toISOString());
            updateMessages((current) =>
              current.map((item) =>
                item.id === id ? applyTombstone(item) : item,
              ),
            );
            refreshConversations();
          })
          .catch(() => {
            setError('delete');
          });
      }
    },
    [
      applyTombstone,
      editingId,
      finishEditing,
      media,
      messagesList,
      refreshConversations,
      text,
      updateMessages,
    ],
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
    (id: string, action: 'accept' | 'reject') => {
      setError(null);
      void api()
        .post(`/api/v1/chat/invitations/${id}/${action}`)
        .then(() => {
          setInvitations((current) => current.filter((item) => item.id !== id));
          return loadConversations();
        })
        .catch(() => {
          setError('invite');
        });
    },
    [loadConversations],
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
          setInviteAccount(null);
          setInviteAccountQuery('');
        })
        .catch(() => {
          setError('invite');
        });
    },
    [conversationId, inviteAccount],
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
          // Saved values now come from the room, so later renames show up here.
          setGroupEdit(null);
          return loadConversations();
        })
        .catch(() => {
          setError('update');
        });
    },
    [conversation, conversationId, groupEdit, loadConversations],
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

  const handleConversationAction = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      if (!conversationId || !conversation) return;
      const action = event.currentTarget.dataset.action;
      if (!action) return;
      if (
        action === 'destroy' &&
        !window.confirm(intl.formatMessage(messages.deleteGroupConfirm))
      )
        return;
      setError(null);
      if (action === 'mute' || action === 'unmute') {
        void api()
          .post(`/api/v1/chat/conversations/${conversationId}/${action}`)
          .then(() => loadConversations())
          .catch(() => {
            setError('update');
          });
      } else if (action === 'archive' || action === 'unarchive') {
        void api()
          .post(`/api/v1/chat/conversations/${conversationId}/${action}`)
          .then(() => loadConversations())
          .catch(() => {
            setError('update');
          });
      } else if (action === 'leave') {
        void api()
          .delete(`/api/v1/chat/conversations/${conversationId}/leave`)
          .then(() => {
            navigateIfActive('/chat');
          })
          .catch(() => {
            setError('update');
          });
      } else if (action === 'destroy') {
        void api()
          .delete(`/api/v1/chat/conversations/${conversationId}`)
          .then(() => {
            navigateIfActive('/chat');
          })
          .catch(() => {
            setError('update');
          });
      }
    },
    [conversation, conversationId, intl, loadConversations, navigateIfActive],
  );

  const handleRemoveMember = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      if (
        conversation?.type !== 'group' ||
        conversation.current_role !== 'owner' ||
        removingMemberId
      )
        return;
      const member = conversation.accounts.find(
        (account) => account.id === event.currentTarget.dataset.accountId,
      );
      if (!member || member.id === me) return;
      if (
        !window.confirm(
          intl.formatMessage(
            {
              id: 'chat.remove_member_confirm',
              defaultMessage:
                'Remove {name} from this group? They will need another invitation to rejoin.',
            },
            { name: member.display_name || member.acct },
          ),
        )
      )
        return;

      setError(null);
      setRemovingMemberId(member.id);
      void api()
        .delete<ChatConversation>(
          `/api/v1/chat/conversations/${conversation.id}/members/${member.id}`,
        )
        .then(({ data }) => {
          setConversations((current) =>
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
    [conversation, intl, removingMemberId],
  );

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

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='chat'
        iconComponent={ChatIcon}
        title={
          creating
            ? intl.formatMessage(messages.newChat)
            : conversation
              ? conversationName(conversation)
              : intl.formatMessage(messages.heading)
        }
        multiColumn={multiColumn}
        showBackButton={Boolean(conversationId) || creating}
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
        {conversationId && conversationMissing ? null : conversationId ? (
          <>
            {conversation && (
              <div className='chat-native__conversation-tools'>
                <button
                  type='button'
                  data-action={conversation.muted ? 'unmute' : 'mute'}
                  onClick={handleConversationAction}
                >
                  {conversation.muted ? (
                    <FormattedMessage
                      id='chat.unmute'
                      defaultMessage='Unmute'
                    />
                  ) : (
                    <FormattedMessage id='chat.mute' defaultMessage='Mute' />
                  )}
                </button>
                {isGroupOwner && (
                  <button
                    type='button'
                    aria-expanded={groupSettingsOpen}
                    aria-controls='chat-group-settings'
                    onClick={handleGroupSettingsToggle}
                  >
                    <FormattedMessage
                      id='chat.group_settings'
                      defaultMessage='Group settings'
                    />
                  </button>
                )}
                {conversation.type === 'group' &&
                  conversation.current_role === 'owner' && (
                    <button
                      type='button'
                      data-action={
                        conversation.archived ? 'unarchive' : 'archive'
                      }
                      onClick={handleConversationAction}
                    >
                      {conversation.archived ? (
                        <FormattedMessage
                          id='chat.unarchive'
                          defaultMessage='Reopen'
                        />
                      ) : (
                        <FormattedMessage
                          id='chat.archive'
                          defaultMessage='Archive'
                        />
                      )}
                    </button>
                  )}
                {conversation.type === 'group' && (
                  <button
                    type='button'
                    data-action={
                      conversation.current_role === 'owner'
                        ? 'destroy'
                        : 'leave'
                    }
                    onClick={handleConversationAction}
                  >
                    {conversation.current_role === 'owner' ? (
                      <FormattedMessage
                        id='chat.delete_group'
                        defaultMessage='Delete group'
                      />
                    ) : (
                      <FormattedMessage
                        id='chat.leave_group'
                        defaultMessage='Leave group'
                      />
                    )}
                  </button>
                )}
              </div>
            )}
            {conversation?.type === 'group' && (
              <section className='chat-native__members'>
                <h4>
                  <FormattedMessage
                    id='chat.members'
                    defaultMessage='Members ({count})'
                    values={{ count: conversation.accounts.length }}
                  />
                </h4>
                <div className='chat-native__members-list'>
                  {conversation.accounts.map((account) => (
                    <span
                      className='chat-native__member'
                      key={account.id}
                      title={`@${account.acct}`}
                    >
                      {account.display_name || account.acct}
                      {isRemoteAccount(account) && (
                        <small className='chat-native__remote-badge'>
                          <FormattedMessage
                            id='chat.remote'
                            defaultMessage='Remote'
                          />
                        </small>
                      )}
                      {conversation.current_role === 'owner' &&
                        account.id !== me && (
                          <button
                            type='button'
                            data-account-id={account.id}
                            onClick={handleRemoveMember}
                            disabled={removingMemberId !== null}
                            aria-label={intl.formatMessage(
                              {
                                id: 'chat.remove_member_label',
                                defaultMessage: 'Remove {name} from group',
                              },
                              { name: account.display_name || account.acct },
                            )}
                          >
                            <FormattedMessage
                              id='chat.remove_member'
                              defaultMessage='Remove'
                            />
                          </button>
                        )}
                    </span>
                  ))}
                </div>
              </section>
            )}
            {isGroupOwner && groupSettingsOpen && (
              <section
                id='chat-group-settings'
                className='chat-native__group-settings'
              >
                <form
                  className='chat-native__group-edit'
                  onSubmit={handleGroupEditSubmit}
                >
                  <input
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
                        <span>
                          <strong>
                            {inviteAccount.display_name || inviteAccount.acct}
                          </strong>
                          <small>@{inviteAccount.acct}</small>
                        </span>
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
                {inviteAccountResults.length > 0 && (
                  <div className='chat-native__account-results'>
                    {inviteAccountResults.map((account) => (
                      <button
                        key={account.id}
                        type='button'
                        data-account-id={account.id}
                        onClick={handleInviteAccountResult}
                      >
                        <strong>{account.display_name || account.acct}</strong>
                        <span>@{account.acct}</span>
                      </button>
                    ))}
                  </div>
                )}
              </section>
            )}
            {olderMessageId && (
              <LoadMore onClick={loadOlderMessages} loading={loadingMore} />
            )}
            <div className='chat-native__messages' ref={messagesListRef}>
              {messagesList.map((message) => (
                <article
                  className={`chat-native__message ${message.account.id === me ? 'chat-native__message--mine' : ''}`}
                  key={message.id}
                >
                  <strong>
                    {message.account.display_name || message.account.acct}
                  </strong>
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
                  {message.media_attachments.map((attachment) => (
                    <div
                      key={attachment.id}
                      className='chat-native__attachment'
                    >
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
                      ) : attachment.url ? (
                        <a
                          href={attachment.url}
                          target='_blank'
                          rel='noopener noreferrer'
                        >
                          <img
                            src={attachment.preview_url ?? attachment.url}
                            alt={attachment.description ?? ''}
                          />
                        </a>
                      ) : (
                        <span>{attachment.description ?? attachment.type}</span>
                      )}
                    </div>
                  ))}
                  {message.reactions.length > 0 && (
                    <div className='chat-native__reactions'>
                      {message.reactions.map((reaction) => (
                        <button
                          key={`${reaction.account.id}-${reaction.reaction}`}
                          type='button'
                          className={
                            reaction.account.id === me ? 'mine' : undefined
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
                  <time dateTime={message.created_at}>
                    {new Date(message.created_at).toLocaleString()}
                  </time>
                  {message.edited_at && !message.deleted_at && (
                    <span className='chat-native__edited'>
                      <FormattedMessage
                        id='chat.message_edited'
                        defaultMessage='Edited'
                      />
                    </span>
                  )}
                  {!message.deleted_at && !conversation?.archived && (
                    <div className='chat-native__actions'>
                      <button
                        type='button'
                        data-message-id={message.id}
                        data-action='reply'
                        onClick={handleMessageAction}
                      >
                        <FormattedMessage
                          id='chat.reply'
                          defaultMessage='Reply'
                        />
                      </button>
                      {message.account.id !== me && (
                        <span className='chat-native__react-picker'>
                          <ChatEmojiPicker
                            messageId={message.id}
                            onPick={handleEmojiPick}
                          />
                        </span>
                      )}
                      {message.account.id === me && (
                        <>
                          <button
                            type='button'
                            data-message-id={message.id}
                            data-action='edit'
                            onClick={handleMessageAction}
                          >
                            <FormattedMessage
                              id='chat.edit'
                              defaultMessage='Edit'
                            />
                          </button>
                          <button
                            type='button'
                            data-message-id={message.id}
                            data-action='delete'
                            onClick={handleMessageAction}
                          >
                            <FormattedMessage
                              id='chat.delete'
                              defaultMessage='Delete'
                            />
                          </button>
                        </>
                      )}
                    </div>
                  )}
                </article>
              ))}
            </div>
            {conversation?.archived && (
              <div className='chat-native__error'>
                <FormattedMessage
                  id='chat.archived'
                  defaultMessage='This group is archived.'
                />
              </div>
            )}
            <form
              className='chat-native__composer'
              onSubmit={handleComposerSubmit}
            >
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
                    Boolean(editingId) ||
                    Boolean(conversation?.archived)
                  }
                />
                <input
                  ref={fileInputRef}
                  type='file'
                  hidden
                  onChange={handleMediaChange}
                  accept='image/*,video/*,audio/*'
                />
                <textarea
                  value={text}
                  onChange={handleTextChange}
                  placeholder={intl.formatMessage(messages.placeholder)}
                  disabled={loading || isArchived}
                />
              </div>
              {isTooLong && (
                <div className='chat-native__error'>
                  <FormattedMessage
                    id='chat.message_too_long'
                    defaultMessage='This message is too long.'
                  />
                </div>
              )}
              <Button
                type='submit'
                disabled={
                  conversation?.archived ||
                  loading ||
                  media.some((item) => !item.url) ||
                  !hasSendableContent ||
                  isTooLong
                }
              >
                {intl.formatMessage(messages.send)}
              </Button>
            </form>
            {/* After the composer, so scrolling here shows the newest message above it. */}
            <div className='chat-native__end' ref={messagesEndRef} />
          </>
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
                        <span>
                          <strong>
                            {directAccount.display_name || directAccount.acct}
                          </strong>
                          <small>@{directAccount.acct}</small>
                        </span>
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
                {accountResults.length > 0 && (
                  <div className='chat-native__account-results'>
                    {accountResults.map((account) => (
                      <button
                        key={account.id}
                        type='button'
                        data-account-id={account.id}
                        onClick={handleAccountResult}
                      >
                        <strong>{account.display_name || account.acct}</strong>
                        <span>@{account.acct}</span>
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
                      value={groupTitle}
                      onChange={handleGroupTitleChange}
                      placeholder={intl.formatMessage(messages.groupTitle)}
                    />
                  </div>
                  <div className='chat-native__form-row'>
                    <input
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
                          <span>
                            <strong>
                              {account.display_name || account.acct}
                            </strong>
                            <small>@{account.acct}</small>
                          </span>
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
                {groupAccountResults.length > 0 && (
                  <div className='chat-native__account-results'>
                    {groupAccountResults.map((account) => (
                      <button
                        key={account.id}
                        type='button'
                        data-account-id={account.id}
                        onClick={handleGroupAccountResult}
                      >
                        <strong>{account.display_name || account.acct}</strong>
                        <span>@{account.acct}</span>
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
                        onClick={handleSearchResult}
                      >
                        <strong>
                          {result.account.display_name || result.account.acct}
                        </strong>
                        <span>{result.content}</span>
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
                    <strong>{conversationName(item)}</strong>
                    <span>{item.last_message?.content}</span>
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
                {visibleConversations.length === 0 && (
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
        {error && (
          <div className='chat-native__error' role='alert'>
            <FormattedMessage
              id='chat.error'
              defaultMessage='The chat request could not be completed.'
            />
          </div>
        )}
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};
