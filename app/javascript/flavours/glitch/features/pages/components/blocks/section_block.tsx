import type {
  ApiPageSectionBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';

import { PageBlockList } from './index';

export const SectionBlock: React.FC<{
  block: ApiPageSectionBlock;
  page: ApiPageJSON;
  depth: number;
}> = ({ block, page, depth }) => {
  const HeadingTag = `h${Math.min(depth + 2, 6)}` as React.ElementType;

  return (
    <section className='page__block page__block--section'>
      <HeadingTag className='page__section-title'>{block.title}</HeadingTag>
      <PageBlockList blocks={block.children} page={page} depth={depth + 1} />
    </section>
  );
};
