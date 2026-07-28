import PropTypes from 'prop-types';
import { useCallback, useMemo, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import { useHistory } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import { initBlockModal } from 'flavours/glitch/actions/blocks';
import { mentionCompose } from 'flavours/glitch/actions/compose';
import { setDirectReplyTo } from 'flavours/glitch/actions/direct_compose';
import { addReaction, removeReaction } from 'flavours/glitch/actions/interactions';
import { openModal } from 'flavours/glitch/actions/modal';
import { initMuteModal } from 'flavours/glitch/actions/mutes';
import { initReport } from 'flavours/glitch/actions/reports';
import { muteStatus, unmuteStatus, deleteStatus, editStatus } from 'flavours/glitch/actions/statuses';
import AttachmentList from 'flavours/glitch/components/attachment_list';
import { Avatar } from 'flavours/glitch/components/avatar';
import { ContentWarning } from 'flavours/glitch/components/content_warning';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import { AnimateEmojiProvider } from 'flavours/glitch/components/emoji/context';
import { RelativeTimestamp } from 'flavours/glitch/components/relative_timestamp';
import StatusContent from 'flavours/glitch/components/status_content';
import { StatusReactions } from 'flavours/glitch/components/status_reactions';
import { ParentQuote } from 'flavours/glitch/features/direct_timeline/components/parent_quote';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import Bundle from 'flavours/glitch/features/ui/components/bundle';
import { MediaGallery, Video, Audio } from 'flavours/glitch/features/ui/util/async-components';
import { me, deleteModal, reactionsEnabled } from 'flavours/glitch/initial_state';
import { makeGetStatus } from 'flavours/glitch/selectors';

const messages = defineMessages({
  more: { id: 'status.more', defaultMessage: 'More' },
  open: { id: 'status.open', defaultMessage: 'Expand this status' },
  copy: { id: 'status.copy', defaultMessage: 'Copy link to post' },
  edit: { id: 'status.edit', defaultMessage: 'Edit' },
  delete: { id: 'status.delete', defaultMessage: 'Delete' },
  redraft: { id: 'status.redraft', defaultMessage: 'Delete & re-draft' },
  mention: { id: 'status.mention', defaultMessage: 'Mention @{name}' },
  replyToMessage: { id: 'direct_conversation.reply_to_message', defaultMessage: 'Reply to this message' },
  mute: { id: 'account.mute', defaultMessage: 'Mute @{name}' },
  block: { id: 'account.block', defaultMessage: 'Block @{name}' },
  report: { id: 'status.report', defaultMessage: 'Report @{name}' },
  muteConversation: { id: 'status.mute_conversation', defaultMessage: 'Mute conversation' },
  unmuteConversation: { id: 'status.unmute_conversation', defaultMessage: 'Unmute conversation' },
  react: { id: 'status.react', defaultMessage: 'React' },
});

const getStatus = makeGetStatus();

const GROUP_TIME_GAP_MS = 5 * 60 * 1000;

const mentionStripParser = new DOMParser();

const handleTokenRegex = /^\s*@[\w]+(?:@[\w.-]+)?(?=\s|$)/;

const stripLeadingMentions = (html) => {
  if (!html) {
    return html;
  }

  const doc = mentionStripParser.parseFromString(html, 'text/html');
  const first = doc.body.firstElementChild;
  const container = first && first.tagName === 'P' ? first : doc.body;

  const isMention = (node) =>
    node.nodeType === Node.ELEMENT_NODE &&
    (node.matches('a.mention') || node.classList.contains('h-card'));

  let node = container.firstChild;
  let removedMention = false;

  while (node) {
    const next = node.nextSibling;

    if (isMention(node)) {
      node.remove();
      removedMention = true;
      node = next;
      continue;
    }

    if (node.nodeType === Node.TEXT_NODE && node.textContent.trim() === '') {
      node.remove();
      node = next;
      continue;
    }

    break;
  }

  if (node && node.nodeType === Node.TEXT_NODE) {
    let text = node.textContent;

    while (handleTokenRegex.test(text)) {
      text = text.replace(handleTokenRegex, '');
      removedMention = true;
    }

    if (removedMention) {
      node.textContent = text.replace(/^\s+/, '');
    }
  }

  if (!removedMention) {
    return html;
  }

  return doc.body.innerHTML;
};

const htmlIsEmpty = (html) => {
  if (!html) {
    return true;
  }

  const doc = mentionStripParser.parseFromString(html, 'text/html');

  return (doc.body.textContent || '').trim() === '';
};

const htmlIsSingleCustomEmoji = (html) => {
  if (!html) {
    return false;
  }

  const doc = mentionStripParser.parseFromString(html, 'text/html');
  let container = doc.body;
  const meaningfulNodes = (element) => Array.from(element.childNodes).filter(node =>
    node.nodeType !== Node.TEXT_NODE || node.textContent.trim() !== '');

  let nodes = meaningfulNodes(container);

  if (nodes.length === 1 && nodes[0].nodeType === Node.ELEMENT_NODE && nodes[0].tagName === 'P') {
    container = nodes[0];
    nodes = meaningfulNodes(container);
  }

  return nodes.length === 1 &&
    nodes[0].nodeType === Node.ELEMENT_NODE &&
    nodes[0].matches('img.emojione.custom-emoji');
};

const stripLeadingHandlesFromText = (text) => {
  if (!text) {
    return text;
  }

  let result = text;
  let removed = false;

  while (handleTokenRegex.test(result)) {
    result = result.replace(handleTokenRegex, '');
    removed = true;
  }

  return removed ? result.replace(/^\s+/, '') : text;
};

export const ChatMessage = ({ conversationId, statusId, prevStatusId, nextStatusId }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const history = useHistory();

  const status = useSelector(state => getStatus(state, { id: statusId }));
  const account = status ? status.get('account') : null;
  const prevAuthorId = useSelector(state => prevStatusId ? state.getIn(['statuses', prevStatusId, 'account']) : null);
  const nextAuthorId = useSelector(state => nextStatusId ? state.getIn(['statuses', nextStatusId, 'account']) : null);
  const prevCreatedAt = useSelector(state => prevStatusId ? state.getIn(['statuses', prevStatusId, 'created_at']) : null);
  const nextCreatedAt = useSelector(state => nextStatusId ? state.getIn(['statuses', nextStatusId, 'created_at']) : null);

  const [expanded, setExpanded] = useState(false);
  const [revealMedia, setRevealMedia] = useState(false);

  const handleExpandedToggle = useCallback(() => {
    setExpanded(value => !value);
  }, []);

  const handleToggleMediaVisibility = useCallback(() => {
    setRevealMedia(value => !value);
  }, []);

  const displayStatus = useMemo(() => {
    if (!status) {
      return status;
    }

    let next = status;
    const html = status.get('contentHtml');
    const translatedHtml = status.getIn(['translation', 'contentHtml']);
    const mfmText = status.get('mfm_text');

    if (html) {
      const stripped = stripLeadingMentions(html);

      if (!htmlIsEmpty(stripped)) {
        next = next.set('contentHtml', stripped);
      }
    }

    if (translatedHtml) {
      const stripped = stripLeadingMentions(translatedHtml);

      if (!htmlIsEmpty(stripped)) {
        next = next.setIn(['translation', 'contentHtml'], stripped);
      }
    }

    if (mfmText) {
      const stripped = stripLeadingHandlesFromText(mfmText);

      if (stripped.trim() !== '') {
        next = next.set('mfm_text', stripped);
      }
    }

    return next;
  }, [status]);

  if (!status || !account) {
    return null;
  }

  const authorId = account.get('id');
  const isOwnMessage = authorId === me;

  const createdAt = status.get('created_at');
  const gapExceedsThreshold = (a, b) =>
    !!a && !!b && Math.abs(new Date(b).getTime() - new Date(a).getTime()) > GROUP_TIME_GAP_MS;

  const isGroupStart = prevAuthorId !== authorId || gapExceedsThreshold(prevCreatedAt, createdAt);
  const isGroupEnd = nextAuthorId !== authorId || gapExceedsThreshold(createdAt, nextCreatedAt);

  const hasSpoiler = !!status.get('spoiler_text');
  const showContent = !hasSpoiler || expanded;
  const displayedHtml = displayStatus.getIn(['translation', 'contentHtml']) || displayStatus.get('contentHtml');
  const isSticker = !hasSpoiler &&
    status.get('media_attachments').isEmpty() &&
    !status.get('poll') &&
    htmlIsSingleCustomEmoji(displayedHtml);

  const signedIn = !!me;
  const reactions = status.get('reactions');
  const hasReactions = reactions && reactions.some(reaction => reaction.get('count') > 0);
  const canReact = signedIn && reactionsEnabled;

  const fullTime = intl.formatDate(status.get('created_at'), {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  });

  const handleOpen = () => {
    history.push(`/@${account.get('acct')}/${status.get('id')}`);
  };

  const handleCopy = () => {
    const url = status.get('url');

    if (url) {
      void navigator.clipboard.writeText(url);
    }
  };

  const handleEdit = () => {
    dispatch((_, getState) => {
      if (getState().getIn(['compose', 'text']).trim().length !== 0) {
        dispatch(openModal({ modalType: 'CONFIRM_EDIT_STATUS', modalProps: { statusId: status.get('id') } }));
      } else {
        dispatch(editStatus(status.get('id')));
      }
    });
  };

  const handleDelete = () => {
    if (deleteModal) {
      dispatch(openModal({ modalType: 'CONFIRM_DELETE_STATUS', modalProps: { statusId: status.get('id'), withRedraft: false } }));
    } else {
      dispatch(deleteStatus(status.get('id')));
    }
  };

  const handleRedraft = () => {
    if (deleteModal) {
      dispatch(openModal({ modalType: 'CONFIRM_DELETE_STATUS', modalProps: { statusId: status.get('id'), withRedraft: true } }));
    } else {
      dispatch(deleteStatus(status.get('id'), true));
    }
  };

  const handleMention = () => {
    dispatch(mentionCompose(account));
  };

  const handleReplyTo = () => {
    dispatch(setDirectReplyTo(conversationId, status.get('id')));
  };

  const handleConversationMute = () => {
    if (status.get('muted')) {
      dispatch(unmuteStatus(status.get('id')));
    } else {
      dispatch(muteStatus(status.get('id')));
    }
  };

  const handleMute = () => {
    dispatch(initMuteModal(account));
  };

  const handleBlock = () => {
    dispatch(initBlockModal(account));
  };

  const handleReport = () => {
    dispatch(initReport(account, status));
  };

  const handleReactionAdd = (id, name, url) => {
    dispatch(addReaction(id, name, url));
  };

  const handleReactionRemove = (id, name) => {
    dispatch(removeReaction(id, name));
  };

  const handleEmojiPick = (data) => {
    dispatch(addReaction(status.get('id'), data.native.replace(/:/g, ''), data.imageUrl));
  };

  const isSensitive = status.get('sensitive');
  const mediaVisible = !isSensitive || revealMedia;
  const language = status.getIn(['translation', 'language']) || status.get('language');

  const handleOpenMedia = (media, index) => {
    dispatch(openModal({ modalType: 'MEDIA', modalProps: { statusId: status.get('id'), media, index, lang: language } }));
  };

  const handleOpenVideo = (options) => {
    dispatch(openModal({ modalType: 'VIDEO', modalProps: { statusId: status.get('id'), media: status.getIn(['media_attachments', 0]), lang: language, options } }));
  };

  const renderMedia = () => {
    const attachments = status.get('media_attachments');

    if (attachments.size === 0) {
      return null;
    }

    const type = attachments.getIn([0, 'type']);

    if (attachments.some(item => item.get('type') === 'unknown')) {
      return <AttachmentList compact media={attachments} />;
    }

    if (['image', 'gifv'].includes(type) || attachments.size > 1) {
      return (
        <Bundle fetchComponent={MediaGallery} loading={() => null}>
          {Component => (
            <Component
              media={attachments}
              lang={language}
              sensitive={isSensitive}
              visible={mediaVisible}
              onToggleVisibility={handleToggleMediaVisibility}
              onOpenMedia={handleOpenMedia}
            />
          )}
        </Bundle>
      );
    }

    const attachment = attachments.get(0);
    const description = attachment.getIn(['translation', 'description']) || attachment.get('description');

    if (type === 'audio') {
      return (
        <Bundle fetchComponent={Audio} loading={() => null}>
          {Component => (
            <Component
              src={attachment.get('url')}
              alt={description}
              lang={language}
              poster={attachment.get('preview_url') || account.get('avatar_static')}
              backgroundColor={attachment.getIn(['meta', 'colors', 'background'])}
              foregroundColor={attachment.getIn(['meta', 'colors', 'foreground'])}
              accentColor={attachment.getIn(['meta', 'colors', 'accent'])}
              duration={attachment.getIn(['meta', 'original', 'duration'], 0)}
              sensitive={isSensitive}
              blurhash={attachment.get('blurhash')}
              visible={mediaVisible}
              onToggleVisibility={handleToggleMediaVisibility}
            />
          )}
        </Bundle>
      );
    }

    if (type === 'video') {
      return (
        <Bundle fetchComponent={Video} loading={() => null}>
          {Component => (
            <Component
              preview={attachment.get('preview_url')}
              frameRate={attachment.getIn(['meta', 'original', 'frame_rate'])}
              aspectRatio={`${attachment.getIn(['meta', 'original', 'width'])} / ${attachment.getIn(['meta', 'original', 'height'])}`}
              blurhash={attachment.get('blurhash')}
              src={attachment.get('url')}
              alt={description}
              lang={language}
              inline
              sensitive={isSensitive}
              visible={mediaVisible}
              onToggleVisibility={handleToggleMediaVisibility}
              onOpenVideo={handleOpenVideo}
            />
          )}
        </Bundle>
      );
    }

    return <AttachmentList compact media={attachments} />;
  };

  const username = account.get('username');
  const menu = [];

  menu.push({ text: intl.formatMessage(messages.replyToMessage), action: handleReplyTo });
  menu.push({ text: intl.formatMessage(messages.open), action: handleOpen });
  menu.push({ text: intl.formatMessage(messages.copy), action: handleCopy });
  menu.push(null);

  if (isOwnMessage) {
    menu.push({ text: intl.formatMessage(messages.edit), action: handleEdit });
    menu.push({ text: intl.formatMessage(messages.delete), action: handleDelete, dangerous: true });
    menu.push({ text: intl.formatMessage(messages.redraft), action: handleRedraft, dangerous: true });
  } else {
    menu.push({ text: intl.formatMessage(messages.mention, { name: username }), action: handleMention });
    menu.push({ text: intl.formatMessage(status.get('muted') ? messages.unmuteConversation : messages.muteConversation), action: handleConversationMute });
    menu.push(null);
    menu.push({ text: intl.formatMessage(messages.mute, { name: username }), action: handleMute, dangerous: true });
    menu.push({ text: intl.formatMessage(messages.block, { name: username }), action: handleBlock, dangerous: true });
    menu.push({ text: intl.formatMessage(messages.report, { name: username }), action: handleReport, dangerous: true });
  }

  return (
    <AnimateEmojiProvider
      as='article'
      className={classNames('chat-message', {
        'chat-message--own': isOwnMessage,
        'chat-message--group-start': isGroupStart,
        'chat-message--group-end': isGroupEnd,
        'chat-message--has-media': showContent && status.get('media_attachments').size > 0,
        'chat-message--sticker': isSticker,
      })}
      tabIndex={0}
    >
      <div className='chat-message__body'>
        <div className='chat-message__avatar'>
          {isGroupEnd && <Avatar account={account} size={40} />}
        </div>

        <div className='chat-message__content'>
          {status.get('in_reply_to_id') && <ParentQuote statusId={status.get('in_reply_to_id')} />}

          <div className='chat-message__row'>
            <div className='chat-message__bubble' title={fullTime}>
              <ContentWarning
                status={status}
                expanded={showContent}
                onClick={hasSpoiler ? handleExpandedToggle : undefined}
              />

              {showContent && (
                <>
                  <StatusContent status={displayStatus} />

                  {renderMedia()}
                </>
              )}
            </div>

            <div className='chat-message__actions'>
              {signedIn && reactionsEnabled && (
                <div className='chat-message__react' title={intl.formatMessage(messages.react)}>
                  <EmojiPickerDropdown onPickEmoji={handleEmojiPick} disabled={!canReact} />
                </div>
              )}

              <Dropdown
                status={status}
                items={menu}
                icon='ellipsis-h'
                iconComponent={MoreHorizIcon}
                size={18}
                direction='right'
                title={intl.formatMessage(messages.more)}
              />
            </div>
          </div>
        </div>
      </div>

      {hasReactions && (
        <StatusReactions
          statusId={status.get('id')}
          reactions={reactions}
          numVisible={8}
          addReaction={handleReactionAdd}
          removeReaction={handleReactionRemove}
          canReact={signedIn && reactionsEnabled}
        />
      )}

      {isGroupEnd && (
        <div className='chat-message__header'>
          <DisplayName account={account} variant='simple' />
          <span className='chat-message__time'>
            <RelativeTimestamp timestamp={status.get('created_at')} />
          </span>
        </div>
      )}
    </AnimateEmojiProvider>
  );
};

ChatMessage.propTypes = {
  conversationId: PropTypes.string.isRequired,
  statusId: PropTypes.string.isRequired,
  prevStatusId: PropTypes.string,
  nextStatusId: PropTypes.string,
};
