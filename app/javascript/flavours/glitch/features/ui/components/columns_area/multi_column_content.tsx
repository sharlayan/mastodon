import { Children, cloneElement, isValidElement, useCallback } from 'react';

import type { List, Record } from 'immutable';

import { ColumnIndexContext } from '@/flavours/glitch/components/column/context';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import { changeLocalSetting } from 'flavours/glitch/actions/local_settings';
import {
  federatedTimelineEnabled,
  localTimelineEnabled,
} from 'flavours/glitch/initial_state';
import { sharlayanColumnComponents } from 'flavours/glitch/sharlayan/registry/routes';

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
} from '../../util/async-components';
import {
  ColumnWidthContext,
  normalizeColumnWidth,
} from '../../util/column_width_context';
import Bundle from '../bundle';
import { BundleColumnError } from '../bundle_column_error';
import { ColumnLoading } from '../column_loading';
import DrawerLoading from '../drawer_loading';

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

const ErrorComponent = (props: { onRetry: () => void }) => (
  <BundleColumnError multiColumn errorType='network' {...props} />
);

const renderLoading = (columnId: string) => {
  const LoadingComponent =
    columnId === 'COMPOSE' ? <DrawerLoading /> : <ColumnLoading multiColumn />;
  return () => LoadingComponent;
};

export const MultiColumnContent: React.FC<{
  children: React.ReactElement | React.ReactElement[];
}> = ({ children }) => {
  const columns = useAppSelector(
    (state) => state.settings.get('columns') as List<Record<Column>>,
  );
  const visibleColumns = columns.filter((column) => {
    const columnId = column.get('id');
    if (!localTimelineEnabled && columnId === 'COMMUNITY') return false;
    if (!federatedTimelineEnabled && ['PUBLIC', 'REMOTE'].includes(columnId))
      return false;
    return true;
  });
  const dispatch = useAppDispatch();
  const unpinnedColumnWidth = normalizeColumnWidth(
    useAppSelector((state) =>
      state.local_settings.get('deck_unpinned_column_width'),
    ),
  );
  const saveUnpinnedColumnWidth = useCallback(
    (width: number) => {
      dispatch(changeLocalSetting(['deck_unpinned_column_width'], width));
    },
    [dispatch],
  );

  return (
    <>
      {visibleColumns.map((column, index) => {
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
        <ColumnIndexContext.Provider value={visibleColumns.size}>
          {Children.map(children, (child) =>
            isValidElement<{ multiColumn?: boolean }>(child)
              ? cloneElement(child, { multiColumn: true })
              : child,
          )}
        </ColumnIndexContext.Provider>
      </ColumnWidthContext.Provider>
    </>
  );
};
