import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import { openModal } from 'flavours/glitch/actions/modal';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

const MFM_DOC_URL = 'https://misskey-hub.net/en/docs/for-users/features/mfm/';

export const MfmComposeHint = () => {
  const dispatch = useAppDispatch();
  const contentType = useAppSelector((state) => state.getIn(['compose', 'content_type']));
  const text = useAppSelector((state) => state.getIn(['compose', 'text']));
  const hidden = useAppSelector((state) => state.getIn(['local_settings', 'hide_mfm_compose_hint']));

  const handlePreview = useCallback(() => {
    dispatch(openModal({
      modalType: 'MFM_PREVIEW',
      modalProps: { text },
    }));
  }, [dispatch, text]);

  if (contentType !== 'text/x-mfm' || hidden) {
    return null;
  }

  return (
    <div className='compose-form__mfm-hint'>
      <button type='button' className='compose-form__mfm-hint__preview' onClick={handlePreview}>
        <FormattedMessage id='compose_form.mfm.preview' defaultMessage='Preview' />
      </button>

      <a className='compose-form__mfm-hint__docs' href={MFM_DOC_URL} target='_blank' rel='noopener noreferrer'>
        <FormattedMessage id='compose_form.mfm.syntax_docs' defaultMessage='MFM syntax' />
      </a>
    </div>
  );
};
