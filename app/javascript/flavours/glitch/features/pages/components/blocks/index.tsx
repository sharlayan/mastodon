import type {
  ApiPageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';

import { ImageBlock } from './image_block';
import { NoteBlock } from './note_block';
import { SectionBlock } from './section_block';
import { TextBlock } from './text_block';

export const PageBlock: React.FC<{
  block: ApiPageBlock;
  page: ApiPageJSON;
  depth: number;
}> = ({ block, page, depth }) => {
  switch (block.type) {
    case 'text':
      return <TextBlock block={block} />;
    case 'section':
      return <SectionBlock block={block} page={page} depth={depth} />;
    case 'image':
      return <ImageBlock block={block} page={page} />;
    case 'note':
      return <NoteBlock block={block} />;
  }
};

export const PageBlockList: React.FC<{
  blocks: ApiPageBlock[];
  page: ApiPageJSON;
  depth: number;
}> = ({ blocks, page, depth }) => (
  <>
    {blocks.map((block) => (
      <PageBlock key={block.id} block={block} page={page} depth={depth} />
    ))}
  </>
);
