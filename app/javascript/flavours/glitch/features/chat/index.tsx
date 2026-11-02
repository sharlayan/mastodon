import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ChangeEvent, MouseEvent, SyntheticEvent } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory, useParams } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import ChatIcon from '@/material-icons/400-24px/chat.svg?react';
import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import GroupsIcon from '@/material-icons/400-24px/groups.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import api from 'flavours/glitch/api';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Icon } from 'flavours/glitch/components/icon';
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

interface ChatMedia {
  id: string;
  url: string;
  preview_url: string;
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
    defaultMessage: 'Joined rooms',
  },
  tabOwnedRooms: { id: 'chat.owned_rooms', defaultMessage: 'Your rooms' },
});

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
  const { conversationId } = useParams<{ conversationId?: string }>();
  const { signedIn } = useIdentity();
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
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
  const [groupEdit, setGroupEdit] = useState<{
    conversationId: string;
    title: string;
    description: string;
  } | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
    async (query: string, setter: (accounts: ChatAccount[]) => void) => {
      if (query.trim().length < 2) {
        setter([]);
        return;
      }
      const response = await api().get<{ accounts: ChatAccount[] }>(
        '/api/v2/search',
        {
          params: {
            q: query.trim(),
            type: 'accounts',
            resolve: true,
            limit: 8,
          },
        },
      );
      setter(response.data.accounts.filter((account) => account.id !== me));
    },
    [],
  );

  const loadConversations = useCallback(async () => {
    const response = await api().get<ChatConversation[]>(
      '/api/v1/chat/conversations',
    );
    setConversations(response.data);
  }, []);

  const loadInvitations = useCallback(async () => {
    const response = await api().get<ChatInvitation[]>(
      '/api/v1/chat/invitations',
    );
    setInvitations(response.data);
  }, []);

  const loadMessages = useCallback(async () => {
    if (!conversationId) return;
    const response = await api().get<ChatMessage[]>(
      `/api/v1/chat/conversations/${conversationId}/messages`,
    );
    setMessagesList(response.data);
    await api().post(`/api/v1/chat/conversations/${conversationId}/read`);
    setConversations((current) =>
      current.map((item) =>
        item.id === conversationId ? { ...item, unread: false } : item,
      ),
    );
  }, [conversationId]);

  useEffect(() => {
    Promise.all([
      api().get<ChatConversation[]>('/api/v1/chat/conversations'),
      api().get<ChatInvitation[]>('/api/v1/chat/invitations'),
      api().get<ChatSettings>('/api/v1/chat/settings'),
    ])
      .then(([conversationResponse, invitationResponse, settingsResponse]) => {
        setConversations(conversationResponse.data);
        setInvitations(invitationResponse.data);
        setChatSettings(settingsResponse.data);
      })
      .catch(() => {
        setError('load');
      });
  }, []);

  useEffect(() => {
    if (!conversationId) return;

    api()
      .get<ChatMessage[]>(
        `/api/v1/chat/conversations/${conversationId}/messages`,
      )
      .then((response) => {
        setMessagesList(response.data);
        return api().post(`/api/v1/chat/conversations/${conversationId}/read`);
      })
      .then(() => {
        setConversations((current) =>
          current.map((item) =>
            item.id === conversationId ? { ...item, unread: false } : item,
          ),
        );
      })
      .catch(() => {
        setError('load');
      });
  }, [conversationId]);

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
          setMessagesList((current) =>
            current.some((item) => item.id === value.id)
              ? current
              : [...current, value as ChatMessage],
          );
          void loadConversations();
        } else if (
          event === 'chat.message_update' &&
          value.conversation_id === conversationId
        ) {
          setMessagesList((current) =>
            current.map((item) =>
              item.id === value.id ? (value as ChatMessage) : item,
            ),
          );
          void loadConversations();
        } else if (
          event === 'chat.message_delete' &&
          value.conversation_id === conversationId
        ) {
          setMessagesList((current) =>
            current.map((item) =>
              item.id === value.id
                ? {
                    ...item,
                    content: null,
                    deleted_at: new Date().toISOString(),
                    media_attachments: [],
                    reactions: [],
                  }
                : item,
            ),
          );
          void loadConversations();
        } else if (event === 'chat.reaction') {
          if (!value.message_id || !value.account?.id || !value.reaction)
            return;
          const reaction = value as ChatReaction;
          setMessagesList((current) =>
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

          setMessagesList((current) =>
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
        } else if (event === 'chat.invitation') {
          void loadInvitations().catch(() => {
            setError('load');
          });
          void loadConversations();
        } else if (
          event !== 'chat.notification' &&
          event !== 'chat.read' &&
          event.startsWith('chat.')
        ) {
          void loadConversations();
          if (value.conversation_id === conversationId) void loadMessages();
        }
      }),
    [conversationId, loadConversations, loadInvitations, loadMessages],
  );

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
      history.push(`/chat/${response.data.id}`);
      setDirectAccount(null);
      setDirectAccountQuery('');
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [directAccount, history, loadConversations]);

  const send = useCallback(async () => {
    if (!conversationId || (!text.trim() && media.length === 0)) return;
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
      setMessagesList((current) =>
        current.some((item) => item.id === response.data.id)
          ? current.map((item) =>
              item.id === response.data.id ? response.data : item,
            )
          : [...current, response.data],
      );
      setText('');
      setMedia([]);
      setReplyToId(null);
      setEditingId(null);
    } catch {
      setError('send');
    } finally {
      setLoading(false);
    }
  }, [conversationId, editingId, media, replyToId, text]);

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
      void searchAccounts(value, setAccountResults);
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
      void searchAccounts(event.target.value, setGroupAccountResults);
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
      void searchAccounts(event.target.value, setInviteAccountResults);
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

  const handleSearchChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setSearchQuery(event.target.value);
    },
    [],
  );

  const handleSearchSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!searchQuery.trim()) return;
      void api()
        .get<ChatMessage[]>('/api/v1/chat/messages/search', {
          params: { q: searchQuery.trim(), limit: 40 },
        })
        .then((response) => {
          setSearchResults(response.data);
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
      history.push(`/chat/${response.data.id}`);
      setGroupTitle('');
      setGroupAccountQuery('');
      setGroupAccounts([]);
    } catch {
      setError('create');
    } finally {
      setLoading(false);
    }
  }, [groupAccounts, groupTitle, history, loadConversations]);

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
      if (
        !chatSettings ||
        files.length + media.length > chatSettings.max_attachments
      )
        return;
      event.target.value = '';
      setLoading(true);
      void Promise.all(
        files.map(async (file) => {
          const body = new FormData();
          body.append('file', file);
          const response = await api().post<ChatMedia>('/api/v2/media', body);
          return response.data;
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

      if (action === 'reply') {
        setReplyToId(id);
        setEditingId(null);
      } else if (action === 'edit') {
        setEditingId(id);
        setReplyToId(null);
        setText(message.content ?? '');
      } else if (action === 'delete') {
        void api().delete(`/api/v1/chat/messages/${id}`);
      }
    },
    [messagesList],
  );

  const handleEmojiPick = useCallback(
    (messageId: string, emoji: PickedEmoji) => {
      const reaction = reactionFromEmoji(emoji);

      if (!reaction) return;

      void api()
        .post<ChatReaction>(`/api/v1/chat/messages/${messageId}/reactions`, {
          reaction,
        })
        .then((response) => {
          setMessagesList((current) =>
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
        });
    },
    [],
  );

  const handleReactionClick = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const messageId = event.currentTarget.dataset.messageId;
      const reaction = event.currentTarget.dataset.reaction;
      const accountId = event.currentTarget.dataset.accountId;

      if (!messageId || !reaction || accountId !== me) return;

      void api()
        .delete(
          `/api/v1/chat/messages/${messageId}/reactions/${encodeURIComponent(reaction)}`,
        )
        .then(() => {
          setMessagesList((current) =>
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
        });
    },
    [],
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
    setEditingId(null);
    setText('');
  }, []);

  const handleInvitationAction = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      const id = event.currentTarget.dataset.invitationId;
      const action = event.currentTarget.dataset.action;
      if (!id || !action) return;
      void api()
        .post(`/api/v1/chat/invitations/${id}/${action}`)
        .then(() => {
          setInvitations((current) => current.filter((item) => item.id !== id));
          return loadConversations();
        });
    },
    [loadConversations],
  );

  const handleInviteSubmit = useCallback(
    (event: SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!conversationId || !inviteAccount) return;
      void api()
        .post(`/api/v1/chat/conversations/${conversationId}/invitations`, {
          account_id: inviteAccount.id,
        })
        .then(() => {
          setInviteAccount(null);
          setInviteAccountQuery('');
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
      void api()
        .patch<ChatConversation>(
          `/api/v1/chat/conversations/${conversationId}`,
          {
            title: title.trim(),
            description: description.trim(),
          },
        )
        .then(() => loadConversations())
        .catch(() => {
          setError('update');
        });
    },
    [conversation, conversationId, groupEdit, loadConversations],
  );

  const handlePolicyChange = useCallback(
    (event: ChangeEvent<HTMLSelectElement>) => {
      void api()
        .patch<ChatSettings>('/api/v1/chat/settings', {
          policy: event.target.value,
        })
        .then((response) => {
          setChatSettings(response.data);
        });
    },
    [],
  );

  const handleSettingToggle = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      const key = event.target.dataset.setting;
      if (!key) return;
      void api()
        .patch<ChatSettings>('/api/v1/chat/settings', {
          [key]: event.target.checked,
        })
        .then((response) => {
          setChatSettings(response.data);
        });
    },
    [],
  );

  const handleConversationAction = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      if (!conversationId || !conversation) return;
      const action = event.currentTarget.dataset.action;
      if (!action) return;
      if (action === 'mute' || action === 'unmute') {
        void api()
          .post(`/api/v1/chat/conversations/${conversationId}/${action}`)
          .then(() => loadConversations());
      } else if (action === 'archive' || action === 'unarchive') {
        void api()
          .post(`/api/v1/chat/conversations/${conversationId}/${action}`)
          .then(() => loadConversations());
      } else if (action === 'leave') {
        void api()
          .delete(`/api/v1/chat/conversations/${conversationId}/leave`)
          .then(() => {
            history.push('/chat');
            return loadConversations();
          });
      } else if (action === 'destroy') {
        void api()
          .delete(`/api/v1/chat/conversations/${conversationId}`)
          .then(() => {
            history.push('/chat');
            return loadConversations();
          });
      }
    },
    [conversation, conversationId, history, loadConversations],
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
          conversation
            ? conversationName(conversation)
            : intl.formatMessage(messages.heading)
        }
        multiColumn={multiColumn}
        showBackButton={Boolean(conversationId)}
      >
        {!conversationId && chatSettings && (
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
        {conversationId ? (
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
                    </span>
                  ))}
                </div>
              </section>
            )}
            <div className='chat-native__messages'>
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
                    <a
                      key={attachment.id}
                      href={attachment.url}
                      target='_blank'
                      rel='noopener noreferrer'
                    >
                      <img
                        src={attachment.preview_url}
                        alt={attachment.description ?? ''}
                      />
                    </a>
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
                          {reaction.reaction}
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
                  {!message.deleted_at && (
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
                      <span className='chat-native__react-picker'>
                        <ChatEmojiPicker
                          messageId={message.id}
                          onPick={handleEmojiPick}
                        />
                      </span>
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
            {conversation?.type === 'group' &&
              conversation.current_role === 'owner' && (
                <>
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
                          <strong>
                            {account.display_name || account.acct}
                          </strong>
                          <span>@{account.acct}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </>
              )}
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
                      <FormattedMessage
                        id='chat.replying_to'
                        defaultMessage='Replying to {account}'
                        values={{
                          account:
                            replyTarget?.account.display_name ??
                            replyTarget?.account.acct ??
                            '',
                        }}
                      />
                      <span>
                        {replyTarget?.content ??
                          intl.formatMessage({
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
              <textarea
                value={text}
                onChange={handleTextChange}
                placeholder={intl.formatMessage(messages.placeholder)}
                maxLength={4096}
              />
              <label className='button'>
                {intl.formatMessage(messages.attach)}
                <input
                  type='file'
                  hidden
                  onChange={handleMediaChange}
                  accept='image/*,video/*,audio/*'
                />
              </label>
              {media.length > 0 && (
                <div className='chat-native__media-preview'>
                  {media.map((attachment) => (
                    <div key={attachment.id}>
                      <img
                        src={attachment.preview_url}
                        alt={attachment.description ?? ''}
                      />
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
              <Button
                type='submit'
                disabled={
                  conversation?.archived ||
                  loading ||
                  (!text.trim() && media.length === 0)
                }
              >
                {intl.formatMessage(messages.send)}
              </Button>
            </form>
          </>
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
            {activeTab === 'home' && (
              <>
                <form
                  className='chat-native__new'
                  onSubmit={handleDirectSubmit}
                >
                  <h3>{intl.formatMessage(messages.newDirect)}</h3>
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
                <form className='chat-native__new' onSubmit={handleGroupSubmit}>
                  <h3>{intl.formatMessage(messages.newGroup)}</h3>
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
            {activeTab === 'invitations' && invitations.length > 0 && (
              <section className='chat-native__invitations'>
                <h3>
                  <FormattedMessage
                    id='chat.invitations'
                    defaultMessage='Invitations'
                  />
                </h3>
                {invitations.map((invitation) => (
                  <div key={invitation.id}>
                    <span>{conversationName(invitation.conversation)}</span>
                    <button
                      type='button'
                      data-invitation-id={invitation.id}
                      data-action='accept'
                      onClick={handleInvitationAction}
                    >
                      <FormattedMessage
                        id='chat.accept'
                        defaultMessage='Accept'
                      />
                    </button>
                    <button
                      type='button'
                      data-invitation-id={invitation.id}
                      data-action='reject'
                      onClick={handleInvitationAction}
                    >
                      <FormattedMessage
                        id='chat.reject'
                        defaultMessage='Reject'
                      />
                    </button>
                  </div>
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
            {activeTab === 'home' && (
              <>
                <form
                  className='chat-native__new chat-native__new--compact'
                  onSubmit={handleSearchSubmit}
                >
                  <input
                    value={searchQuery}
                    onChange={handleSearchChange}
                    placeholder={intl.formatMessage({
                      id: 'chat.search',
                      defaultMessage: 'Search messages',
                    })}
                  />
                  <Button type='submit' disabled={!searchQuery.trim()}>
                    <FormattedMessage
                      id='chat.search_action'
                      defaultMessage='Search'
                    />
                  </Button>
                </form>
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
                    data-conversation-id={item.id}
                    onClick={handleOpenConversation}
                  >
                    <strong>{conversationName(item)}</strong>
                    <span>{item.last_message?.content}</span>
                    {item.unread && <i aria-label='Unread' />}
                  </button>
                ))}
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
                        defaultMessage='There are no chat rooms here.'
                      />
                    )}
                  </div>
                )}
              </div>
            )}
          </>
        )}
        {error && (
          <div className='chat-native__error'>
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
