import type { ChangeEventHandler, SyntheticEvent } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PersonShieldIcon from '@/material-icons/400-24px/person_shield.svg?react';
import PreviewOffIcon from '@/material-icons/400-24px/preview_off.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Icon } from 'flavours/glitch/components/icon';

import type { PageMediaOpenHandler } from './blocks';
import { PageBlockList } from './blocks';
import { PageNoteFetchProvider } from './blocks/note_fetch_context';
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
  seriesMain: {
    id: 'pages.series.main',
    defaultMessage: 'Representative page',
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
        {page.category && (
          <span className='page__category'>{page.category}</span>
        )}
      </div>

      {page.summary && <p className='page__summary'>{page.summary}</p>}
      {page.page_series && (
        <aside className='page__series'>
          {page.page_series.cover_media_attachment && (
            <img
              className='page__series-cover'
              src={page.page_series.cover_media_attachment.url}
              alt=''
              decoding='async'
              loading='lazy'
            />
          )}
          <div className='page__series-details'>
            <strong>
              {page.page_series.title}
              {page.series_main && (
                <span className='page__series-main'>
                  {intl.formatMessage(messages.seriesMain)}
                </span>
              )}
            </strong>
            {page.page_series.description && (
              <p>{page.page_series.description}</p>
            )}
          </div>
        </aside>
      )}

      {page.locked ? (
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
          <PageShowFooter
            page={page}
            isOwner={isOwner}
            isBlogView={isBlogView}
            previousPage={previousPage}
            nextPage={nextPage}
            onLikeToggle={onLikeToggle}
            onMainToggle={onMainToggle}
          />
        </>
      )}
    </article>
  );
};
