import type {
  ApiPageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';

import { ImageBlock } from './image_block';
import { NoteBlock } from './note_block';
import { SectionBlock } from './section_block';
import { TextBlock } from './text_block';
import { YoutubeBlock } from './youtube_block';

export type PageMediaOpenHandler = (key: string, isolated?: boolean) => void;

export const PageBlock: React.FC<{
  block: ApiPageBlock;
  page: ApiPageJSON;
  depth: number;
  onOpenMedia: PageMediaOpenHandler;
}> = ({ block, page, depth, onOpenMedia }) => {
  switch (block.type) {
    case 'text':
      return <TextBlock block={block} />;
    case 'section':
      return (
        <SectionBlock
          block={block}
          page={page}
          depth={depth}
          onOpenMedia={onOpenMedia}
        />
      );
    case 'image':
      return <ImageBlock block={block} page={page} onOpenMedia={onOpenMedia} />;
    case 'note':
      return <NoteBlock block={block} />;
    case 'youtube':
      return <YoutubeBlock block={block} />;
  }
};

export const PageBlockList: React.FC<{
  blocks: ApiPageBlock[];
  page: ApiPageJSON;
  depth: number;
  onOpenMedia: PageMediaOpenHandler;
}> = ({ blocks, page, depth, onOpenMedia }) => (
  <>
    {blocks.map((block) => (
      <PageBlock
        key={block.id}
        block={block}
        page={page}
        depth={depth}
        onOpenMedia={onOpenMedia}
      />
    ))}
  </>
);
