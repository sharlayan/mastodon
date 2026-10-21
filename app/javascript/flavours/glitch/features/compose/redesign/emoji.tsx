import type React from 'react';
import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { SmileyIcon } from '@phosphor-icons/react';
import type { EmojiData, EmojiSkin } from 'emoji-mart';

import { emojiUse } from '@/flavours/glitch/actions/emojis';
import {
  addFavoriteEmoji,
  removeFavoriteEmoji,
} from '@/flavours/glitch/actions/favorite_emojis';
import { changeSetting } from '@/flavours/glitch/actions/settings';
import { IconButton } from '@/flavours/glitch/components/button/redesign';
import type { IconButtonProps } from '@/flavours/glitch/components/button/redesign';
import { CircularProgress } from '@/flavours/glitch/components/circular_progress';
import { MenuCard } from '@/flavours/glitch/components/menu/card';
import type { PopoverChildProps } from '@/flavours/glitch/components/popover';
import { Popover } from '@/flavours/glitch/components/popover';
import { useMergedRefs } from '@/flavours/glitch/hooks/useMergedRefs';
import { useToggle } from '@/flavours/glitch/hooks/useToggle';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import {
  emojiPickerFavoriteProps,
  emojiPickerFavoritesCategoryLabel,
  shouldIgnoreEmojiDropdownClose,
} from '@/sharlayan/emoji_picker/favorites';
import {
  computeEmojiPickerStyle,
  EmojiPickerSizeObserver,
  loadEmojiPickerSize,
} from '@/sharlayan/emoji_picker/picker_size';

import { PER_LINE, selectFrequentlyUsedEmoji } from './selectors';
import classes from './styles.module.scss';

export type OnEmojiPick = (emoji: EmojiData) => void;

const messages = defineMessages({
  emoji: { id: 'emoji_button.label', defaultMessage: 'Insert emoji' },
  emoji_search: { id: 'emoji_button.search', defaultMessage: 'Search...' },
  custom: { id: 'emoji_button.custom', defaultMessage: 'Custom' },
  recent: { id: 'emoji_button.recent', defaultMessage: 'Frequently used' },
  search_results: {
    id: 'emoji_button.search_results',
    defaultMessage: 'Search results',
  },
  people: { id: 'emoji_button.people', defaultMessage: 'People' },
  nature: { id: 'emoji_button.nature', defaultMessage: 'Nature' },
  food: { id: 'emoji_button.food', defaultMessage: 'Food & Drink' },
  activity: { id: 'emoji_button.activity', defaultMessage: 'Activity' },
  travel: { id: 'emoji_button.travel', defaultMessage: 'Travel & Places' },
  objects: { id: 'emoji_button.objects', defaultMessage: 'Objects' },
  symbols: { id: 'emoji_button.symbols', defaultMessage: 'Symbols' },
  flags: { id: 'emoji_button.flags', defaultMessage: 'Flags' },
});

export const ComposeEmojiButton: React.FC<{
  onPick: OnEmojiPick;
  label?: React.ReactNode;
  icon?: IconButtonProps['icon'];
  disabled?: boolean;
  variant?: IconButtonProps['variant'];
}> = ({ onPick, label, icon = SmileyIcon, disabled, variant }) => {
  const [open, { onToggle, onFalse }] = useToggle();
  const [target, setTarget] = useState<HTMLButtonElement | null>(null);
  const handleClose = useCallback(
    (event?: Event) => {
      if (!shouldIgnoreEmojiDropdownClose(event)) onFalse();
    },
    [onFalse],
  );

  return (
    <>
      <IconButton
        size='sm'
        icon={icon}
        disabled={disabled}
        variant={variant}
        ref={setTarget}
        onClick={onToggle}
        aria-expanded={open}
      >
        {label ?? (
          <FormattedMessage
            id='emoji_button.label'
            defaultMessage='Insert emoji'
          />
        )}
      </IconButton>

      <Popover
        isOpen={open}
        onClose={handleClose}
        reference={target}
        placement='top-start'
        offset={4}
      >
        {({ props, placement }) => (
          <ComposeEmojiDropdown
            onPick={onPick}
            onClose={onFalse}
            className={placement}
            {...props}
          />
        )}
      </Popover>
    </>
  );
};

const EmojiPicker = lazy(() =>
  import('@/flavours/glitch/features/emoji/emoji_picker').then(
    ({ Picker }) => ({
      default: Picker,
    }),
  ),
);
const Emoji = lazy(() =>
  import('@/flavours/glitch/features/emoji/emoji_picker').then(({ Emoji }) => ({
    default: Emoji,
  })),
);

const ComposeEmojiDropdown: React.FC<
  {
    onClose: () => void;
    onPick: OnEmojiPick;
    className?: string;
  } & PopoverChildProps
> = ({ onPick, onClose, className, style, ...props }) => {
  const intl = useIntl();
  const skinTone = useAppSelector(
    (state) => state.settings.get('skinTone') as EmojiSkin | undefined,
  );
  const frequentlyUsedEmojis = useAppSelector(selectFrequentlyUsedEmoji);
  const favoriteEmojis = useAppSelector(
    (state) =>
      state.favorite_emojis as ImmutableList<ImmutableMap<string, unknown>>,
  );
  const [pickerSize, setPickerSize] = useState(
    () => loadEmojiPickerSize() as { width: number; height: number } | null,
  );
  const [pickerElement, setPickerElement] = useState<HTMLDivElement | null>(
    null,
  );
  const pickerRef = useMergedRefs<HTMLDivElement>(props.ref, setPickerElement);
  useEffect(() => {
    const observer = new EmojiPickerSizeObserver(setPickerSize);
    observer.observe(pickerElement);
    return () => {
      observer.dispose();
    };
  }, [pickerElement]);
  const i18n = useMemo(
    () => ({
      search: intl.formatMessage(messages.emoji_search),
      categories: {
        search: intl.formatMessage(messages.search_results),
        recent: intl.formatMessage(messages.recent),
        people: intl.formatMessage(messages.people),
        nature: intl.formatMessage(messages.nature),
        foods: intl.formatMessage(messages.food),
        activity: intl.formatMessage(messages.activity),
        places: intl.formatMessage(messages.travel),
        objects: intl.formatMessage(messages.objects),
        symbols: intl.formatMessage(messages.symbols),
        flags: intl.formatMessage(messages.flags),
        custom: intl.formatMessage(messages.custom),
        favorites: emojiPickerFavoritesCategoryLabel(intl) as string,
      },
    }),
    [intl],
  );

  const dispatch = useAppDispatch();
  const onAddFavorite = useCallback(
    (name: string, emojiType: string) => {
      dispatch(addFavoriteEmoji(name, emojiType));
    },
    [dispatch],
  );
  const onRemoveFavorite = useCallback(
    (name: string, emojiType: string, position: number) => {
      dispatch(removeFavoriteEmoji(name, emojiType, position));
    },
    [dispatch],
  );
  const handleEmojiPick = useCallback(
    (rawEmoji: EmojiData, event: React.MouseEvent<HTMLInputElement>) => {
      const emoji = {
        ...rawEmoji,
        native: 'native' in rawEmoji ? rawEmoji.native : `:${rawEmoji.id}:`,
      };

      if (!(event.ctrlKey || event.metaKey)) {
        onClose();
      }
      dispatch(emojiUse(emoji));
      onPick(emoji);
    },
    [dispatch, onPick, onClose],
  );

  // Close modifier window if it's not clicked in.
  const modifierRef = useRef<HTMLDivElement>(null);
  const [open, { onTrue, onFalse }] = useToggle();
  const handleRootClick: React.MouseEventHandler<HTMLDivElement> = useCallback(
    (event) => {
      if (
        !open ||
        (event.target instanceof Node &&
          modifierRef.current?.contains(event.target))
      ) {
        return;
      }
      onFalse();
    },
    [onFalse, open],
  );

  return (
    <MenuCard
      {...props}
      ref={pickerRef}
      style={computeEmojiPickerStyle(style, pickerSize) as React.CSSProperties}
      className={classNames(
        'dropdown-animation',
        'emoji-picker-dropdown__menu',
        classes.emojiRoot,
        className,
        open && 'selecting',
      )}
      onClick={handleRootClick}
    >
      <Suspense
        fallback={
          <CircularProgress
            size={50}
            strokeWidth={2}
            role='none'
            className={classes.emojiLoading}
          />
        }
      >
        <EmojiPicker
          perLine={PER_LINE}
          emojiSize={22}
          color=''
          emoji=''
          title={intl.formatMessage(messages.emoji)}
          i18n={i18n}
          onClick={handleEmojiPick}
          recent={frequentlyUsedEmojis}
          skin={skinTone ?? 1}
          showPreview={false}
          showSkinTones={false}
          // We need to cast as unknown as this requires a legacy class component.
          notFound={NotFound as unknown as () => React.Component}
          autoFocus
          emojiTooltip
          {...emojiPickerFavoriteProps(intl, {
            favoriteEmojis,
            onAddFavorite,
            onRemoveFavorite,
          })}
        />

        <div className='emoji-picker-dropdown__modifiers'>
          <Emoji emoji='fist' size={22} skin={skinTone} onClick={onTrue} />
          <div
            className='emoji-picker-dropdown__modifiers__menu'
            hidden={!open}
            ref={modifierRef}
          >
            <ModifierButton skin={1} onClose={onFalse} />
            <ModifierButton skin={2} onClose={onFalse} />
            <ModifierButton skin={3} onClose={onFalse} />
            <ModifierButton skin={4} onClose={onFalse} />
            <ModifierButton skin={5} onClose={onFalse} />
            <ModifierButton skin={6} onClose={onFalse} />
          </div>
        </div>
      </Suspense>
    </MenuCard>
  );
};

const ModifierButton: React.FC<{ skin: EmojiSkin; onClose: () => void }> = ({
  skin,
  onClose,
}) => {
  const dispatch = useAppDispatch();
  const handleClick: React.MouseEventHandler = useCallback(
    (event) => {
      event.preventDefault();
      dispatch(changeSetting(['skinTone'], skin));
      onClose();
    },
    [dispatch, onClose, skin],
  );
  return (
    <button type='button' onClick={handleClick} data-index={1}>
      <Emoji emoji='fist' size={22} skin={skin} />
    </button>
  );
};

const NotFound = () => (
  <div className='emoji-mart-no-results'>
    <Emoji emoji='sleuth_or_spy' size={32} />

    <div className='emoji-mart-no-results-label'>
      <FormattedMessage
        id='emoji_button.not_found'
        defaultMessage='No matching emojis found'
      />
    </div>
  </div>
);
