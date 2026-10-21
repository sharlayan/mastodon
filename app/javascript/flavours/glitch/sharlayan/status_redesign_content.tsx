import { FormattedMessage } from 'react-intl';

import {
  MfmRenderer,
  hasAnyMfmFn,
  hasSensitiveFoldTags,
  MFM_FOLD_LENGTH_THRESHOLD,
} from '@/flavours/glitch/components/mfm';
import { mfmEnabled } from '@/flavours/glitch/initial_state';
import type { AnyStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';

const stopNavigation: React.MouseEventHandler<HTMLElement> = (event) => {
  event.stopPropagation();
};

export function redesignMfmSource(status: AnyStatusShape, content: string) {
  if (
    status.mfm_text != null &&
    !(status.translation && !status.translation.isLoading)
  ) {
    return status.mfm_text;
  }

  const doc = new DOMParser().parseFromString(content, 'text/html');
  for (const br of doc.querySelectorAll('br')) br.replaceWith('\n');
  for (const paragraph of doc.querySelectorAll('p')) paragraph.after('\n');
  return doc.body.textContent;
}

export function useRedesignMfmContent(status: AnyStatusShape, content: string) {
  const enabled = useAppSelector(
    (state) => state.meta.get('mfm_enabled') !== false,
  );
  const animations = useAppSelector(
    (state) => state.meta.get('mfm_animations') !== false,
  );
  const foldMode = useAppSelector(
    (state) => state.meta.get('mfm_fold_mode', 'sensitive') as string,
  );

  if (!status.mfm || !mfmEnabled || !enabled) return null;

  const source = redesignMfmSource(status, content);
  const fold =
    (foldMode === 'all' && hasAnyMfmFn(source)) ||
    (foldMode === 'sensitive' && hasSensitiveFoldTags(source)) ||
    source.length > MFM_FOLD_LENGTH_THRESHOLD;
  const renderer = (
    <MfmRenderer
      text={source}
      emojis={status.emojis}
      animationsEnabled={animations}
    />
  );

  return fold ? (
    <details className='status__content__mfm-fold'>
      <summary onClick={stopNavigation}>
        <FormattedMessage
          id='status.mfm_fold_expand'
          defaultMessage='Expand MFM post'
        />
      </summary>
      {renderer}
    </details>
  ) : (
    renderer
  );
}
