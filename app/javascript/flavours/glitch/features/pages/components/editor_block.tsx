import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { length } from 'stringz';

import ArrowDownwardIcon from '@/material-icons/400-24px/arrow_downward.svg?react';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import type {
  ApiPageBlock,
  ApiPageBlockType,
} from 'flavours/glitch/api_types/pages';
import { Icon } from 'flavours/glitch/components/icon';
import { useAppDispatch } from 'flavours/glitch/store';

import { BlockAddButtons } from './block_add_buttons';
import { blockTypeMessages } from './block_messages';
import { ImageUploadField } from './image_upload_field';

export type PageBlockPatch = Record<string, unknown>;

const messages = defineMessages({
  moveUp: { id: 'pages.block.move_up', defaultMessage: 'Move up' },
  moveDown: { id: 'pages.block.move_down', defaultMessage: 'Move down' },
  remove: { id: 'pages.block.remove', defaultMessage: 'Remove block' },
  removeConfirmTitle: {
    id: 'pages.block.remove_confirm_title',
    defaultMessage: 'Delete this item?',
  },
  removeConfirm: {
    id: 'pages.block.remove_confirm',
    defaultMessage: 'Delete',
  },
  textPlaceholder: {
    id: 'pages.block.text_placeholder',
    defaultMessage: 'Write text (MFM supported)…',
  },
  characterCountWithSpaces: {
    id: 'pages.block.character_count_with_spaces',
    defaultMessage: 'With spaces: {count}',
  },
  characterCountWithoutSpaces: {
    id: 'pages.block.character_count_without_spaces',
    defaultMessage: 'Without spaces: {count}',
  },
  sectionPlaceholder: {
    id: 'pages.block.section_placeholder',
    defaultMessage: 'Section title',
  },
  notePlaceholder: {
    id: 'pages.block.note_placeholder',
    defaultMessage: 'Post ID or URL',
  },
  noUpscale: {
    id: 'pages.block.no_upscale',
    defaultMessage: 'Do not enlarge beyond the original size',
  },
});

const SECTION_CHILD_TYPES: ApiPageBlockType[] = ['text', 'image', 'note'];

interface EditorBlockProps {
  block: ApiPageBlock;
  depth: number;
  onUpdate: (id: string, patch: PageBlockPatch) => void;
  onRemove: (id: string) => void;
  onMove: (id: string, delta: number) => void;
  onAddChild: (parentId: string, type: ApiPageBlockType) => void;
  onMediaUploaded: (media: ApiMediaAttachmentJSON) => void;
  getMedia: (fileId: string | null) => ApiMediaAttachmentJSON | null;
}

export const EditorBlock: React.FC<EditorBlockProps> = ({
  block,
  depth,
  onUpdate,
  onRemove,
  onMove,
  onAddChild,
  onMediaUploaded,
  getMedia,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const blockId = block.id;
  const characterCount = block.type === 'text' ? length(block.text) : undefined;
  const characterCountWithoutSpaces =
    block.type === 'text' ? length(block.text.replace(/\s/gu, '')) : undefined;

  const handleMoveUp = useCallback(() => {
    onMove(blockId, -1);
  }, [onMove, blockId]);

  const handleMoveDown = useCallback(() => {
    onMove(blockId, 1);
  }, [onMove, blockId]);

  const handleRemove = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'CONFIRM',
        modalProps: {
          title: intl.formatMessage(messages.removeConfirmTitle),
          confirm: intl.formatMessage(messages.removeConfirm),
          onConfirm: () => {
            onRemove(blockId);
          },
        },
      }),
    );
  }, [dispatch, intl, onRemove, blockId]);

  const handleTextChange = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      onUpdate(blockId, { text: event.target.value });
    },
    [onUpdate, blockId],
  );

  const handleTitleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      onUpdate(blockId, { title: event.target.value });
    },
    [onUpdate, blockId],
  );

  const handleNoteChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const raw = event.target.value.trim();
      const match = /(\d+)\s*$/.exec(raw);
      onUpdate(blockId, { note: match?.[1] ?? (raw || null) });
    },
    [onUpdate, blockId],
  );

  const handleImageChange = useCallback(
    (media: ApiMediaAttachmentJSON | null) => {
      if (media) {
        onMediaUploaded(media);
      }

      onUpdate(blockId, { fileId: media?.id ?? null });
    },
    [onUpdate, onMediaUploaded, blockId],
  );

  const handleImageNoUpscaleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      onUpdate(blockId, { noUpscale: event.target.checked });
    },
    [onUpdate, blockId],
  );

  const handleAddChild = useCallback(
    (type: ApiPageBlockType) => {
      onAddChild(blockId, type);
    },
    [onAddChild, blockId],
  );

  return (
    <div className='page-editor__block'>
      <div className='page-editor__block__header'>
        <span className='page-editor__block__type'>
          {intl.formatMessage(blockTypeMessages[block.type])}
        </span>

        <div className='page-editor__block__controls'>
          <button
            type='button'
            title={intl.formatMessage(messages.moveUp)}
            onClick={handleMoveUp}
          >
            <Icon id='arrow-up' icon={ArrowUpwardIcon} />
          </button>
          <button
            type='button'
            title={intl.formatMessage(messages.moveDown)}
            onClick={handleMoveDown}
          >
            <Icon id='arrow-down' icon={ArrowDownwardIcon} />
          </button>
          <button
            type='button'
            className='page-editor__block__remove'
            title={intl.formatMessage(messages.remove)}
            onClick={handleRemove}
          >
            <Icon id='trash' icon={DeleteIcon} />
          </button>
        </div>
      </div>

      {block.type === 'text' && (
        <>
          <textarea
            className='page-editor__textarea'
            value={block.text}
            placeholder={intl.formatMessage(messages.textPlaceholder)}
            onChange={handleTextChange}
          />
          <div className='page-editor__character-count'>
            <span>
              {intl.formatMessage(messages.characterCountWithSpaces, {
                count: characterCount,
              })}
            </span>
            <span>
              {intl.formatMessage(messages.characterCountWithoutSpaces, {
                count: characterCountWithoutSpaces,
              })}
            </span>
          </div>
        </>
      )}

      {block.type === 'note' && (
        <input
          type='text'
          value={block.note ?? ''}
          placeholder={intl.formatMessage(messages.notePlaceholder)}
          onChange={handleNoteChange}
        />
      )}

      {block.type === 'image' && (
        <>
          <ImageUploadField
            value={getMedia(block.fileId)}
            onChange={handleImageChange}
          />
          <label className='page-editor__image-option'>
            <input
              type='checkbox'
              checked={block.noUpscale ?? false}
              onChange={handleImageNoUpscaleChange}
            />
            <span>{intl.formatMessage(messages.noUpscale)}</span>
          </label>
        </>
      )}

      {block.type === 'section' && (
        <div className='page-editor__section'>
          <input
            type='text'
            value={block.title}
            placeholder={intl.formatMessage(messages.sectionPlaceholder)}
            onChange={handleTitleChange}
          />

          <div className='page-editor__section__children'>
            {block.children.map((child) => (
              <EditorBlock
                key={child.id}
                block={child}
                depth={depth + 1}
                onUpdate={onUpdate}
                onRemove={onRemove}
                onMove={onMove}
                onAddChild={onAddChild}
                onMediaUploaded={onMediaUploaded}
                getMedia={getMedia}
              />
            ))}
          </div>

          <BlockAddButtons types={SECTION_CHILD_TYPES} onAdd={handleAddChild} />
        </div>
      )}
    </div>
  );
};
