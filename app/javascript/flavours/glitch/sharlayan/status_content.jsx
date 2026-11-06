import { FormattedMessage } from 'react-intl';

import { EmojiInfoTooltip } from '../components/emoji_info_tooltip';
import { MfmRenderer, mfmPlainTextFromHtml, shouldFoldMfm } from '../components/mfm';

export const sharlayanStatusContentState = (state) => ({
  localMfmEnabled: state.getIn(['meta', 'mfm_enabled']) !== false,
  localMfmAnimations: state.getIn(['meta', 'mfm_animations']) !== false,
  localMfmFoldMode: state.getIn(['meta', 'mfm_fold_mode']) ?? 'sensitive',
});

export const isSharlayanMfmStatus = (status, { mfmEnabled, localMfmEnabled }) =>
  status.get('mfm') && mfmEnabled !== false && localMfmEnabled !== false;

export const getSharlayanMfmSourceText = (status, content) => {
  const translation = status.get('translation');

  if (translation && !translation.get('isLoading')) {
    return mfmPlainTextFromHtml(content);
  }

  return status.get('mfm_text') ?? mfmPlainTextFromHtml(content);
};

export const renderSharlayanMfmContent = (status, { content, language, mfmEnabled, localMfmEnabled, localMfmAnimations, localMfmFoldMode }) => {
  if (!isSharlayanMfmStatus(status, { mfmEnabled, localMfmEnabled })) {
    return null;
  }

  const mfmAnimationsEnabled = localMfmAnimations !== false;
  const mfmFoldMode = localMfmFoldMode ?? 'sensitive';

  const mfmSourceText = getSharlayanMfmSourceText(status, content);
  const foldMfm = shouldFoldMfm(mfmSourceText, mfmFoldMode);

  const renderer = (
    <MfmRenderer text={mfmSourceText} emojis={status.get('emojis')} animationsEnabled={mfmAnimationsEnabled} />
  );

  return (
    <div className='status__content__text status__content__text--visible translate' lang={language}>
      {foldMfm ? (
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
