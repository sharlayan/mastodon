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
import { openModal } from 'flavours/glitch/actions/modal';
import {
  apiGetPage,
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
});

const PageShow: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const history = useAppHistory();
  const { accountId } = useIdentity();
  const { id } = useParams<{ id: string }>();

  const [page, setPage] = useState<ApiPageJSON | null>(null);
  const [accountPagesResult, setAccountPagesResult] = useState<{
    accountId: string;
    pages: ApiPageJSON[];
  } | null>(null);
  const [errorId, setErrorId] = useState<string | null>(null);
  const [wideView, setWideView] = useState(false);

  useEffect(() => {
    document.documentElement.classList.toggle('page-wide-view', wideView);
    document.body.classList.toggle('page-wide-view', wideView);

    return () => {
      document.documentElement.classList.remove('page-wide-view');
      document.body.classList.remove('page-wide-view');
    };
  }, [wideView]);

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

  if (error) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const isOwner = !!currentPage && currentPage.account_id === accountId;
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

  return (
    <Column
      bindToDocument={!multiColumn}
      className='page-show-column'
      label={title}
    >
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
                    state: { fromPageShow: true },
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
            {accountId && !isOwner && (
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

      {currentPage ? (
        <div className='scrollable'>
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
          </aside>
          <article
            className={classNames('page', `page--font-${currentPage.font}`, {
              'page--center': currentPage.align_center,
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
              <h1 className='page__title'>{currentPage.title}</h1>
              {currentPage.category && (
                <span className='page__category'>{currentPage.category}</span>
              )}
            </div>

            {(!eyeCatchingMedia || currentPage.draft) && (
              <div className='page__byline-row'>
                {!eyeCatchingMedia && (
                  <Link
                    to={`/@${currentPage.account.acct}`}
                    className='page__byline'
                  >
                    @{currentPage.account.acct}
                  </Link>
                )}
                {currentPage.draft && (
                  <span className='page__draft'>
                    <FormattedMessage id='pages.draft' defaultMessage='Draft' />
                  </span>
                )}
              </div>
            )}

            {currentPage.summary && (
              <p className='page__summary'>{currentPage.summary}</p>
            )}

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
                  icon={currentPage.liked ? FavoriteIcon : FavoriteBorderIcon}
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
          </article>
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
