import { useCallback, useMemo } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import CampaignIcon from '@/material-icons/400-24px/campaign.svg?react';
import ErrorIcon from '@/material-icons/400-24px/error.svg?react';
import InfoIcon from '@/material-icons/400-24px/info.svg?react';
import ReportIcon from '@/material-icons/400-24px/report.svg?react';
import WarningIcon from '@/material-icons/400-24px/warning.svg?react';
import { Icon } from 'flavours/glitch/components/icon';
import type {
  AllowedTagsType,
  OnAttributeHandler,
  OnElementHandler,
} from 'flavours/glitch/utils/html';
import { defaultAllowedTags } from 'flavours/glitch/utils/html';

export const BOARD_ALLOWED_TAGS: AllowedTagsType = {
  ...defaultAllowedTags,
  hr: { children: false },
  h6: {},
  table: {},
  thead: {},
  tbody: {},
  tfoot: {},
  caption: {},
  tr: {},
  th: {
    attributes: {
      colspan: 'colSpan',
      rowspan: 'rowSpan',
      scope: true,
      align: true,
    },
  },
  td: {
    attributes: { colspan: 'colSpan', rowspan: 'rowSpan', align: true },
  },
  div: { attributes: { align: true } },
  p: { attributes: { align: true } },
  input: {
    children: false,
    attributes: { type: true, checked: true, disabled: true },
  },
  details: { attributes: { open: true } },
  summary: {},
  dl: {},
  dt: {},
  dd: {},
  mark: {},
  kbd: {},
  ins: {},
  small: {},
};

const styleStringToObject = (style: string): React.CSSProperties => {
  const result: Record<string, string> = {};

  for (const declaration of style.split(';')) {
    const separator = declaration.indexOf(':');
    if (separator === -1) {
      continue;
    }

    const property = declaration.slice(0, separator).trim();
    const value = declaration.slice(separator + 1).trim();
    if (!property || !value) {
      continue;
    }

    const camelCased = property
      .toLowerCase()
      .replace(/-([a-z])/g, (_, letter: string) => letter.toUpperCase());
    result[camelCased] = value;
  }

  return result as React.CSSProperties;
};

export const handleBoardAttribute: OnAttributeHandler = (name, value) => {
  if (name === 'style') {
    return ['style', styleStringToObject(value)];
  }

  if (name === 'checked' || name === 'disabled') {
    return [name === 'checked' ? 'checked' : 'disabled', value !== 'false'];
  }

  return undefined;
};

const ALERT_TYPES = ['note', 'tip', 'important', 'warning', 'caution'] as const;

type AlertType = (typeof ALERT_TYPES)[number];

const ALERT_ICONS: Record<
  AlertType,
  React.FC<React.SVGProps<SVGSVGElement>>
> = {
  note: InfoIcon,
  tip: CampaignIcon,
  important: ReportIcon,
  warning: WarningIcon,
  caution: ErrorIcon,
};

const messages = defineMessages({
  note: { id: 'board_announcements.alert.note', defaultMessage: 'Note' },
  tip: { id: 'board_announcements.alert.tip', defaultMessage: 'Tip' },
  important: {
    id: 'board_announcements.alert.important',
    defaultMessage: 'Important',
  },
  warning: {
    id: 'board_announcements.alert.warning',
    defaultMessage: 'Warning',
  },
  caution: {
    id: 'board_announcements.alert.caution',
    defaultMessage: 'Caution',
  },
});

const alertTypeOf = (element: HTMLElement): AlertType | undefined =>
  ALERT_TYPES.find((type) =>
    element.parentElement?.classList.contains(`markdown-alert-${type}`),
  );

interface BoardAnnouncementHtmlProps {
  allowedTags: AllowedTagsType;
  onAttribute: OnAttributeHandler;
  onElement: OnElementHandler;
}

export const useBoardAnnouncementHtml = (): BoardAnnouncementHtmlProps => {
  const intl = useIntl();

  const onElement = useCallback<OnElementHandler>(
    (element, props) => {
      if (!element.classList.contains('markdown-alert-title')) {
        return undefined;
      }

      const type = alertTypeOf(element);

      if (!type) {
        return undefined;
      }

      return (
        <p key={props.key as string} className='markdown-alert-title'>
          <Icon
            id={`markdown-alert-${type}`}
            icon={ALERT_ICONS[type]}
            className='markdown-alert-icon'
          />
          {intl.formatMessage(messages[type])}
        </p>
      );
    },
    [intl],
  );

  return useMemo(
    () => ({
      allowedTags: BOARD_ALLOWED_TAGS,
      onAttribute: handleBoardAttribute,
      onElement,
    }),
    [onElement],
  );
};
