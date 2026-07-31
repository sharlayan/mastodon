import type { ChangeEventHandler, SyntheticEvent } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PersonShieldIcon from '@/material-icons/400-24px/person_shield.svg?react';
import PreviewOffIcon from '@/material-icons/400-24px/preview_off.svg?react';
import PushPinFillIcon from '@/material-icons/400-24px/push_pin-fill.svg?react';
import PushPinIcon from '@/material-icons/400-24px/push_pin.svg?react';
import ShareIcon from '@/material-icons/400-24px/share.svg?react';
import VisibilityIcon from '@/material-icons/400-24px/visibility.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Icon } from 'flavours/glitch/components/icon';

import type { PageMediaOpenHandler } from './blocks';
import { PageBlockList } from './blocks';
import { PageNoteFetchProvider } from './blocks/note_fetch_context';
import { PageSeries } from './page_series';
import { PageShowFooter } from './page_show_footer';

const messages = defineMessages({
  password: { id: 'pages.password', defaultMessage: 'Password' },
  unlock: { id: 'pages.unlock', defaultMessage: 'View page' },
  invalidPassword: {
    id: 'pages.invalid_password',
    defaultMessage: 'The password is incorrect.',
  },
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
  viewsCount: {
    id: 'pages.views_count',
    defaultMessage: '{count, plural, one {# view} other {# views}}',
  },
});

export const PageShowContent: React.FC<{
  page: ApiPageJSON;
  isOwner: boolean;
  isBlogView: boolean;
  previousPage: ApiPageJSON | null;
  nextPage: ApiPageJSON | null;
  password: string;
  passwordError: boolean;
  unlocking: boolean;
  onPasswordChange: ChangeEventHandler<HTMLInputElement>;
  onUnlock: (event: SyntheticEvent<HTMLFormElement>) => void;
  onOpenMedia: PageMediaOpenHandler;
  onOpenEyeCatchingMedia: () => void;
  onLikeToggle: () => void;
  onMainToggle: () => void;
  onShare: () => void;
  onDelete: () => void;
}> = ({
  page,
  isOwner,
  isBlogView,
  previousPage,
  nextPage,
  password,
  passwordError,
  unlocking,
  onPasswordChange,
  onUnlock,
  onOpenMedia,
  onOpenEyeCatchingMedia,
  onLikeToggle,
  onMainToggle,
  onShare,
  onDelete,
}) => {
  const intl = useIntl();
  const eyeCatchingMedia = page.eye_catching_media_attachment;

  return (
    <article
      className={classNames('page', `page--font-${page.font}`, {
        'page--center': page.align_center,
        'page--blog': isBlogView,
      })}
    >
      <div
        className={classNames('page__eye-catching-container', {
          'page__eye-catching-container--without-media': !eyeCatchingMedia,
        })}
      >
        {eyeCatchingMedia && (
          <button
            type='button'
            className='page__media-button'
            onClick={onOpenEyeCatchingMedia}
          >
            {eyeCatchingMedia.type === 'gifv' ? (
              <video
                className='page__eye-catching'
                src={eyeCatchingMedia.url}
                aria-label={eyeCatchingMedia.description ?? ''}
                autoPlay
                loop
                muted
                playsInline
                preload='metadata'
              />
            ) : (
              <img
                className='page__eye-catching'
                src={eyeCatchingMedia.url}
                alt={eyeCatchingMedia.description ?? ''}
                decoding='async'
              />
            )}
          </button>
        )}
        <div className='page__eye-catching-author'>
          <Avatar account={page.account} size={32} withLink />
          <span className='page__eye-catching-author-text'>
            <strong>
              {page.account.display_name || page.account.username}
            </strong>
            <span>@{page.account.acct}</span>
          </span>
        </div>
      </div>

      <div className='page__title-row'>
        <h1 className='page__title'>
          {page.is_main && (
            <Icon
              id='home'
              icon={HomeIcon}
              className='page__main-icon'
              aria-label={intl.formatMessage(messages.main)}
            />
          )}
          <span className='page__title-text'>{page.title}</span>
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
              className='page__visibility-icon'
              aria-label={intl.formatMessage(
                page.visibility === 'password'
                  ? messages.passwordVisibility
                  : page.visibility === 'authenticated'
                    ? messages.authenticatedVisibility
                    : messages.privateVisibility,
              )}
            />
          )}
        </h1>
      </div>

      <div className='page__title-actions'>
        {isOwner && (
          <div className='page__title-actions__buttons'>
            <Link
              to={{
                pathname: `/pages/${page.id}/edit`,
                state: { fromPageShow: true, pageName: page.name },
              }}
              title={intl.formatMessage({
                id: 'pages.edit',
                defaultMessage: 'Edit page',
              })}
              aria-label={intl.formatMessage({
                id: 'pages.edit',
                defaultMessage: 'Edit page',
              })}
            >
              <Icon id='pencil' icon={EditIcon} />
            </Link>
            <button
              type='button'
              title={intl.formatMessage({
                id: 'pages.delete',
                defaultMessage: 'Delete page',
              })}
              aria-label={intl.formatMessage({
                id: 'pages.delete',
                defaultMessage: 'Delete page',
              })}
              onClick={onDelete}
            >
              <Icon id='trash' icon={DeleteIcon} />
            </button>
            {page.visibility === 'public' && !page.draft && (
              <>
                <button
                  type='button'
                  title={intl.formatMessage({
                    id: 'pages.share',
                    defaultMessage: 'Share',
                  })}
                  aria-label={intl.formatMessage({
                    id: 'pages.share',
                    defaultMessage: 'Share',
                  })}
                  onClick={onShare}
                >
                  <Icon id='share' icon={ShareIcon} />
                </button>
                <button
                  type='button'
                  title={intl.formatMessage(
                    page.is_main
                      ? {
                          id: 'pages.unset_main',
                          defaultMessage: 'Remove main page',
                        }
                      : {
                          id: 'pages.set_main',
                          defaultMessage: 'Set as main page',
                        },
                  )}
                  aria-pressed={page.is_main}
                  onClick={onMainToggle}
                >
                  <Icon
                    id='pin'
                    icon={page.is_main ? PushPinFillIcon : PushPinIcon}
                  />
                </button>
              </>
            )}
          </div>
        )}
        <span className='page__views-count'>
          <Icon id='visibility' icon={VisibilityIcon} />
          {intl.formatMessage(messages.viewsCount, {
            count: page.views_count,
          })}
        </span>
      </div>

      {page.summary && <p className='page__summary'>{page.summary}</p>}

      {page.locked ? (
        <>
          <form className='page__password-form' onSubmit={onUnlock}>
            <label htmlFor='page_access_password'>
              {intl.formatMessage(messages.password)}
            </label>
            <input
              id='page_access_password'
              type='password'
              minLength={8}
              maxLength={72}
              required
              autoComplete='current-password'
              value={password}
              onChange={onPasswordChange}
            />
            {passwordError && (
              <span className='page__password-error'>
                {intl.formatMessage(messages.invalidPassword)}
              </span>
            )}
            <button type='submit' className='button' disabled={unlocking}>
              {intl.formatMessage(messages.unlock)}
            </button>
          </form>
          <PageSeries page={page} />
        </>
      ) : (
        <>
          <div className='page__content'>
            <PageNoteFetchProvider key={page.id}>
              <PageBlockList
                blocks={page.content}
                page={page}
                depth={0}
                onOpenMedia={onOpenMedia}
              />
            </PageNoteFetchProvider>
          </div>
          <PageSeries page={page} />
          <PageShowFooter
            page={page}
            isOwner={isOwner}
            previousPage={previousPage}
            nextPage={nextPage}
            onLikeToggle={onLikeToggle}
          />
        </>
      )}
    </article>
  );
};
