import { defineMessages } from 'react-intl';

import BrushIcon from '@/material-icons/400-24px/brush.svg?react';

const messages = defineMessages({
  mfmLabel: { id: 'compose.content-type.mfm', defaultMessage: 'MFM' },
  mfmMeta: { id: 'compose.content-type.mfm_meta', defaultMessage: 'Format your posts using Markup language For Misskey' },
});

export const extendContentTypeOptions = (options, intl, mfmAllowComposition) => {
  if (mfmAllowComposition) {
    options.push({
      icon: 'brush',
      iconComponent: BrushIcon,
      value: 'text/x-mfm',
      text: intl.formatMessage(messages.mfmLabel),
      meta: intl.formatMessage(messages.mfmMeta),
    });
  }

  return options;
};

export const getSharlayanContentTypeIcon = (contentType) => contentType === 'text/x-mfm' ? {
  icon: 'brush',
  iconComponent: BrushIcon,
} : null;
