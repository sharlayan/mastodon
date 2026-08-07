import { FormattedMessage } from 'react-intl';

import { EmojiInfoTooltip } from '../components/emoji_info_tooltip';
import { MfmRenderer, hasSensitiveFoldTags, hasAnyMfmFn, MFM_FOLD_LENGTH_THRESHOLD } from '../components/mfm';

const mfmDomParser = new DOMParser();

function extractPlainTextFromHtml(html) {
  const doc = mfmDomParser.parseFromString(html, 'text/html');
  for (const br of doc.querySelectorAll('br')) {
    br.replaceWith('\n');
  }
  for (const p of doc.querySelectorAll('p')) {
    p.after('\n');
  }
  return doc.body.textContent || '';
}

export const sharlayanStatusContentState = (state) => ({
  localMfmEnabled: state.getIn(['meta', 'mfm_enabled']) !== false,
  localMfmAnimations: state.getIn(['meta', 'mfm_animations']) !== false,
  localMfmFoldMode: state.getIn(['meta', 'mfm_fold_mode']) ?? 'sensitive',
});

export const isSharlayanMfmStatus = (status, { mfmEnabled, localMfmEnabled }) =>
  status.get('mfm') && mfmEnabled !== false && localMfmEnabled !== false;

export const renderSharlayanMfmContent = (status, { content, language, mfmEnabled, localMfmEnabled, localMfmAnimations, localMfmFoldMode }) => {
  if (!isSharlayanMfmStatus(status, { mfmEnabled, localMfmEnabled })) {
    return null;
  }

  const mfmAnimationsEnabled = localMfmAnimations !== false;
  const mfmFoldMode = localMfmFoldMode ?? 'sensitive';

  const mfmSourceText = status.get('mfm_text') || extractPlainTextFromHtml(content);
  const hasMfmFn = hasAnyMfmFn(mfmSourceText);
  const shouldFoldMfm = (
    (mfmFoldMode === 'all' && hasMfmFn) ||
    (mfmFoldMode === 'sensitive' && hasSensitiveFoldTags(mfmSourceText)) ||
    mfmSourceText.length > MFM_FOLD_LENGTH_THRESHOLD
  );

  const renderer = (
    <MfmRenderer text={mfmSourceText} emojis={status.get('emojis')} animationsEnabled={mfmAnimationsEnabled} />
  );

  return (
    <div className='status__content__text status__content__text--visible translate' lang={language}>
      {shouldFoldMfm ? (
        <details className='status__content__mfm-fold'>
          <summary>
            <FormattedMessage id='status.mfm_fold_expand' defaultMessage='Expand MFM post' />
          </summary>
          {renderer}
        </details>
      ) : renderer}
    </div>
  );
};

export const SharlayanStatusContentTooltip = ({ containerRef }) => (
  <EmojiInfoTooltip containerRef={containerRef} enabled />
);
