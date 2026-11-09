import { FormattedMessage } from 'react-intl';

import {
  MfmRenderer,
  mfmPlainTextFromHtml,
  shouldFoldMfm,
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

  return mfmPlainTextFromHtml(content);
}

export function useRedesignMfmContent(
  status: AnyStatusShape,
  content: string,
  authorAcct?: string | null,
) {
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
  const fold = shouldFoldMfm(source, foldMode);
  const renderer = (
    <MfmRenderer
      text={source}
      emojis={status.emojis}
      animationsEnabled={animations}
      mentions={status.mentions}
      authorAcct={authorAcct}
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
