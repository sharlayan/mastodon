import { useEffect, useState, useCallback, useRef } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { useParams, Link } from 'react-router-dom';

import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';
import { isAxiosError } from 'axios';

import { useIdentity } from '@/flavours/glitch/identity_context';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import { showAlert, showAlertForError } from 'flavours/glitch/actions/alerts';
import { openModal } from 'flavours/glitch/actions/modal';
import {
  apiGetPage,
  apiUnlockPage,
  apiGetAccountPages,
  apiGetAccountBookletPages,
  apiDeletePage,
  apiLikePage,
  apiUnlikePage,
  apiSetMainPage,
  apiUnsetMainPage,
  PAGE_LIST_MAX_LIMIT,
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
  pageBlogViewAccount,
  pageBlogViewSkin,
  pageBlogViewViewerSkin,
  pageBlogViewColorSchemes,
  colorScheme,
  title as siteTitle,
} from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';
import { pageBlogThemeNeedsReload } from 'flavours/glitch/utils/page_blog_theme';
import { applyPageColorScheme } from 'flavours/glitch/utils/theme';
import type { ColorScheme } from 'flavours/glitch/utils/theme';

import type { PageMediaOpenHandler } from './components/blocks';
import { PageShowContent } from './components/page_show_content';
import { PageShowHeader } from './components/page_show_header';
import { PageShowSidebar } from './components/page_show_sidebar';

interface PageMediaEntry {
  key: string;
  media: ApiPageJSON['attached_media'][number];
}

const flattenPageBlocks = (blocks: ApiPageBlock[]): ApiPageBlock[] =>
  blocks.flatMap((block) =>
    block.type === 'section'
      ? [block, ...flattenPageBlocks(block.children)]
      : [block],
  );

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
      if (block.type === 'image' && block.fileId && !block.spoiler) {
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

const colorSchemeStorageKey = 'mastodon-page-color-scheme';

const readStoredColorScheme = (supported: ColorScheme[]): ColorScheme => {
  let stored: string | null = null;

  try {
    stored = localStorage.getItem(colorSchemeStorageKey);
  } catch {
    stored = null;
  }

  if (stored && (supported as string[]).includes(stored)) {
    return stored as ColorScheme;
  }

  return supported.includes('auto') ? 'auto' : (supported[0] ?? 'auto');
};

const storeColorScheme = (value: ColorScheme) => {
  try {
    localStorage.setItem(colorSchemeStorageKey, value);
  } catch {
    return;
  }
};

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  confirmDelete: {
    id: 'pages.delete_confirm',
    defaultMessage: 'Are you sure you want to delete this page?',
  },
  backToTop: { id: 'pages.back_to_top', defaultMessage: 'Back to top' },
  colorScheme: {
    id: 'pages.color_scheme',
    defaultMessage: 'Color scheme',
  },
  colorSchemeAuto: {
    id: 'settings.color_scheme.auto',
    defaultMessage: 'Sync with system',
  },
  colorSchemeLight: {
    id: 'settings.color_scheme.light',
    defaultMessage: 'Light',
  },
  colorSchemeDark: {
    id: 'settings.color_scheme.dark',
    defaultMessage: 'Dark',
  },
  darkOnly: {
    id: 'pages.color_scheme.dark_only',
    defaultMessage: 'This theme only supports dark mode.',
  },
  linkCopied: {
    id: 'pages.link_copied',
    defaultMessage: 'Page link copied to clipboard.',
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
  const [bookletPagesResult, setBookletPagesResult] = useState<{
    accountId: string;
    bookletId: string;
    pages: ApiPageJSON[];
  } | null>(null);
  const [loadError, setLoadError] = useState<{
    id: string;
    notFound: boolean;
  } | null>(null);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [wideView, setWideView] = useState(false);
  const [password, setPassword] = useState('');
  const [unlocking, setUnlocking] = useState(false);
  const [passwordError, setPasswordError] = useState(false);
  const [showBackToTop, setShowBackToTop] = useState(false);
  const supportedColorSchemes = pageBlogViewColorSchemes as ColorScheme[];
  const [visitorColorScheme, setVisitorColorScheme] = useState<ColorScheme>(
    () => readStoredColorScheme(supportedColorSchemes),
  );
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
    if (initialPage?.id === id && !initialPage.locked) {
      return;
    }

    let active = true;

    apiGetPage(id)
      .then((data) => {
        if (active) {
          setPage(data);
        }

        return data;
      })
      .catch((loadFailure: unknown) => {
        if (active) {
          const status = isAxiosError(loadFailure)
            ? loadFailure.response?.status
            : undefined;
          setLoadError({ id, notFound: status === 404 || status === 410 });
        }
      });

    return () => {
      active = false;
    };
  }, [id, initialPage, loadAttempt]);

  const handleRetryLoad = useCallback(() => {
    setLoadError(null);
    setLoadAttempt((attempt) => attempt + 1);
  }, []);

  const currentPage = page?.id === id ? page : null;
  const currentPageAccountId = currentPage?.account_id;
  const currentBookletId = currentPage?.booklet_id ?? null;
  const error = loadError?.id === id && !currentPage ? loadError : null;
  const isOwner = !!currentPage && currentPage.account_id === accountId;
  const useBlogView =
    !!currentPage &&
    !multiColumn &&
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

  useEffect(() => {
    if (!currentPageAccountId || !currentBookletId) {
      return;
    }

    let active = true;

    const loadBookletPages = async () => {
      const pages: ApiPageJSON[] = [];

      while (active) {
        const batch = await apiGetAccountBookletPages(
          currentPageAccountId,
          currentBookletId,
          pages.length,
        );
        pages.push(...batch);

        if (batch.length < PAGE_LIST_MAX_LIMIT) {
          break;
        }
      }

      return pages;
    };

    loadBookletPages()
      .then((pages) => {
        if (active) {
          setBookletPagesResult({
            accountId: currentPageAccountId,
            bookletId: currentBookletId,
            pages,
          });
        }

        return pages;
      })
      .catch(() => {
        if (active) {
          setBookletPagesResult({
            accountId: currentPageAccountId,
            bookletId: currentBookletId,
            pages: [],
          });
        }
      });

    return () => {
      active = false;
    };
  }, [currentPageAccountId, currentBookletId]);

  const handleDelete = useCallback(() => {
    if (!window.confirm(intl.formatMessage(messages.confirmDelete))) {
      return;
    }

    apiDeletePage(id)
      .then(() => {
        history.push('/pages');
        return undefined;
      })
      .catch((error: unknown) => {
        dispatch(showAlertForError(error));
      });
  }, [id, history, intl, dispatch]);

  const replacePage = useCallback((data: ApiPageJSON) => {
    setPage((current) => (current?.id === data.id ? data : current));
  }, []);

  const handleLikeToggle = useCallback(() => {
    if (!page) {
      return;
    }

    const request = page.liked ? apiUnlikePage : apiLikePage;

    request(id)
      .then((data) => {
        replacePage(data);
        return data;
      })
      .catch((error: unknown) => {
        dispatch(showAlertForError(error));
      });
  }, [id, page, replacePage, dispatch]);

  const handleMainToggle = useCallback(() => {
    if (!page) return;

    const request = page.is_main ? apiUnsetMainPage : apiSetMainPage;

    request(id)
      .then((data) => {
        replacePage(data);
        const updateMain = <
          T extends { accountId: string; pages: ApiPageJSON[] },
        >(
          result: T | null,
        ) =>
          result?.accountId === data.account_id
            ? {
                ...result,
                pages: result.pages.map((accountPage) => ({
                  ...accountPage,
                  is_main: data.is_main && accountPage.id === data.id,
                })),
              }
            : result;
        setAccountPagesResult(updateMain);
        setBookletPagesResult(updateMain);
        return data;
      })
      .catch((error: unknown) => {
        dispatch(showAlertForError(error));
      });
  }, [id, page, replacePage, dispatch]);

  const handleShare = useCallback(() => {
    if (currentPage?.visibility !== 'public') {
      return;
    }

    const url = `${window.location.origin}/@${currentPage.account.acct}/pages/${encodeURIComponent(currentPage.name)}`;
    const copyLink = () => {
      navigator.clipboard
        .writeText(url)
        .then(() => {
          dispatch(showAlert({ message: messages.linkCopied }));
          return undefined;
        })
        .catch((error: unknown) => {
          dispatch(showAlertForError(error));
        });
    };

    if ('share' in navigator) {
      navigator
        .share({
          title: currentPage.title,
          url,
        })
        .catch((error: unknown) => {
          if (error instanceof DOMException && error.name === 'AbortError') {
            return;
          }

          copyLink();
        });
    } else {
      copyLink();
    }
  }, [currentPage, dispatch]);

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
          replacePage(data);
          setPassword('');
          setUnlocking(false);
          return data;
        })
        .catch(() => {
          setPasswordError(true);
          setUnlocking(false);
        });
    },
    [id, password, replacePage],
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
    (key, isolated = false) => {
      if (!currentPage) {
        return;
      }

      let entries = collectPageMedia(currentPage);
      if (isolated) {
        const blockId = key.startsWith('block:') ? key.slice(6) : '';
        const block = flattenPageBlocks(currentPage.content).find(
          (item) => item.id === blockId,
        );
        const media =
          block?.type === 'image'
            ? currentPage.attached_media.find(
                (item) => item.id === block.fileId,
              )
            : undefined;
        entries = media ? [{ key, media }] : [];
      }
      const index = entries.findIndex((entry) => entry.key === key);

      if (entries.length === 0) {
        return;
      }

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

  useEffect(() => {
    if (
      pageBlogThemeNeedsReload({
        useBlogView,
        pathname: window.location.pathname,
        serverAccount: pageBlogViewAccount,
        skin: pageBlogViewSkin,
        viewerSkin: pageBlogViewViewerSkin,
        stylesheetPresent: Boolean(document.getElementById('page-blog-theme')),
      })
    ) {
      window.location.reload();
    }
  }, [useBlogView]);

  useEffect(() => {
    if (!useBlogView || !pageBlogViewSkin) {
      return;
    }

    if (pageBlogViewViewerSkin) {
      document.body.classList.remove(`skin-${pageBlogViewViewerSkin}`);
    }
    document.body.classList.add(`skin-${pageBlogViewSkin}`);

    return () => {
      document.body.classList.remove(`skin-${pageBlogViewSkin}`);
      if (pageBlogViewViewerSkin) {
        document.body.classList.add(`skin-${pageBlogViewViewerSkin}`);
      }
      document.getElementById('page-blog-theme')?.remove();
    };
  }, [useBlogView]);

  useEffect(() => {
    if (!useBlogView) {
      return;
    }

    applyPageColorScheme(
      accountId ? colorScheme : visitorColorScheme,
      supportedColorSchemes,
    );

    return () => {
      applyPageColorScheme(null);
    };
  }, [accountId, supportedColorSchemes, useBlogView, visitorColorScheme]);

  const handleVisitorColorSchemeChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      const value = event.target.value as ColorScheme;
      setVisitorColorScheme(value);
      storeColorScheme(value);
    },
    [],
  );

  if (error) {
    return (
      <BundleColumnError
        multiColumn={multiColumn}
        errorType={error.notFound ? 'routing' : 'network'}
        onRetry={handleRetryLoad}
      />
    );
  }

  const title = currentPage
    ? currentPage.title
    : intl.formatMessage(messages.heading);
  const accountPages =
    accountPagesResult && accountPagesResult.accountId === currentPageAccountId
      ? accountPagesResult.pages
      : null;
  const bookletPages =
    bookletPagesResult &&
    bookletPagesResult.accountId === currentPageAccountId &&
    bookletPagesResult.bookletId === currentBookletId
      ? bookletPagesResult.pages
      : null;
  const navigationPages = currentBookletId ? bookletPages : accountPages;
  const currentPageListed = !!navigationPages?.some(
    (accountPage) => accountPage.id === id,
  );
  const filteredAccountPages = currentPage
    ? [...(currentPageListed ? [] : [currentPage]), ...(navigationPages ?? [])]
    : [];
  const currentPageIndex = currentPageListed
    ? filteredAccountPages.findIndex((accountPage) => accountPage.id === id)
    : -1;
  const previousPage =
    currentPageIndex > 0
      ? (filteredAccountPages[currentPageIndex - 1] ?? null)
      : null;
  const nextPage =
    currentPageIndex >= 0 && currentPageIndex < filteredAccountPages.length - 1
      ? (filteredAccountPages[currentPageIndex + 1] ?? null)
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
            onReport={handleReport}
            onWideViewToggle={handleWideViewToggle}
          />
          <div ref={scrollableRef} className='scrollable'>
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
                onShare={handleShare}
                onDelete={handleDelete}
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
              <footer className='page-show__blog-footer'>
                <div>
                  <Link to='/about'>{siteTitle ?? domain}</Link>
                  {siteTitle && domain && <span>{domain}</span>}
                </div>
                {!accountId && (
                  <label className='page-show__color-scheme'>
                    <span>{intl.formatMessage(messages.colorScheme)}</span>
                    <select
                      value={visitorColorScheme}
                      onChange={handleVisitorColorSchemeChange}
                    >
                      {supportedColorSchemes.map((scheme) => (
                        <option key={scheme} value={scheme}>
                          {intl.formatMessage(
                            scheme === 'dark'
                              ? messages.colorSchemeDark
                              : scheme === 'light'
                                ? messages.colorSchemeLight
                                : messages.colorSchemeAuto,
                          )}
                        </option>
                      ))}
                    </select>
                    {supportedColorSchemes.length === 1 &&
                      supportedColorSchemes[0] === 'dark' && (
                        <small>{intl.formatMessage(messages.darkOnly)}</small>
                      )}
                  </label>
                )}
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
        <meta
          name='robots'
          content={
            currentPage?.account.noindex === false
              ? 'index, follow'
              : 'noindex, noarchive'
          }
        />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default PageShow;
