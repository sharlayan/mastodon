import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import ImmutablePropTypes from 'react-immutable-proptypes';

import classNames from 'classnames';

import { supportsPassiveEvents } from 'detect-passive-events';

import MoodIcon from '@/material-icons/400-20px/mood.svg?react';
import { IconButton } from '@/flavours/glitch/components/icon_button';
import { injectIntl } from '@/flavours/glitch/components/intl';
import { Popover } from '@/flavours/glitch/components/popover';
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

import { EmojiPicker as EmojiPickerAsync } from '../../ui/util/async-components';

const messages = defineMessages({
  emoji: { id: 'emoji_button.label', defaultMessage: 'Insert emoji' },
  emoji_search: { id: 'emoji_button.search', defaultMessage: 'Search...' },
  custom: { id: 'emoji_button.custom', defaultMessage: 'Custom' },
  recent: { id: 'emoji_button.recent', defaultMessage: 'Frequently used' },
  search_results: { id: 'emoji_button.search_results', defaultMessage: 'Search results' },
  people: { id: 'emoji_button.people', defaultMessage: 'People' },
  nature: { id: 'emoji_button.nature', defaultMessage: 'Nature' },
  food: { id: 'emoji_button.food', defaultMessage: 'Food & Drink' },
  activity: { id: 'emoji_button.activity', defaultMessage: 'Activity' },
  travel: { id: 'emoji_button.travel', defaultMessage: 'Travel & Places' },
  objects: { id: 'emoji_button.objects', defaultMessage: 'Objects' },
  symbols: { id: 'emoji_button.symbols', defaultMessage: 'Symbols' },
  flags: { id: 'emoji_button.flags', defaultMessage: 'Flags' },
});

let EmojiPicker, Emoji; // load asynchronously

const listenerOptions = supportsPassiveEvents ? { passive: true, capture: true } : true;

const notFoundFn = () => (
  <div className='emoji-mart-no-results'>
    <Emoji
      emoji='sleuth_or_spy'
      size={32}
    />

    <div className='emoji-mart-no-results-label'>
      <FormattedMessage id='emoji_button.not_found' defaultMessage='No matching emojis found' />
    </div>
  </div>
);

class ModifierPickerMenu extends PureComponent {

  static propTypes = {
    active: PropTypes.bool,
    onSelect: PropTypes.func.isRequired,
    onClose: PropTypes.func.isRequired,
  };

  handleClick = e => {
    this.props.onSelect(e.currentTarget.getAttribute('data-index') * 1);
  };

  componentDidMount() {
    if (this.props.active) {
      this.attachListeners();
    }
  }

  componentDidUpdate() {
    if (this.props.active) {
      this.attachListeners();
    } else {
      this.removeListeners();
    }
  }

  componentWillUnmount() {
    this.removeListeners();
  }

  handleDocumentClick = e => {
    if (this.node && !this.node.contains(e.target)) {
      this.props.onClose();
    }
  };

  attachListeners() {
    document.addEventListener('click', this.handleDocumentClick, { capture: true });
    document.addEventListener('touchend', this.handleDocumentClick, listenerOptions);
  }

  removeListeners() {
    document.removeEventListener('click', this.handleDocumentClick, { capture: true });
    document.removeEventListener('touchend', this.handleDocumentClick, listenerOptions);
  }

  setRef = c => {
    this.node = c;
  };

  render() {
    const { active } = this.props;

    return (
      <div className='emoji-picker-dropdown__modifiers__menu' style={{ display: active ? 'block' : 'none' }} ref={this.setRef}>
        <button type='button' onClick={this.handleClick} data-index={1}><Emoji emoji='fist' size={22} skin={1} /></button>
        <button type='button' onClick={this.handleClick} data-index={2}><Emoji emoji='fist' size={22} skin={2} /></button>
        <button type='button' onClick={this.handleClick} data-index={3}><Emoji emoji='fist' size={22} skin={3} /></button>
        <button type='button' onClick={this.handleClick} data-index={4}><Emoji emoji='fist' size={22} skin={4} /></button>
        <button type='button' onClick={this.handleClick} data-index={5}><Emoji emoji='fist' size={22} skin={5} /></button>
        <button type='button' onClick={this.handleClick} data-index={6}><Emoji emoji='fist' size={22} skin={6} /></button>
      </div>
    );
  }

}

class ModifierPicker extends PureComponent {

  static propTypes = {
    active: PropTypes.bool,
    modifier: PropTypes.number,
    onChange: PropTypes.func,
    onClose: PropTypes.func,
    onOpen: PropTypes.func,
  };

  handleClick = () => {
    if (this.props.active) {
      this.props.onClose();
    } else {
      this.props.onOpen();
    }
  };

  handleSelect = modifier => {
    this.props.onChange(modifier);
    this.props.onClose();
  };

  render() {
    const { active, modifier } = this.props;

    return (
      <div className='emoji-picker-dropdown__modifiers'>
        <Emoji emoji='fist' size={22} skin={modifier} onClick={this.handleClick} />
        <ModifierPickerMenu active={active} onSelect={this.handleSelect} onClose={this.props.onClose} />
      </div>
    );
  }

}

class EmojiPickerMenuImpl extends PureComponent {

  static propTypes = {
    favorite_emojis: ImmutablePropTypes.list,
    frequentlyUsedEmojis: PropTypes.arrayOf(PropTypes.string),
    loading: PropTypes.bool,
    onClose: PropTypes.func.isRequired,
    onPick: PropTypes.func.isRequired,
    onAddFavorite: PropTypes.func,
    onRemoveFavorite: PropTypes.func,
    style: PropTypes.object,
    intl: PropTypes.object.isRequired,
    skinTone: PropTypes.number.isRequired,
    onSkinTone: PropTypes.func.isRequired,
    pickerButtonRef: PropTypes.func.isRequired
  };

  static defaultProps = {
    style: {},
    loading: true,
    frequentlyUsedEmojis: [],
  };

  state = {
    modifierOpen: false,
    readyToFocus: false,
    pickerSize: loadEmojiPickerSize(),
  };

  sizeObserver = new EmojiPickerSizeObserver((pickerSize) => {
    this.setState({ pickerSize });
  });

  componentDidMount() {
    // Because of https://github.com/react-bootstrap/react-bootstrap/issues/2614 we need
    // to wait for a frame before focusing
    requestAnimationFrame(() => {
      this.setState({ readyToFocus: true });
      if (this.node) {
        const element = this.node.querySelector('input[type="search"]');
        if (element) element.focus();
      }
    });
  }

  componentWillUnmount() {
    this.sizeObserver.dispose();
  }

  setRef = c => {
    this.node = c;
    this.sizeObserver.observe(this.node);
  };

  getI18n = () => {
    const { intl } = this.props;

    return {
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
        favorites: emojiPickerFavoritesCategoryLabel(intl),
      },
    };
  };

  handleClick = (emoji, event) => {
    if (!emoji.native) {
      emoji.native = `:${emoji.id}:`;
    }
    if (!(event.ctrlKey || event.metaKey)) {

      this.props.onClose();
    }
    this.props.onPick(emoji);
  };

  handleModifierOpen = () => {
    this.setState({ modifierOpen: true });
  };

  handleModifierClose = () => {
    this.setState({ modifierOpen: false });
  };

  handleModifierChange = modifier => {
    this.props.onSkinTone(modifier);
  };

  render() {
    const { loading, style, intl, favorite_emojis, skinTone, frequentlyUsedEmojis, onAddFavorite, onRemoveFavorite } = this.props;

    if (loading) {
      return <div style={{ width: 329 }} />;
    }

    const title = intl.formatMessage(messages.emoji);

    const { modifierOpen, pickerSize } = this.state;

    const pickerStyle = computeEmojiPickerStyle(style, pickerSize);

    return (
      <div className={classNames('emoji-picker-dropdown__menu', { selecting: modifierOpen })} style={pickerStyle} ref={this.setRef}>
        <EmojiPicker
          perLine={8}
          emojiSize={22}
          color=''
          emoji=''
          title={title}
          i18n={this.getI18n()}
          onClick={this.handleClick}
          recent={frequentlyUsedEmojis}
          skin={skinTone}
          showPreview={false}
          showSkinTones={false}
          notFound={notFoundFn}
          autoFocus={this.state.readyToFocus}
          emojiTooltip
          {...emojiPickerFavoriteProps(intl, {
            favoriteEmojis: favorite_emojis,
            onAddFavorite,
            onRemoveFavorite,
          })}
        />

        <ModifierPicker
          active={modifierOpen}
          modifier={skinTone}
          onOpen={this.handleModifierOpen}
          onClose={this.handleModifierClose}
          onChange={this.handleModifierChange}
        />
      </div>
    );
  }

}

const EmojiPickerMenu = injectIntl(EmojiPickerMenuImpl);

class EmojiPickerDropdown extends PureComponent {
  static propTypes = {
    favorite_emojis: ImmutablePropTypes.list,
    frequentlyUsedEmojis: PropTypes.arrayOf(PropTypes.string),
    intl: PropTypes.object.isRequired,
    onPickEmoji: PropTypes.func.isRequired,
    onSkinTone: PropTypes.func.isRequired,
    onAddFavorite: PropTypes.func,
    onRemoveFavorite: PropTypes.func,
    skinTone: PropTypes.number.isRequired,
    inverted: PropTypes.bool,
    disabled: PropTypes.bool,
  };

  state = {
    active: false,
    loading: false,
    target: null,
  };

  setRef = (c) => {
    this.dropdown = c;
  };

  onShowDropdown = () => {
    this.setState({ active: true });

    if (!EmojiPicker) {
      this.setState({ loading: true });

      EmojiPickerAsync().then(EmojiMart => {
        EmojiPicker = EmojiMart.Picker;
        Emoji = EmojiMart.Emoji;
        this.setState({ loading: false });
      }).catch(() => {
        this.setState({ loading: false, active: false });
      });
    }
  };

  onHideDropdown = e => {
    if (shouldIgnoreEmojiDropdownClose(e)) return;
    this.setState({ active: false });
  };

  onToggle = (e) => {
    if (!this.state.loading && (!e.key || e.key === 'Enter')) {
      if (this.state.active) {
        this.onHideDropdown();
      } else {
        this.onShowDropdown(e);
      }
    }
  };

  setTargetRef = c => {
    this.setState({ target: c });
  };

  render() {
    const { intl, onPickEmoji, onSkinTone, skinTone, frequentlyUsedEmojis, inverted, disabled, onAddFavorite, onRemoveFavorite } = this.props;
    const title = intl.formatMessage(messages.emoji);
    const { active, loading, target } = this.state;

    return (
      <div className='emoji-picker-dropdown' ref={this.setTargetRef}>
        <IconButton
          title={title}
          aria-expanded={active}
          active={active}
          icon='mood'
          iconComponent={MoodIcon}
          onClick={this.onToggle}
          disabled={disabled}
          id="emoji"
          inverted={inverted}
        />

        <Popover
          isOpen={active}
          reference={target}
          onClose={this.onHideDropdown}
        >
          {({ props, placement }) => (
            <div  {...props} className={`dropdown-animation ${placement}`}>
              <EmojiPickerMenu
                favorite_emojis={this.props.favorite_emojis}
                loading={loading}
                onClose={this.onHideDropdown}
                onPick={onPickEmoji}
                onSkinTone={onSkinTone}
                skinTone={skinTone}
                frequentlyUsedEmojis={frequentlyUsedEmojis}
                pickerButtonRef={this.target}
                onAddFavorite={onAddFavorite}
                onRemoveFavorite={onRemoveFavorite}
              />
            </div>
          )}
        </Popover>
      </div>
    );
  }

}

export default injectIntl(EmojiPickerDropdown);
