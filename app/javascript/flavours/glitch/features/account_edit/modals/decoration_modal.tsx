import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ChangeEvent, FC } from 'react';
import type React from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { apiGetAvatarDecorations } from '@/flavours/glitch/api/accounts';
import type { ApiAvatarDecorationJSON } from '@/flavours/glitch/api_types/accounts';
import type { ApiProfileDecorationConfigJSON } from '@/flavours/glitch/api_types/profile';
import { buildDecorationTransform } from '@/flavours/glitch/components/avatar_decoration_utils';
import { Button } from '@/flavours/glitch/components/button';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { Popover } from '@/flavours/glitch/components/popover';
import { patchProfile } from '@/flavours/glitch/reducers/slices/profile_edit';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import { autoPlayGif } from 'flavours/glitch/initial_state';

import { DialogModal } from '../../ui/components/dialog_modal';
import type { DialogModalProps } from '../../ui/components/dialog_modal';

import classes from './decoration_modal.module.scss';

const messages = defineMessages({
  title: {
    id: 'account_edit.decoration_modal.title',
    defaultMessage: 'Profile decorations',
  },
  save: {
    id: 'account_edit.save',
    defaultMessage: 'Save',
  },
  cancelEdit: {
    id: 'account_edit.decoration_modal.cancel_edit',
    defaultMessage: 'Cancel',
  },
  addNew: {
    id: 'account_edit.decoration_modal.add_new',
    defaultMessage: 'Add decoration',
  },
  addThis: {
    id: 'account_edit.decoration_modal.add_this',
    defaultMessage: 'Add this decoration',
  },
  back: {
    id: 'account_edit.decoration_modal.back',
    defaultMessage: 'Back',
  },
  done: {
    id: 'account_edit.decoration_modal.done',
    defaultMessage: 'Done',
  },
  edit: {
    id: 'account_edit.decoration_modal.edit_action',
    defaultMessage: 'Edit',
  },
  noDecorations: {
    id: 'account_edit.decoration_modal.no_decorations',
    defaultMessage: 'No profile decorations are available on this server.',
  },
  noSearchResults: {
    id: 'account_edit.decoration_modal.no_search_results',
    defaultMessage: 'No decorations match your search.',
  },
  noActiveDecorations: {
    id: 'account_edit.decoration_modal.no_active',
    defaultMessage: 'No decorations added yet.',
  },
  removeLabel: {
    id: 'account_edit.decoration_modal.remove',
    defaultMessage: 'Remove',
  },
  angleLabel: {
    id: 'account_edit.decoration_modal.angle',
    defaultMessage: 'Angle',
  },
  scaleLabel: {
    id: 'account_edit.decoration_modal.scale',
    defaultMessage: 'Scale',
  },
  opacityLabel: {
    id: 'account_edit.decoration_modal.opacity',
    defaultMessage: 'Opacity',
  },
  offsetXLabel: {
    id: 'account_edit.decoration_modal.offset_x',
    defaultMessage: 'Horizontal offset',
  },
  offsetYLabel: {
    id: 'account_edit.decoration_modal.offset_y',
    defaultMessage: 'Vertical offset',
  },
  flipLabel: {
    id: 'account_edit.decoration_modal.flip',
    defaultMessage: 'Flip horizontally',
  },
  moveUp: {
    id: 'account_edit.decoration_modal.move_up',
    defaultMessage: 'Move up',
  },
  moveDown: {
    id: 'account_edit.decoration_modal.move_down',
    defaultMessage: 'Move down',
  },
  searchPlaceholder: {
    id: 'account_edit.decoration_modal.search',
    defaultMessage: 'Search decorations…',
  },
  allCategories: {
    id: 'account_edit.decoration_modal.all_categories',
    defaultMessage: 'All categories',
  },
  uncategorized: {
    id: 'account_edit.decoration_modal.uncategorized',
    defaultMessage: 'Uncategorized',
  },
  categoryCount: {
    id: 'account_edit.decoration_modal.category_count',
    defaultMessage: '{name} ({count})',
  },
});

const UNCATEGORIZED_KEY = '__uncategorized__';

const noop = () => undefined;

interface CategoryGroup {
  key: string;
  name: string;
  decorations: ApiAvatarDecorationJSON[];
}

function groupByCategory(
  list: ApiAvatarDecorationJSON[],
  uncategorizedLabel: string,
): CategoryGroup[] {
  const groups = new Map<string, CategoryGroup>();
  for (const d of list) {
    const key = d.category ?? UNCATEGORIZED_KEY;
    const name = d.category ?? uncategorizedLabel;
    let group = groups.get(key);
    if (!group) {
      group = { key, name, decorations: [] };
      groups.set(key, group);
    }
    group.decorations.push(d);
  }
  return Array.from(groups.values()).sort((a, b) => {
    if (a.key === UNCATEGORIZED_KEY) return 1;
    if (b.key === UNCATEGORIZED_KEY) return -1;
    return a.name.localeCompare(b.name);
  });
}

interface DecorationTooltipProps {
  show: boolean;
  target: HTMLElement | null;
  decoration: ApiAvatarDecorationJSON;
}

const DecorationTooltip: FC<DecorationTooltipProps> = ({
  show,
  target,
  decoration,
}) => {
  if (!show || !target) return null;
  const url = autoPlayGif ? decoration.url : decoration.static_url;
  return (
    <Popover
      isOpen={show}
      reference={target}
      offset={8}
      placement='top'
      onClose={noop}
      closeOnClickOutside={false}
    >
      {({ props, placement: currentPlacement }) => (
        <div className={classes.decorationTooltipOverlay} {...props}>
          <div className={`dropdown-animation ${currentPlacement}`}>
            <div className={classes.decorationTooltip}>
              <img src={url} alt='' className={classes.decorationTooltipImg} />
              <span className={classes.decorationTooltipName}>
                {decoration.name}
              </span>
            </div>
          </div>
        </div>
      )}
    </Popover>
  );
};

interface DecorationTileProps {
  decoration: ApiAvatarDecorationJSON;
  isSelected: boolean;
  onSelect: (id: string) => void;
}

const DecorationTile: FC<DecorationTileProps> = ({
  decoration,
  isSelected,
  onSelect,
}) => {
  const [buttonEl, setButtonEl] = useState<HTMLButtonElement | null>(null);
  const [hovered, setHovered] = useState(false);

  const handleClick = useCallback(() => {
    onSelect(decoration.id);
  }, [onSelect, decoration.id]);

  const handleMouseEnter = useCallback(() => {
    setHovered(true);
  }, []);

  const handleMouseLeave = useCallback(() => {
    setHovered(false);
  }, []);

  return (
    <>
      <button
        ref={setButtonEl}
        type='button'
        className={`${classes.decorationTile} ${isSelected ? classes.decorationTileSelected : ''}`}
        onClick={handleClick}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        aria-pressed={isSelected}
      >
        <img src={decoration.url} alt='' className={classes.decorationImg} />
      </button>
      <DecorationTooltip
        show={hovered}
        target={buttonEl}
        decoration={decoration}
      />
    </>
  );
};

interface ActiveDecorationConfig extends ApiProfileDecorationConfigJSON {
  instanceId: string;
}

function withInstanceId(
  config: ApiProfileDecorationConfigJSON,
): ActiveDecorationConfig {
  return { ...config, instanceId: crypto.randomUUID() };
}

const DEFAULT_CONFIG: Omit<ApiProfileDecorationConfigJSON, 'id'> = {
  angle: 0,
  flip_h: false,
  offset_x: 0,
  offset_y: 0,
  scale: 1.0,
  opacity: 1.0,
};

type OnConfigChange = (
  instanceId: string,
  key: keyof Omit<ApiProfileDecorationConfigJSON, 'id'>,
  value: number | boolean,
) => void;

type Level = 1 | 2 | 3;

interface AvatarPreviewProps {
  avatarUrl: string | undefined;
  configs: ActiveDecorationConfig[];
  decorationsById: Map<string, ApiAvatarDecorationJSON>;
  focusedInstanceId?: string | null;
}

const AvatarPreview: FC<AvatarPreviewProps> = ({
  avatarUrl,
  configs,
  decorationsById,
  focusedInstanceId,
}) => {
  const animate = autoPlayGif;
  const src = avatarUrl ?? '/avatars/original/missing.png';
  const hasFocus = focusedInstanceId != null;

  return (
    <div className={classes.previewWrapper}>
      <div className={classes.previewAvatar}>
        <img src={src} alt='' className={classes.previewAvatarImg} />
        {configs.map((config) => {
          const decoration = decorationsById.get(config.id);
          if (!decoration) return null;
          const url = animate ? decoration.url : decoration.static_url;
          const dimmed = hasFocus && config.instanceId !== focusedInstanceId;
          return (
            <img
              key={config.instanceId}
              src={url}
              alt=''
              aria-hidden='true'
              className={classes.previewDecoration}
              style={{
                transform: buildDecorationTransform(config),
                opacity: dimmed ? 0.25 : config.opacity,
                transition: 'opacity 0.2s ease',
              }}
            />
          );
        })}
      </div>
    </div>
  );
};

interface ActiveListItemProps {
  config: ActiveDecorationConfig;
  decoration: ApiAvatarDecorationJSON | undefined;
  isExpanded: boolean;
  canMoveUp: boolean;
  canMoveDown: boolean;
  onToggleExpand: (instanceId: string) => void;
  onEdit: (instanceId: string) => void;
  onRemove: (instanceId: string) => void;
  onMoveUp: (instanceId: string) => void;
  onMoveDown: (instanceId: string) => void;
}

const ActiveListItem: FC<ActiveListItemProps> = ({
  config,
  decoration,
  isExpanded,
  canMoveUp,
  canMoveDown,
  onToggleExpand,
  onEdit,
  onRemove,
  onMoveUp,
  onMoveDown,
}) => {
  const intl = useIntl();
  const animate = autoPlayGif;

  const handleRowClick = useCallback(() => {
    onToggleExpand(config.instanceId);
  }, [onToggleExpand, config.instanceId]);

  const handleEdit = useCallback(() => {
    onEdit(config.instanceId);
  }, [onEdit, config.instanceId]);

  const handleRemove = useCallback(() => {
    onRemove(config.instanceId);
  }, [onRemove, config.instanceId]);

  const handleMoveUp = useCallback(() => {
    onMoveUp(config.instanceId);
  }, [onMoveUp, config.instanceId]);

  const handleMoveDown = useCallback(() => {
    onMoveDown(config.instanceId);
  }, [onMoveDown, config.instanceId]);

  const url = decoration && (animate ? decoration.url : decoration.static_url);

  return (
    <div
      className={`${classes.listItem} ${isExpanded ? classes.listItemExpanded : ''}`}
    >
      <div className={classes.listItemRow}>
        <button
          type='button'
          className={classes.listItemToggle}
          onClick={handleRowClick}
          aria-expanded={isExpanded}
        >
          <div className={classes.listItemThumb}>
            {url && <img src={url} alt='' className={classes.listItemImg} />}
          </div>
          <span className={classes.listItemName}>
            {decoration?.name ?? config.id}
          </span>
        </button>
        <div className={classes.listItemReorder}>
          <button
            type='button'
            className={classes.reorderBtn}
            onClick={handleMoveUp}
            disabled={!canMoveUp}
            title={intl.formatMessage(messages.moveUp)}
            aria-label={intl.formatMessage(messages.moveUp)}
          >
            ↑
          </button>
          <button
            type='button'
            className={classes.reorderBtn}
            onClick={handleMoveDown}
            disabled={!canMoveDown}
            title={intl.formatMessage(messages.moveDown)}
            aria-label={intl.formatMessage(messages.moveDown)}
          >
            ↓
          </button>
        </div>
      </div>

      {isExpanded && (
        <div className={classes.listItemActions}>
          <button
            type='button'
            className={classes.actionBtn}
            onClick={handleEdit}
          >
            {intl.formatMessage(messages.edit)}
          </button>
          <button
            type='button'
            className={`${classes.actionBtn} ${classes.actionBtnDanger}`}
            onClick={handleRemove}
          >
            {intl.formatMessage(messages.removeLabel)}
          </button>
        </div>
      )}
    </div>
  );
};

interface EditControlsProps {
  config: ActiveDecorationConfig;
  onConfigChange: OnConfigChange;
}

const EditControls: FC<EditControlsProps> = ({ config, onConfigChange }) => {
  const intl = useIntl();

  const handleAngle = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'angle', parseFloat(e.target.value));
    },
    [onConfigChange, config.instanceId],
  );
  const handleScale = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'scale', parseFloat(e.target.value));
    },
    [onConfigChange, config.instanceId],
  );
  const handleOpacity = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'opacity', parseFloat(e.target.value));
    },
    [onConfigChange, config.instanceId],
  );
  const handleOffsetX = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'offset_x', parseFloat(e.target.value));
    },
    [onConfigChange, config.instanceId],
  );
  const handleOffsetY = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'offset_y', parseFloat(e.target.value));
    },
    [onConfigChange, config.instanceId],
  );
  const handleFlip = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      onConfigChange(config.instanceId, 'flip_h', e.target.checked);
    },
    [onConfigChange, config.instanceId],
  );

  return (
    <div className={classes.controls}>
      <label className={classes.control}>
        <span>{intl.formatMessage(messages.angleLabel)}</span>
        <input
          type='range'
          min='-0.5'
          max='0.5'
          step='0.01'
          value={config.angle}
          onChange={handleAngle}
        />
        <output>{Math.round(config.angle * 360)}°</output>
      </label>

      <label className={classes.control}>
        <span>{intl.formatMessage(messages.scaleLabel)}</span>
        <input
          type='range'
          min='0.5'
          max='1.5'
          step='0.01'
          value={config.scale}
          onChange={handleScale}
        />
        <output>{Math.round(config.scale * 100)}%</output>
      </label>

      <label className={classes.control}>
        <span>{intl.formatMessage(messages.opacityLabel)}</span>
        <input
          type='range'
          min='0.1'
          max='1.0'
          step='0.01'
          value={config.opacity}
          onChange={handleOpacity}
        />
        <output>{Math.round(config.opacity * 100)}%</output>
      </label>

      <label className={classes.control}>
        <span>{intl.formatMessage(messages.offsetXLabel)}</span>
        <input
          type='range'
          min='-0.25'
          max='0.25'
          step='0.005'
          value={config.offset_x}
          onChange={handleOffsetX}
        />
        <output>{Math.round(config.offset_x * 100)}%</output>
      </label>

      <label className={classes.control}>
        <span>{intl.formatMessage(messages.offsetYLabel)}</span>
        <input
          type='range'
          min='-0.25'
          max='0.25'
          step='0.005'
          value={config.offset_y}
          onChange={handleOffsetY}
        />
        <output>{Math.round(config.offset_y * 100)}%</output>
      </label>

      <label className={`${classes.control} ${classes.controlCheckbox}`}>
        <input type='checkbox' checked={config.flip_h} onChange={handleFlip} />
        <span>{intl.formatMessage(messages.flipLabel)}</span>
      </label>
    </div>
  );
};

export const DecorationModal: FC<DialogModalProps> = ({ onClose }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const { profile, isPending } = useAppSelector((state) => state.profileEdit);

  const [available, setAvailable] = useState<ApiAvatarDecorationJSON[] | null>(
    null,
  );
  const [configs, setConfigs] = useState<ActiveDecorationConfig[]>(
    (profile?.avatarDecorations ?? []).map(withInstanceId),
  );

  const [level, setLevel] = useState<Level>(1);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [pendingAddId, setPendingAddId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('all');
  const [collapsedCategories, setCollapsedCategories] = useState<Set<string>>(
    () => new Set(),
  );

  const handleSearchChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setSearchQuery(e.target.value);
  }, []);

  const handleCategoryFilterChange = useCallback(
    (e: ChangeEvent<HTMLSelectElement>) => {
      setCategoryFilter(e.target.value);
    },
    [],
  );

  const handleToggleCategory = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      const key = e.currentTarget.dataset.key;
      if (!key) return;
      setCollapsedCategories((prev) => {
        const next = new Set(prev);
        if (next.has(key)) next.delete(key);
        else next.add(key);
        return next;
      });
    },
    [],
  );

  useEffect(() => {
    void apiGetAvatarDecorations().then((list) => {
      setAvailable(list);
    });
  }, []);

  const decorationsById = useMemo(
    () => new Map((available ?? []).map((d) => [d.id, d])),
    [available],
  );

  const handleToggleExpand = useCallback((instanceId: string) => {
    setExpandedId((prev) => (prev === instanceId ? null : instanceId));
  }, []);

  const handleEditItem = useCallback((instanceId: string) => {
    setEditingId(instanceId);
    setExpandedId(null);
    setLevel(3);
  }, []);

  const handleRemoveItem = useCallback((instanceId: string) => {
    setConfigs((prev) => prev.filter((c) => c.instanceId !== instanceId));
    setExpandedId(null);
  }, []);

  const handleMove = useCallback((instanceId: string, dir: -1 | 1) => {
    setConfigs((prev) => {
      const idx = prev.findIndex((c) => c.instanceId === instanceId);
      const next = idx + dir;
      if (idx < 0 || next < 0 || next >= prev.length) return prev;
      const nextItem = prev[next];
      const currItem = prev[idx];
      if (nextItem === undefined || currItem === undefined) return prev;
      return prev.map((item, i) => {
        if (i === idx) return nextItem;
        if (i === next) return currItem;
        return item;
      });
    });
  }, []);

  const handleMoveUp = useCallback(
    (instanceId: string) => {
      handleMove(instanceId, -1);
    },
    [handleMove],
  );

  const handleMoveDown = useCallback(
    (instanceId: string) => {
      handleMove(instanceId, 1);
    },
    [handleMove],
  );

  const handleGoToAdd = useCallback(() => {
    setPendingAddId(null);
    setLevel(2);
  }, []);

  const handleSave = useCallback(() => {
    if (!isPending) {
      const payload = configs.map(
        ({ instanceId: _instanceId, ...rest }) => rest,
      );
      void dispatch(patchProfile({ avatar_decorations: payload })).then(
        onClose,
      );
    }
  }, [dispatch, isPending, configs, onClose]);

  const handleSelectPending = useCallback((id: string) => {
    setPendingAddId((prev) => (prev === id ? null : id));
  }, []);

  const handleConfirmAdd = useCallback(() => {
    if (pendingAddId == null) return;
    const newConfig: ActiveDecorationConfig = {
      id: pendingAddId,
      ...DEFAULT_CONFIG,
      instanceId: crypto.randomUUID(),
    };
    setConfigs((prev) => [...prev, newConfig]);
    setEditingId(newConfig.instanceId);
    setPendingAddId(null);
    setLevel(3);
  }, [pendingAddId]);

  const handleBackFromAdd = useCallback(() => {
    setPendingAddId(null);
    setLevel(1);
  }, []);

  const handleConfigChange = useCallback<OnConfigChange>(
    (instanceId, key, value) => {
      setConfigs((prev) =>
        prev.map((c) =>
          c.instanceId === instanceId ? { ...c, [key]: value } : c,
        ),
      );
    },
    [],
  );

  const handleDoneEditing = useCallback(() => {
    setEditingId(null);
    setLevel(1);
  }, []);

  if (!profile) return <LoadingIndicator />;

  const renderLevel1 = () => (
    <>
      <AvatarPreview
        avatarUrl={profile.avatar}
        configs={configs}
        decorationsById={decorationsById}
      />

      <div className={classes.activeList}>
        {configs.length === 0 && (
          <p className={classes.empty}>
            {intl.formatMessage(messages.noActiveDecorations)}
          </p>
        )}
        {[...configs].reverse().map((config, idx) => (
          <ActiveListItem
            key={config.instanceId}
            config={config}
            decoration={decorationsById.get(config.id)}
            isExpanded={expandedId === config.instanceId}
            canMoveUp={idx > 0}
            canMoveDown={idx < configs.length - 1}
            onToggleExpand={handleToggleExpand}
            onEdit={handleEditItem}
            onRemove={handleRemoveItem}
            onMoveUp={handleMoveDown}
            onMoveDown={handleMoveUp}
          />
        ))}
      </div>

      <div className={classes.levelActions}>
        <Button onClick={handleGoToAdd} secondary>
          {intl.formatMessage(messages.addNew)}
        </Button>
        <Button onClick={onClose} secondary>
          {intl.formatMessage(messages.cancelEdit)}
        </Button>
        <Button onClick={handleSave} disabled={isPending}>
          {intl.formatMessage(messages.save)}
        </Button>
      </div>
    </>
  );

  const renderLevel2 = () => {
    const query = searchQuery.trim().toLowerCase();
    const uncategorizedLabel = intl.formatMessage(messages.uncategorized);

    const searchFiltered =
      available !== null && query.length > 0
        ? available.filter((d) => d.name.toLowerCase().includes(query))
        : available;

    const allGroups =
      available !== null ? groupByCategory(available, uncategorizedLabel) : [];

    const visibleGroups =
      searchFiltered !== null
        ? groupByCategory(
            categoryFilter === 'all'
              ? searchFiltered
              : searchFiltered.filter(
                  (d) => (d.category ?? UNCATEGORIZED_KEY) === categoryFilter,
                ),
            uncategorizedLabel,
          )
        : [];

    const renderTile = (decoration: ApiAvatarDecorationJSON) => {
      return (
        <DecorationTile
          key={decoration.id}
          decoration={decoration}
          isSelected={pendingAddId === decoration.id}
          onSelect={handleSelectPending}
        />
      );
    };

    return (
      <>
        {available !== null && available.length > 0 && (
          <div className={classes.filterRow}>
            <input
              type='search'
              className={classes.searchInput}
              placeholder={intl.formatMessage(messages.searchPlaceholder)}
              value={searchQuery}
              onChange={handleSearchChange}
            />
            {allGroups.length > 1 && (
              <select
                className={classes.categorySelect}
                value={categoryFilter}
                onChange={handleCategoryFilterChange}
              >
                <option value='all'>
                  {intl.formatMessage(messages.allCategories)}
                </option>
                {allGroups.map((g) => (
                  <option key={g.key} value={g.key}>
                    {intl.formatMessage(messages.categoryCount, {
                      name: g.name,
                      count: g.decorations.length,
                    })}
                  </option>
                ))}
              </select>
            )}
          </div>
        )}
        {searchFiltered === null && <LoadingIndicator />}
        {searchFiltered !== null && visibleGroups.length === 0 && (
          <p className={classes.empty}>
            {intl.formatMessage(
              query.length > 0
                ? messages.noSearchResults
                : messages.noDecorations,
            )}
          </p>
        )}
        {visibleGroups.map((group) => {
          const collapsed = collapsedCategories.has(group.key);
          return (
            <div key={group.key} className={classes.categoryGroup}>
              <button
                type='button'
                className={classes.categoryHeader}
                data-key={group.key}
                onClick={handleToggleCategory}
                aria-expanded={!collapsed}
              >
                <span className={classes.categoryCaret}>
                  {collapsed ? '▶' : '▼'}
                </span>
                <span>
                  {intl.formatMessage(messages.categoryCount, {
                    name: group.name,
                    count: group.decorations.length,
                  })}
                </span>
              </button>
              {!collapsed && (
                <div className={classes.grid}>
                  {group.decorations.map(renderTile)}
                </div>
              )}
            </div>
          );
        })}

        <div className={classes.levelActions}>
          <Button onClick={handleBackFromAdd} secondary>
            {intl.formatMessage(messages.back)}
          </Button>
          {pendingAddId != null && (
            <Button onClick={handleConfirmAdd}>
              {intl.formatMessage(messages.addThis)}
            </Button>
          )}
        </div>
      </>
    );
  };

  const renderLevel3 = () => {
    const config = configs.find((c) => c.instanceId === editingId);
    if (!config) return null;
    return (
      <>
        <AvatarPreview
          avatarUrl={profile.avatar}
          configs={configs}
          decorationsById={decorationsById}
          focusedInstanceId={editingId}
        />

        <EditControls config={config} onConfigChange={handleConfigChange} />

        <div className={classes.levelActions}>
          <Button onClick={handleDoneEditing}>
            {intl.formatMessage(messages.done)}
          </Button>
        </div>
      </>
    );
  };

  return (
    <DialogModal
      onClose={onClose}
      title={intl.formatMessage(messages.title)}
      noCancelButton
    >
      <div className={classes.wrapper}>
        {level === 1 && renderLevel1()}
        {level === 2 && renderLevel2()}
        {level === 3 && renderLevel3()}
      </div>
    </DialogModal>
  );
};
