import {
  Children,
  cloneElement,
  createContext,
  forwardRef,
  isValidElement,
  useCallback,
  useContext,
} from 'react';

import classNames from 'classnames';

import type { List, Record } from 'immutable';

import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import { changeLocalSetting } from 'flavours/glitch/actions/local_settings';
import { Footer } from 'flavours/glitch/features/custom_homepage/components/footer';
import { Header } from 'flavours/glitch/features/custom_homepage/components/header';
import { CollapsibleNavigationPanel } from 'flavours/glitch/features/navigation_panel';
import { sharlayanColumnComponents } from 'flavours/glitch/sharlayan/registry/routes';
import { SharlayanColumnsAreaExtensions } from 'flavours/glitch/sharlayan/registry/ui';

import { useBreakpoint } from '../hooks/useBreakpoint';
import {
  Compose,
  Notifications,
  HomeTimeline,
  CommunityTimeline,
  PublicTimeline,
  HashtagTimeline,
  DirectTimeline,
  FavouritedStatuses,
  BookmarkedStatuses,
  ListTimeline,
  Directory,
} from '../util/async-components';
import {
  ColumnWidthContext,
  normalizeColumnWidth,
} from '../util/column_width_context';
import { useColumnsContext } from '../util/columns_context';

import Bundle from './bundle';
import { BundleColumnError } from './bundle_column_error';
import { ColumnLoading } from './column_loading';
import { ComposePanel, RedirectToMobileComposeIfNeeded } from './compose_panel';
import DrawerLoading from './drawer_loading';

const componentMap = {
  COMPOSE: Compose,
  HOME: HomeTimeline,
  NOTIFICATIONS: Notifications,
  PUBLIC: PublicTimeline,
  REMOTE: PublicTimeline,
  COMMUNITY: CommunityTimeline,
  HASHTAG: HashtagTimeline,
  DIRECT: DirectTimeline,
  FAVOURITES: FavouritedStatuses,
  BOOKMARKS: BookmarkedStatuses,
  LIST: ListTimeline,
  DIRECTORY: Directory,
  ...sharlayanColumnComponents,
} as const;

const TabsBarPortal = () => {
  const { setTabsBarElement } = useColumnsContext();

  const setRef = useCallback(
    (element: HTMLDivElement | null) => {
      if (element) {
        setTabsBarElement(element);
      }
    },
    [setTabsBarElement],
  );

  return <div id='tabs-bar__portal' ref={setRef} />;
};

export const ColumnIndexContext = createContext(1);
export const useColumnIndexContext = () => useContext(ColumnIndexContext);

interface Column {
  uuid: string;
  id: keyof typeof componentMap;
  params?: null | Record<{ other?: unknown; width?: number }>;
}

type FetchedComponent = React.FC<{
  columnId?: string;
  multiColumn?: boolean;
  params: unknown;
}>;

export const ColumnsArea = forwardRef<
  HTMLDivElement,
  {
    pageBlogView?: boolean;
    singleColumn?: boolean;
    minimalShell?: boolean;
    children: React.ReactElement | React.ReactElement[];
  }
>(({ children, minimalShell, pageBlogView, singleColumn }, ref) => {
  const renderComposePanel = !useBreakpoint('full');
  const columns = useAppSelector(
    (state) => state.settings.get('columns') as List<Record<Column>>,
  );
  const isModalOpen = useAppSelector(
    (state) => !state.modal.get('stack').isEmpty(),
  );
  const dispatch = useAppDispatch();
  const unpinnedColumnWidth = normalizeColumnWidth(
    useAppSelector(
      (state) =>
        // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
        state.local_settings.get('deck_unpinned_column_width') as unknown,
    ),
  );
  const saveUnpinnedColumnWidth = useCallback(
    (width: number) => {
      dispatch(changeLocalSetting(['deck_unpinned_column_width'], width));
    },
    [dispatch],
  );

  if (pageBlogView) {
    return (
      <main className='columns-area columns-area--mobile page-blog-shell'>
        {children}
      </main>
    );
  }

  if (minimalShell) {
    return (
      <div className='columns-area__panels'>
        <div className='columns-area__panels__main'>
          <Header />

          <div className='tabs-bar__wrapper'>
            <TabsBarPortal />
          </div>

          <div className='columns-area columns-area--mobile'>{children}</div>

          <Footer />
        </div>
      </div>
    );
  }

  if (singleColumn) {
    return (
      <div className='columns-area__panels'>
        <div className='columns-area__panels__pane columns-area__panels__pane--compositional'>
          <div className='columns-area__panels__pane__inner'>
            {renderComposePanel && <ComposePanel />}
            <RedirectToMobileComposeIfNeeded />
          </div>
        </div>

        <main className='columns-area__panels__main'>
          <div className='tabs-bar__wrapper'>
            <TabsBarPortal />
          </div>

          <SharlayanColumnsAreaExtensions />

          <div className='columns-area columns-area--mobile'>{children}</div>
        </main>

        <CollapsibleNavigationPanel />
      </div>
    );
  }

  return (
    <main
      className={classNames('columns-area', { unscrollable: isModalOpen })}
      ref={ref}
      tabIndex={isModalOpen ? undefined : 0}
    >
      {columns.map((column, index) => {
        const params = column.get('params')
          ? column.get('params')?.toJS()
          : null;
        const other = params?.other ?? {};
        const width = normalizeColumnWidth(params?.width);
        const customized = params?.width != null;
        const uuid = column.get('uuid');
        const id = column.get('id');

        return (
          <ColumnIndexContext.Provider value={index} key={uuid}>
            <ColumnWidthContext.Provider
              value={{ columnId: uuid, customized, width }}
            >
              <Bundle
                key={uuid}
                fetchComponent={componentMap[id]}
                loading={renderLoading(id)}
                error={ErrorComponent}
              >
                {(SpecificComponent: FetchedComponent) => (
                  <SpecificComponent
                    columnId={uuid}
                    params={params}
                    multiColumn
                    {...other}
                  />
                )}
              </Bundle>
            </ColumnWidthContext.Provider>
          </ColumnIndexContext.Provider>
        );
      })}

      <ColumnWidthContext.Provider
        value={{
          customized: true,
          width: unpinnedColumnWidth,
          onSave: saveUnpinnedColumnWidth,
        }}
      >
        <ColumnIndexContext.Provider value={columns.size}>
          {Children.map(children, (child) =>
            isValidElement<{ multiColumn?: boolean }>(child)
              ? cloneElement(child, { multiColumn: true })
              : child,
          )}
        </ColumnIndexContext.Provider>
      </ColumnWidthContext.Provider>
    </main>
  );
});

ColumnsArea.displayName = 'ColumnsArea';

const ErrorComponent = (props: { onRetry: () => void }) => {
  return <BundleColumnError multiColumn errorType='network' {...props} />;
};

const renderLoading = (columnId: string) => {
  const LoadingComponent =
    columnId === 'COMPOSE' ? <DrawerLoading /> : <ColumnLoading multiColumn />;
  return () => LoadingComponent;
};
