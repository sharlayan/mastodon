import type { ApiPageTextBlock } from 'flavours/glitch/api_types/pages';
import { MfmRenderer } from 'flavours/glitch/components/mfm';

export const TextBlock: React.FC<{ block: ApiPageTextBlock }> = ({ block }) => (
  <div className='page__block page__block--text'>
    <MfmRenderer text={block.text} />
  </div>
);
