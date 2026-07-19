import { defineMessages, useIntl } from 'react-intl';

import AddReactionIcon from '@/material-icons/400-24px/add_reaction.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import { IconButton } from 'flavours/glitch/components/icon_button';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import { adminTimelineOwnerViewer, roleplayMode, softHideDeletion } from 'flavours/glitch/sharlayan/roleplay';

const messages = defineMessages({
  react: { id: 'status.react', defaultMessage: 'React' },
  addToClip: { id: 'status.add_to_clip', defaultMessage: 'Add to clip' },
  deleteAdmin: { id: 'status.delete_admin', defaultMessage: 'Delete (Admin)' },
  purgeAdmin: { id: 'status.purge_admin', defaultMessage: 'Remove' },
  direct: { id: 'status.direct', defaultMessage: 'Privately mention @{name}' },
  directDm: { id: 'status.direct_dm', defaultMessage: 'Send DM to @{name}' },
});

const noop = () => {}; // EmojiPickerDropdown handles the click on the react button

export const sharlayanAddToClipMenuItem = (intl, { enabled, statusId, dispatch }) => {
  if (!enabled) {
    return null;
  }

  return {
    text: intl.formatMessage(messages.addToClip),
    action: () => dispatch(openModal({
      modalType: 'CLIP_ADD',
      modalProps: { statusId },
    })),
  };
};

export const sharlayanRoleplayStatusAction = ({
  status,
  writtenByMe,
  isRemote,
  roleplayEnabled = roleplayMode,
  softHideEnabled = softHideDeletion,
  ownerViewer = adminTimelineOwnerViewer,
}) => {
  if (!roleplayEnabled || !softHideEnabled || !ownerViewer || isRemote) {
    return null;
  }

  if (status.get('rp_hidden')) {
    return 'purge';
  }

  return writtenByMe ? null : 'delete';
};

export const sharlayanRoleplayStatusMenuItem = (intl, action, onDelete) => {
  if (!action) {
    return null;
  }

  return {
    text: intl.formatMessage(action === 'purge' ? messages.purgeAdmin : messages.deleteAdmin),
    action: onDelete,
    dangerous: true,
  };
};

export const sharlayanDirectMessage = (intl, name) => intl.formatMessage(
  roleplayMode ? messages.directDm : messages.direct,
  { name },
);

const ReactionButton = ({ status, onReactionAdd, canReact, wrapperClassName, buttonClassName, dropdownClassName, inverted }) => {
  const intl = useIntl();

  const handleEmojiPick = data => {
    onReactionAdd(status.get('id'), data.native.replace(/:/g, ''), data.imageUrl);
  };

  const reactButton = (
    <IconButton
      className={buttonClassName}
      onClick={noop}
      title={intl.formatMessage(messages.react)}
      disabled={!canReact}
      icon='add_reaction'
      iconComponent={AddReactionIcon}
    />
  );

  return (
    <div className={wrapperClassName}>
      {canReact
        ? <EmojiPickerDropdown className={dropdownClassName} onPickEmoji={handleEmojiPick} button={reactButton} disabled={!canReact} inverted={inverted} />
        : reactButton}
    </div>
  );
};

export const SharlayanStatusReactionButton = ({ enabled, ...props }) => {
  if (!enabled) {
    return null;
  }

  return <ReactionButton {...props} />;
};
