import { useEffect, useState, useCallback, useRef } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { useParams, Link } from 'react-router-dom';

import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import { useIdentity } from '@/flavours/glitch/identity_context';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import {
  apiGetPage,
  apiUnlockPage,
  apiGetAccountPages,
  apiDeletePage,
  apiLikePage,
  apiUnlikePage,
  apiSetMainPage,
  apiUnsetMainPage,
} from 'flavours/glitch/api/pages';
import type {
  ApiPageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';
import { Column } from 'flavours/glitch/components/column';
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
import { PageShowCategoryMenu } from './components/page_show_category_menu';
import { PageShowContent } from './components/page_show_content';
import { PageShowHeader } from './components/page_show_header';
import { PageShowSidebar } from './components/page_show_sidebar';

interface PageMediaEntry {
  key: string;
  media: ApiPageJSON['attached_media'][number];
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
  confirmDelete: {
    id: 'pages.delete_confirm',
    defaultMessage: 'Are you sure you want to delete this page?',
  },
  backToTop: { id: 'pages.back_to_top', defaultMessage: 'Back to top' },
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
  const [category, setCategory] = useState('');
  const [password, setPassword] = useState('');
  const [unlocking, setUnlocking] = useState(false);
  const [passwordError, setPasswordError] = useState(false);
  const [showBackToTop, setShowBackToTop] = useState(false);
  const scrollableRef = useRef<HTMLDivElement>(null);

  const updateBackToTopVisibility = useCallback(() => {
    const scrollTarget = multiColumn
      ? scrollableRef.current
      : document.scrollingElement;

    setShowBackToTop((scrollTarget?.scrollHeight ?? 0) > 1400);
  }, [multiColumn]);

  useEffect(() => {
    const scrollable = scrollableRef.current;

    if (!scrollable) {
      return;
    }

    const observer = new ResizeObserver(updateBackToTopVisibility);
    observer.observe(scrollable);
    Array.from(scrollable.children).forEach((child) => {
      observer.observe(child);
    });
    window.addEventListener('resize', updateBackToTopVisibility);
    const animationFrame = window.requestAnimationFrame(
      updateBackToTopVisibility,
    );

    return () => {
      observer.disconnect();
      window.removeEventListener('resize', updateBackToTopVisibility);
      window.cancelAnimationFrame(animationFrame);
    };
  }, [page, updateBackToTopVisibility]);

  const handleBackToTop = useCallback(() => {
    const scrollTarget = multiColumn
      ? scrollableRef.current
      : document.scrollingElement;

    scrollTarget?.scrollTo({ top: 0, behavior: 'smooth' });
  }, [multiColumn]);

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

  const handleMainToggle = useCallback(() => {
    if (!page) return;

    const request = page.is_main ? apiUnsetMainPage : apiSetMainPage;

    request(id)
      .then((data) => {
        setPage(data);
        setAccountPagesResult((result) =>
          result
            ? {
                ...result,
                pages: result.pages.map((accountPage) => ({
                  ...accountPage,
                  is_main: accountPage.id === data.id,
                })),
              }
            : result,
        );
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
  const filteredAccountPages = category
    ? visibleAccountPages.filter(
        (accountPage) => accountPage.category === category,
      )
    : visibleAccountPages;
  const currentPageIndex = visibleAccountPages.findIndex(
    (accountPage) => accountPage.id === id,
  );
  const previousPage =
    currentPageIndex > 0
      ? (visibleAccountPages[currentPageIndex - 1] ?? null)
      : null;
  const nextPage =
    currentPageIndex >= 0 && currentPageIndex < visibleAccountPages.length - 1
      ? (visibleAccountPages[currentPageIndex + 1] ?? null)
      : null;

  return (
    <Column
      bindToDocument={!multiColumn}
      className='page-show-column'
      label={title}
    >
      {currentPage ? (
        <>
          <PageShowHeader
            page={currentPage}
            accountId={accountId}
            isOwner={isOwner}
            isBlogView={useBlogView}
            isWideView={wideView}
            multiColumn={multiColumn}
            onBack={handleBack}
            onDelete={handleDelete}
            onReport={handleReport}
            onMainToggle={handleMainToggle}
            onWideViewToggle={handleWideViewToggle}
          />
          <div ref={scrollableRef} className='scrollable'>
            <PageShowCategoryMenu
              pages={visibleAccountPages}
              value={category}
              onChange={setCategory}
            />
            <div
              className={classNames('page-show__content', {
                'page-show__content--blog': useBlogView,
                'page-show__content--blog-right':
                  useBlogView && blogListPosition === 'right',
              })}
            >
              <PageShowSidebar
                page={currentPage}
                pages={filteredAccountPages}
                isBlogView={useBlogView}
              />
              <PageShowContent
                page={currentPage}
                isOwner={isOwner}
                isBlogView={useBlogView}
                previousPage={previousPage}
                nextPage={nextPage}
                password={password}
                passwordError={passwordError}
                unlocking={unlocking}
                onPasswordChange={handlePasswordChange}
                onUnlock={handleUnlock}
                onOpenMedia={handleOpenMedia}
                onOpenEyeCatchingMedia={handleOpenEyeCatchingMedia}
                onLikeToggle={handleLikeToggle}
                onMainToggle={handleMainToggle}
              />
            </div>
            {!useBlogView && !wideView && (
              <PageShowSidebar
                page={currentPage}
                pages={filteredAccountPages}
                isBlogView={false}
                position='bottom'
              />
            )}
            {useBlogView && (
              <PageShowCategoryMenu
                pages={visibleAccountPages}
                value={category}
                onChange={setCategory}
                position='bottom'
              />
            )}
            {useBlogView && (
              <footer className='page-show__blog-footer'>
                <Link to='/about'>{siteTitle ?? domain}</Link>
                {siteTitle && domain && <span>{domain}</span>}
              </footer>
            )}
          </div>
          {showBackToTop && (
            <button
              type='button'
              className='page-show__back-to-top'
              onClick={handleBackToTop}
            >
              <Icon id='arrow-upward' icon={ArrowUpwardIcon} />
              {intl.formatMessage(messages.backToTop)}
            </button>
          )}
        </>
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
