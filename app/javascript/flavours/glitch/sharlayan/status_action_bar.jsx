import { defineMessages, useIntl } from 'react-intl';

import AddReactionIcon from '@/material-icons/400-24px/add_reaction.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import { IconButton } from 'flavours/glitch/components/icon_button';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';

const messages = defineMessages({
  react: { id: 'status.react', defaultMessage: 'React' },
  addToClip: { id: 'status.add_to_clip', defaultMessage: 'Add to clip' },
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
