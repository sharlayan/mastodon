import { defineMessages } from 'react-intl';

export const blockTypeMessages = defineMessages({
  text: { id: 'pages.block_type.text', defaultMessage: 'Text' },
  section: { id: 'pages.block_type.section', defaultMessage: 'Section' },
  image: { id: 'pages.block_type.image', defaultMessage: 'Image' },
  note: { id: 'pages.block_type.note', defaultMessage: 'Post' },
  youtube: { id: 'pages.block_type.youtube', defaultMessage: 'YouTube video' },
});

export const addBlockMessages = defineMessages({
  text: { id: 'pages.add_block.text', defaultMessage: 'Add text' },
  section: { id: 'pages.add_block.section', defaultMessage: 'Add section' },
  image: { id: 'pages.add_block.image', defaultMessage: 'Add image' },
  note: { id: 'pages.add_block.note', defaultMessage: 'Add post' },
  youtube: {
    id: 'pages.add_block.youtube',
    defaultMessage: 'Add YouTube video',
  },
});
