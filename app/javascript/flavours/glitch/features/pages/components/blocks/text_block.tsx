import type { ApiPageTextBlock } from 'flavours/glitch/api_types/pages';
import { MfmRenderer } from 'flavours/glitch/components/mfm';

import { Spoiler } from './spoiler';

const TextContent: React.FC<{ block: ApiPageTextBlock }> = ({ block }) => (
  <div className='page__block page__block--text'>
    <MfmRenderer text={block.text} />
  </div>
);

export const TextBlock: React.FC<{ block: ApiPageTextBlock }> = ({ block }) =>
  block.spoiler ? (
    <Spoiler className='page__block page__block--text-spoiler'>
      <TextContent block={block} />
    </Spoiler>
  ) : (
    <TextContent block={block} />
  );
