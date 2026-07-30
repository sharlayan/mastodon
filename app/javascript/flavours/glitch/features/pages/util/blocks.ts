import type { ApiPageBlock } from 'flavours/glitch/api_types/pages';
import { uuid } from 'flavours/glitch/uuid';

export type PageBlockType = ApiPageBlock['type'];

export const createBlock = (type: PageBlockType): ApiPageBlock => {
  const id = uuid();

  switch (type) {
    case 'text':
      return { id, type: 'text', text: '', format: 'mfm', spoiler: false };
    case 'section':
      return { id, type: 'section', title: '', children: [] };
    case 'image':
      return {
        id,
        type: 'image',
        fileId: null,
        noUpscale: false,
        spoiler: false,
      };
    case 'note':
      return { id, type: 'note', note: null, detailed: false };
    case 'youtube':
      return { id, type: 'youtube', url: '', size: 'medium' };
  }
};

export const updateBlockInTree = (
  blocks: ApiPageBlock[],
  id: string,
  updater: (block: ApiPageBlock) => ApiPageBlock,
): ApiPageBlock[] =>
  blocks.map((block) => {
    if (block.id === id) {
      return updater(block);
    }

    if (block.type === 'section') {
      return {
        ...block,
        children: updateBlockInTree(block.children, id, updater),
      };
    }

    return block;
  });

export const removeBlockFromTree = (
  blocks: ApiPageBlock[],
  id: string,
): ApiPageBlock[] =>
  blocks
    .filter((block) => block.id !== id)
    .map((block) =>
      block.type === 'section'
        ? { ...block, children: removeBlockFromTree(block.children, id) }
        : block,
    );

export const moveBlockInTree = (
  blocks: ApiPageBlock[],
  id: string,
  delta: number,
): ApiPageBlock[] => {
  const index = blocks.findIndex((block) => block.id === id);

  if (index !== -1) {
    const target = index + delta;

    if (target < 0 || target >= blocks.length) {
      return blocks;
    }

    const next = [...blocks];
    const [moved] = next.splice(index, 1);

    if (moved) {
      next.splice(target, 0, moved);
    }

    return next;
  }

  return blocks.map((block) =>
    block.type === 'section'
      ? { ...block, children: moveBlockInTree(block.children, id, delta) }
      : block,
  );
};
