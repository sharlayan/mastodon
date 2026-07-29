import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PersonShieldIcon from '@/material-icons/400-24px/person_shield.svg?react';
import PreviewOffIcon from '@/material-icons/400-24px/preview_off.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Icon } from 'flavours/glitch/components/icon';

const messages = defineMessages({
  passwordVisibility: {
    id: 'pages.visibility.password',
    defaultMessage: 'Password protected',
  },
  authenticatedVisibility: {
    id: 'pages.visibility.authenticated',
    defaultMessage: 'Signed-in users only',
  },
  privateVisibility: {
    id: 'pages.visibility.private',
    defaultMessage: 'Only me',
  },
  main: { id: 'pages.main', defaultMessage: 'Main page' },
});

export const PageListItem: React.FC<{
  page: ApiPageJSON;
  showCategory?: boolean;
  active?: boolean;
  replaceHistory?: boolean;
}> = ({
  page,
  showCategory = true,
  active = false,
  replaceHistory = false,
}) => {
  const intl = useIntl();
  const location = useLocation();
  const headerUrl = page.eye_catching_media_attachment?.url;
  const pathname = `/@${page.account.acct}/pages/${encodeURIComponent(page.name)}`;

  return (
    <div
      className={classNames('lists__item', 'page-list-item', {
        'page-list-item--with-header': headerUrl,
        'page-list-item--active': active,
      })}
      style={
        headerUrl
          ? { backgroundImage: `url(${JSON.stringify(headerUrl)})` }
          : undefined
      }
    >
      <Link
        to={replaceHistory ? { pathname, state: location.state } : pathname}
        className='lists__item__title'
        aria-current={active ? 'page' : undefined}
        replace={replaceHistory}
      >
        <span className='page-list-item__details'>
          <Avatar account={page.account} size={32} />
          <span className='page-list-item__text'>
            <span className='page-list-item__title'>
              {page.is_main && (
                <Icon
                  id='home'
                  icon={HomeIcon}
                  className='page-list-item__main-icon'
                  aria-label={intl.formatMessage(messages.main)}
                />
              )}
              {page.visibility !== 'public' && (
                <Icon
                  id={
                    page.visibility === 'password'
                      ? 'lock'
                      : page.visibility === 'authenticated'
                        ? 'person-shield'
                        : 'preview-off'
                  }
                  icon={
                    page.visibility === 'password'
                      ? LockIcon
                      : page.visibility === 'authenticated'
                        ? PersonShieldIcon
                        : PreviewOffIcon
                  }
                  className='page-list-item__visibility-icon'
                  aria-label={intl.formatMessage(
                    page.visibility === 'password'
                      ? messages.passwordVisibility
                      : page.visibility === 'authenticated'
                        ? messages.authenticatedVisibility
                        : messages.privateVisibility,
                  )}
                />
              )}
              <span className='page-list-item__title-text'>
                {page.title || page.name}
              </span>
              {showCategory && page.category && (
                <>
                  {' · '}
                  <span className='page-list-item__category'>
                    {page.category}
                  </span>
                </>
              )}
              {page.page_series && (
                <>
                  {' · '}
                  <span className='page-list-item__series'>
                    {page.page_series.title}
                  </span>
                </>
              )}
            </span>
            <span className='page-list-item__author'>
              {page.account.display_name || page.account.username} · @
              {page.account.acct}
            </span>
          </span>
        </span>
      </Link>
    </div>
  );
};
