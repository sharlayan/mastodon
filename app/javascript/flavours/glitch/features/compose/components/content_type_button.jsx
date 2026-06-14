import { useCallback } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import SmallDescriptionIcon from '@/material-icons/400-20px/description.svg?react';
import SmallMarkdownIcon from '@/material-icons/400-20px/markdown.svg?react';
import BrushIcon from '@/material-icons/400-24px/brush.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import MarkdownIcon from '@/material-icons/400-24px/markdown.svg?react';
import { changeComposeContentType } from 'flavours/glitch/actions/compose';
import { mfmAllowComposition } from 'flavours/glitch/initial_state';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

import { DropdownIconButton } from './dropdown_icon_button';

const messages = defineMessages({
  change_content_type: { id: 'compose.content-type.change', defaultMessage: 'Change advanced formatting options' },
  plain_text_label: { id: 'compose.content-type.plain', defaultMessage: 'Plain text' },
  plain_text_meta: { id: 'compose.content-type.plain_meta', defaultMessage: 'Write with no advanced formatting' },
  markdown_label: { id: 'compose.content-type.markdown', defaultMessage: 'Markdown' },
  markdown_meta: { id: 'compose.content-type.markdown_meta', defaultMessage: 'Format your posts using Markdown' },
  mfm_label: { id: 'compose.content-type.mfm', defaultMessage: 'MFM' },
  mfm_meta: { id: 'compose.content-type.mfm_meta', defaultMessage: 'Format your posts using Markup language For Misskey' },
});

export const ContentTypeButton = () => {
  const intl = useIntl();

  const showButton = useAppSelector((state) => state.getIn(['local_settings', 'show_content_type_choice']));
  const contentType = useAppSelector((state) => state.getIn(['compose', 'content_type']));
  const dispatch = useAppDispatch();

  const handleChange = useCallback((value) => {
    dispatch(changeComposeContentType(value));
  }, [dispatch]);

  if (!showButton) {
    return null;
  }

  const options = [
    { icon: 'file-text', iconComponent: DescriptionIcon, value: 'text/plain', text: intl.formatMessage(messages.plain_text_label), meta: intl.formatMessage(messages.plain_text_meta) },
    { icon: 'arrow-circle-down', iconComponent: MarkdownIcon, value: 'text/markdown', text: intl.formatMessage(messages.markdown_label), meta: intl.formatMessage(messages.markdown_meta) },
  ];

  if (mfmAllowComposition) {
    options.push({ icon: 'brush', iconComponent: BrushIcon, value: 'text/x-mfm', text: intl.formatMessage(messages.mfm_label), meta: intl.formatMessage(messages.mfm_meta) });
  }

  const icon = {
    'text/plain': 'file-text',
    'text/markdown': 'arrow-circle-down',
    'text/x-mfm': 'brush',
  }[contentType] ?? 'file-text';

  const iconComponent = {
    'text/plain': SmallDescriptionIcon,
    'text/markdown': SmallMarkdownIcon,
    'text/x-mfm': BrushIcon,
  }[contentType] ?? SmallDescriptionIcon;

  return (
    <DropdownIconButton
      icon={icon}
      iconComponent={iconComponent}
      onChange={handleChange}
      options={options}
      title={intl.formatMessage(messages.change_content_type)}
      value={contentType}
    />
  );
};
