import { useEffect, useState, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import classNames from 'classnames';
import { useParams, Link } from 'react-router-dom';

import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import { useIdentity } from '@/flavours/glitch/identity_context';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import FavoriteIcon from '@/material-icons/400-24px/favorite-fill.svg?react';
import FavoriteBorderIcon from '@/material-icons/400-24px/favorite.svg?react';
import FlagIcon from '@/material-icons/400-24px/flag.svg?react';
import FullscreenIcon from '@/material-icons/400-24px/fullscreen.svg?react';
import FullscreenExitIcon from '@/material-icons/400-24px/fullscreen_exit.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PreviewOffIcon from '@/material-icons/400-24px/preview_off.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import {
  apiGetPage,
  apiUnlockPage,
  apiGetAccountPages,
  apiDeletePage,
  apiLikePage,
  apiUnlikePage,
} from 'flavours/glitch/api/pages';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import type {
  ApiPageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { FormattedDateWrapper } from 'flavours/glitch/components/formatted_date';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useAppHistory } from 'flavours/glitch/components/router';
import { BundleColumnError } from 'flavours/glitch/features/ui/components/bundle_column_error';
import {
  domain,
  ignoreOthersPagesView,
  title as siteTitle,
} from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';

import type { PageMediaOpenHandler } from './components/blocks';
import { PageBlockList } from './components/blocks';
import { PageListItem } from './components/page_list_item';

interface PageMediaEntry {
  key: string;
  media: ApiMediaAttachmentJSON;
}

const collectPageMedia = (page: ApiPageJSON): PageMediaEntry[] => {
  const entries: PageMediaEntry[] = [];

  if (page.eye_catching_media_attachment) {
    entries.push({
      key: 'eye-catching',
      media: page.eye_catching_media_attachment,
    });
  }

  const collectBlocks = (blocks: ApiPageBlock[]) => {
    for (const block of blocks) {
      if (block.type === 'image' && block.fileId) {
        const media = page.attached_media.find(
          (item) => item.id === block.fileId,
        );
        if (media) {
          entries.push({ key: `block:${block.id}`, media });
        }
      } else if (block.type === 'section') {
        collectBlocks(block.children);
      }
    }
  };

  collectBlocks(page.content);
  return entries;
};

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  edit: { id: 'pages.edit', defaultMessage: 'Edit page' },
  delete: { id: 'pages.delete', defaultMessage: 'Delete page' },
  confirmDelete: {
    id: 'pages.delete_confirm',
    defaultMessage: 'Are you sure you want to delete this page?',
  },
  like: { id: 'pages.like', defaultMessage: 'Like' },
  unlike: { id: 'pages.unlike', defaultMessage: 'Unlike' },
  wideView: { id: 'pages.wide_view', defaultMessage: 'Wide view' },
  exitWideView: {
    id: 'pages.exit_wide_view',
    defaultMessage: 'Exit wide view',
  },
  createdAt: { id: 'pages.created_at', defaultMessage: 'Created' },
  updatedAt: { id: 'pages.updated_at', defaultMessage: 'Updated' },
  report: { id: 'pages.report', defaultMessage: 'Report page' },
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
  privateVisibility: {
    id: 'pages.visibility.private',
    defaultMessage: 'Only me',
  },
});

const PageShow: React.FC<{
  multiColumn?: boolean;
  pageId?: string;
  initialPage?: ApiPageJSON;
}> = ({ multiColumn, pageId, initialPage }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const history = useAppHistory();
  const { accountId } = useIdentity();
  const { id: routeId } = useParams<{ id: string }>();
  const id = pageId ?? routeId;

  const [page, setPage] = useState<ApiPageJSON | null>(initialPage ?? null);
  const [accountPagesResult, setAccountPagesResult] = useState<{
    accountId: string;
    pages: ApiPageJSON[];
  } | null>(null);
  const [errorId, setErrorId] = useState<string | null>(null);
  const [wideView, setWideView] = useState(false);
  const [password, setPassword] = useState('');
  const [unlocking, setUnlocking] = useState(false);
  const [passwordError, setPasswordError] = useState(false);

  useEffect(() => {
    let active = true;

    apiGetPage(id)
      .then((data) => {
        if (active) {
          setPage(data);
        }

        return data;
      })
      .catch(() => {
        if (active) {
          setErrorId(id);
        }
      });

    return () => {
      active = false;
    };
  }, [id]);

  const currentPage = page?.id === id ? page : null;
  const currentPageAccountId = currentPage?.account_id;
  const error = errorId === id;
  const isOwner = !!currentPage && currentPage.account_id === accountId;
  const useBlogView =
    !!currentPage &&
    (isOwner || !ignoreOthersPagesView) &&
    currentPage.account.pages_view === 'blog';
  const blogListPosition =
    currentPage?.account.pages_blog_list_position ?? 'left';

  useEffect(() => {
    if (!currentPageAccountId) {
      return;
    }

    let active = true;

    apiGetAccountPages(currentPageAccountId)
      .then((data) => {
        if (active) {
          setAccountPagesResult({
            accountId: currentPageAccountId,
            pages: data,
          });
        }

        return data;
      })
      .catch(() => {
        if (active) {
          setAccountPagesResult({ accountId: currentPageAccountId, pages: [] });
        }
      });

    return () => {
      active = false;
    };
  }, [currentPageAccountId]);

  const handleDelete = useCallback(() => {
    if (!window.confirm(intl.formatMessage(messages.confirmDelete))) {
      return;
    }

    apiDeletePage(id)
      .then(() => {
        history.push('/pages');
        return undefined;
      })
      .catch(() => undefined);
  }, [id, history, intl]);

  const handleLikeToggle = useCallback(() => {
    if (!page) {
      return;
    }

    const request = page.liked ? apiUnlikePage : apiLikePage;

    request(id)
      .then((data) => {
        setPage(data);
        return data;
      })
      .catch(() => undefined);
  }, [id, page]);

  const handleWideViewToggle = useCallback(() => {
    setWideView((value) => !value);
  }, []);

  const handleUnlock = useCallback(
    (event: React.SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      setUnlocking(true);
      setPasswordError(false);

      apiUnlockPage(id, password)
        .then((data) => {
          setPage(data);
          setPassword('');
          setUnlocking(false);
          return data;
        })
        .catch(() => {
          setPasswordError(true);
          setUnlocking(false);
        });
    },
    [id, password],
  );

  const handlePasswordChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setPassword(event.target.value);
    },
    [],
  );

  const handleReport = useCallback(() => {
    if (!currentPage) {
      return;
    }

    dispatch(
      openModal({
        modalType: 'REPORT_PAGE',
        modalProps: { page: currentPage },
      }),
    );
  }, [currentPage, dispatch]);

  const handleBack = useCallback(() => {
    if (history.location.state?.fromMastodon) {
      history.goBack();
    } else {
      history.push('/pages');
    }
  }, [history]);

  const handleOpenMedia = useCallback<PageMediaOpenHandler>(
    (key) => {
      if (!currentPage) {
        return;
      }

      const entries = collectPageMedia(currentPage);
      const index = entries.findIndex((entry) => entry.key === key);

      dispatch(
        openModal({
          modalType: 'MEDIA',
          modalProps: {
            media: fromJS(entries.map((entry) => entry.media)),
            index: index < 0 ? 0 : index,
          },
        }),
      );
    },
    [currentPage, dispatch],
  );

  const handleOpenEyeCatchingMedia = useCallback(() => {
    handleOpenMedia('eye-catching');
  }, [handleOpenMedia]);

  useEffect(() => {
    const fullPageView = wideView || useBlogView;

    document.documentElement.classList.toggle('page-wide-view', fullPageView);
    document.body.classList.toggle('page-wide-view', fullPageView);
    document.documentElement.classList.toggle('page-blog-view', useBlogView);
    document.body.classList.toggle('page-blog-view', useBlogView);

    return () => {
      document.documentElement.classList.remove(
        'page-wide-view',
        'page-blog-view',
      );
      document.body.classList.remove('page-wide-view', 'page-blog-view');
    };
  }, [wideView, useBlogView]);

  if (error) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const eyeCatchingMedia = currentPage?.eye_catching_media_attachment;
  const title = currentPage
    ? currentPage.title
    : intl.formatMessage(messages.heading);
  const accountPages =
    accountPagesResult && accountPagesResult.accountId === currentPageAccountId
      ? accountPagesResult.pages
      : null;
  const visibleAccountPages = currentPage
    ? [
        ...(accountPages?.some((accountPage) => accountPage.id === id)
          ? []
          : [currentPage]),
        ...(accountPages ?? []),
      ]
    : [];
  const currentPageIndex = visibleAccountPages.findIndex(
    (accountPage) => accountPage.id === id,
  );
  const previousPage =
    currentPageIndex > 0 ? visibleAccountPages[currentPageIndex - 1] : null;
  const nextPage =
    currentPageIndex >= 0 && currentPageIndex < visibleAccountPages.length - 1
      ? visibleAccountPages[currentPageIndex + 1]
      : null;

  return (
    <Column
      bindToDocument={!multiColumn}
      className='page-show-column'
      label={title}
    >
      {!useBlogView && (
        <ColumnHeader
          title={title}
          icon='description'
          iconComponent={DescriptionIcon}
          multiColumn={multiColumn}
          showBackButton
          onBack={handleBack}
          extraButton={
            <>
              {isOwner && (
                <>
                  <Link
                    to={{
                      pathname: `/pages/${id}/edit`,
                      state: {
                        fromPageShow: true,
                        pageName: currentPage.name,
                      },
                    }}
                    className='column-header__button'
                    title={intl.formatMessage(messages.edit)}
                    aria-label={intl.formatMessage(messages.edit)}
                  >
                    <Icon id='pencil' icon={EditIcon} />
                  </Link>
                  <button
                    type='button'
                    className='column-header__button'
                    title={intl.formatMessage(messages.delete)}
                    aria-label={intl.formatMessage(messages.delete)}
                    onClick={handleDelete}
                  >
                    <Icon id='trash' icon={DeleteIcon} />
                  </button>
                </>
              )}
              {accountId && !isOwner && !currentPage?.locked && (
                <button
                  type='button'
                  className='column-header__button'
                  title={intl.formatMessage(messages.report)}
                  aria-label={intl.formatMessage(messages.report)}
                  onClick={handleReport}
                >
                  <Icon id='flag' icon={FlagIcon} />
                </button>
              )}
              <button
                type='button'
                className='column-header__button'
                title={intl.formatMessage(
                  wideView ? messages.exitWideView : messages.wideView,
                )}
                aria-label={intl.formatMessage(
                  wideView ? messages.exitWideView : messages.wideView,
                )}
                aria-pressed={wideView}
                onClick={handleWideViewToggle}
              >
                <Icon
                  id={wideView ? 'compress' : 'expand'}
                  icon={wideView ? FullscreenExitIcon : FullscreenIcon}
                />
              </button>
            </>
          }
        />
      )}

      {currentPage ? (
        <div className='scrollable'>
          {useBlogView && (
            <header className='page-show__blog-header'>
              <Link
                to={`/@${currentPage.account.acct}`}
                className='page-show__blog-owner'
                style={
                  currentPage.account.header
                    ? ({
                        '--page-blog-owner-header': `url(${JSON.stringify(currentPage.account.header)})`,
                      } as React.CSSProperties)
                    : undefined
                }
              >
                <Avatar account={currentPage.account} size={40} />
                <span className='page-show__blog-owner-text'>
                  <strong>
                    {currentPage.account.display_name ||
                      currentPage.account.username}
                  </strong>
                  <span>@{currentPage.account.acct}</span>
                </span>
              </Link>
              {accountId && (
                <nav
                  className='page-show__blog-navigation'
                  aria-label={intl.formatMessage({
                    id: 'pages.blog_header.navigation',
                    defaultMessage: 'Page links',
                  })}
                >
                  <Link to='/home'>
                    <FormattedMessage
                      id='pages.blog_header.home'
                      defaultMessage='Back to home timeline'
                    />
                  </Link>
                  <span aria-hidden='true'>|</span>
                  <Link to='/pages'>
                    <FormattedMessage
                      id='pages.blog_header.my_pages'
                      defaultMessage='Back to my pages'
                    />
                  </Link>
                  <span aria-hidden='true'>|</span>
                  <Link to={`/@${currentPage.account.acct}`}>
                    <FormattedMessage
                      id='pages.blog_header.owner_profile'
                      defaultMessage="Back to {user}'s profile"
                      values={{
                        user:
                          currentPage.account.display_name ||
                          currentPage.account.username,
                      }}
                    />
                  </Link>
                </nav>
              )}
            </header>
          )}
          <div
            className={classNames('page-show__content', {
              'page-show__content--blog': useBlogView,
              'page-show__content--blog-right':
                useBlogView && blogListPosition === 'right',
            })}
          >
            <aside
              className='page-show__sidebar'
              aria-label={intl.formatMessage({
                id: 'account.pages',
                defaultMessage: 'Pages',
              })}
            >
              <h2>
                <FormattedMessage id='account.pages' defaultMessage='Pages' />
              </h2>
              {useBlogView ? (
                <>
                  <ol className='page-show__blog-list'>
                    {visibleAccountPages.map((accountPage) => (
                      <li key={accountPage.id}>
                        <Link
                          to={`/@${accountPage.account.acct}/pages/${encodeURIComponent(accountPage.name)}`}
                          aria-current={
                            accountPage.id === id ? 'page' : undefined
                          }
                        >
                          {accountPage.title.length > 0
                            ? accountPage.title
                            : accountPage.name}
                        </Link>
                      </li>
                    ))}
                  </ol>
                  <div className='page-show__sidebar-list'>
                    {visibleAccountPages.map((accountPage) => (
                      <PageListItem
                        key={accountPage.id}
                        page={accountPage}
                        active={accountPage.id === id}
                        replaceHistory
                      />
                    ))}
                  </div>
                </>
              ) : (
                <div className='page-show__sidebar-list'>
                  {visibleAccountPages.map((accountPage) => (
                    <PageListItem
                      key={accountPage.id}
                      page={accountPage}
                      active={accountPage.id === id}
                      replaceHistory
                    />
                  ))}
                </div>
              )}
            </aside>
            <article
              className={classNames('page', `page--font-${currentPage.font}`, {
                'page--center': currentPage.align_center,
                'page--blog': useBlogView,
              })}
            >
              {eyeCatchingMedia && (
                <div className='page__eye-catching-container'>
                  <button
                    type='button'
                    className='page__media-button'
                    onClick={handleOpenEyeCatchingMedia}
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
                      />
                    ) : (
                      <img
                        className='page__eye-catching'
                        src={eyeCatchingMedia.url}
                        alt={eyeCatchingMedia.description ?? ''}
                      />
                    )}
                  </button>
                  <div className='page__eye-catching-author'>
                    <Avatar account={currentPage.account} size={32} withLink />
                    <span className='page__eye-catching-author-text'>
                      <strong>
                        {currentPage.account.display_name ||
                          currentPage.account.username}
                      </strong>
                      <span>@{currentPage.account.acct}</span>
                    </span>
                  </div>
                </div>
              )}

              <div className='page__title-row'>
                <h1 className='page__title'>
                  <span className='page__title-text'>{currentPage.title}</span>
                  {currentPage.visibility !== 'public' && (
                    <Icon
                      id={
                        currentPage.visibility === 'password'
                          ? 'lock'
                          : 'preview-off'
                      }
                      icon={
                        currentPage.visibility === 'password'
                          ? LockIcon
                          : PreviewOffIcon
                      }
                      className='page__visibility-icon'
                      aria-label={intl.formatMessage(
                        currentPage.visibility === 'password'
                          ? messages.passwordVisibility
                          : messages.privateVisibility,
                      )}
                    />
                  )}
                </h1>
                {currentPage.category && (
                  <span className='page__category'>{currentPage.category}</span>
                )}
              </div>

              {!eyeCatchingMedia && (
                <div className='page__byline-row'>
                  <Link
                    to={`/@${currentPage.account.acct}`}
                    className='page__byline'
                  >
                    @{currentPage.account.acct}
                  </Link>
                </div>
              )}

              {currentPage.summary && (
                <p className='page__summary'>{currentPage.summary}</p>
              )}

              {currentPage.locked ? (
                <form className='page__password-form' onSubmit={handleUnlock}>
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
                    onChange={handlePasswordChange}
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
                    <PageBlockList
                      blocks={currentPage.content}
                      page={currentPage}
                      depth={0}
                      onOpenMedia={handleOpenMedia}
                    />
                  </div>

                  <div className='page__footer'>
                    <dl className='page__dates'>
                      <div>
                        <dt>{intl.formatMessage(messages.createdAt)}</dt>
                        <dd>
                          <FormattedDateWrapper
                            value={currentPage.created_at}
                            year='numeric'
                            month='long'
                            day='2-digit'
                            hour='2-digit'
                            minute='2-digit'
                          />
                        </dd>
                      </div>
                      <div>
                        <dt>{intl.formatMessage(messages.updatedAt)}</dt>
                        <dd>
                          <FormattedDateWrapper
                            value={currentPage.updated_at}
                            year='numeric'
                            month='long'
                            day='2-digit'
                            hour='2-digit'
                            minute='2-digit'
                          />
                        </dd>
                      </div>
                    </dl>
                    <div className='page__footer-actions'>
                      {useBlogView && isOwner && (
                        <Link
                          to={{
                            pathname: `/pages/${id}/edit`,
                            state: {
                              fromPageShow: true,
                              pageName: currentPage.name,
                            },
                          }}
                          className='button page__edit-button'
                        >
                          <Icon id='pencil' icon={EditIcon} />
                          <FormattedMessage
                            id='pages.edit'
                            defaultMessage='Edit page'
                          />
                        </Link>
                      )}
                      <button
                        type='button'
                        className={classNames('page__like-button', {
                          active: currentPage.liked,
                        })}
                        onClick={handleLikeToggle}
                        disabled={isOwner}
                      >
                        <Icon
                          id='favorite'
                          icon={
                            currentPage.liked
                              ? FavoriteIcon
                              : FavoriteBorderIcon
                          }
                        />
                        <span>
                          <FormattedMessage
                            id='pages.likes_count'
                            defaultMessage='{count, plural, one {# like} other {# likes}}'
                            values={{ count: currentPage.likes_count }}
                          />
                        </span>
                      </button>
                    </div>
                  </div>
                </>
              )}
              {useBlogView && Boolean(previousPage ?? nextPage) && (
                <nav
                  className='page__pagination'
                  aria-label={intl.formatMessage({
                    id: 'pages.pagination',
                    defaultMessage: 'Page navigation',
                  })}
                >
                  {previousPage ? (
                    <Link
                      className='page__link-prev'
                      to={`/@${previousPage.account.acct}/pages/${encodeURIComponent(previousPage.name)}`}
                    >
                      <FormattedMessage
                        id='pages.previous'
                        defaultMessage='Previous page'
                      />
                    </Link>
                  ) : (
                    <span />
                  )}
                  {nextPage && (
                    <Link
                      className='page__link-next'
                      to={`/@${nextPage.account.acct}/pages/${encodeURIComponent(nextPage.name)}`}
                    >
                      <FormattedMessage
                        id='pages.next'
                        defaultMessage='Next page'
                      />
                    </Link>
                  )}
                </nav>
              )}
            </article>
          </div>
          {useBlogView && (
            <footer className='page-show__blog-footer'>
              <Link to='/about'>{siteTitle ?? domain}</Link>
              {siteTitle && domain && <span>{domain}</span>}
            </footer>
          )}
        </div>
      ) : (
        <LoadingIndicator />
      )}

      <Helmet>
        <title>{title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default PageShow;
