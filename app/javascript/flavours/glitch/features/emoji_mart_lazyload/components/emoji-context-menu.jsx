import React from 'react'
import { createPortal } from 'react-dom'
import PropTypes from 'prop-types'

export default class EmojiContextMenu extends React.PureComponent {
  constructor(props) {
    super(props)
    this.handleClickOutside = this.handleClickOutside.bind(this)
    this.handleKeyDown = this.handleKeyDown.bind(this)
  }

  componentDidMount() {
    document.addEventListener('click', this.handleClickOutside, true)
    document.addEventListener('keydown', this.handleKeyDown)
  }

  componentWillUnmount() {
    document.removeEventListener('click', this.handleClickOutside, true)
    document.removeEventListener('keydown', this.handleKeyDown)
  }

  handleClickOutside(e) {
    if (this.node && !this.node.contains(e.target)) {
      this.props.onClose()
    }
  }

  handleKeyDown(e) {
    if (e.key === 'Escape') {
      this.props.onClose()
    }
  }

  handleAddFavorite = () => {
    const { emoji, onAddFavorite, onClose } = this.props
    const name = emoji.id || emoji.short_names[0]
    const emojiType = emoji.custom ? 'custom' : 'unicode'
    onAddFavorite(name, emojiType)
    onClose()
  };

  handleRemoveFavorite = () => {
    const { emoji, favoriteEmojiData, onRemoveFavorite, onClose } = this.props
    const name = emoji.id || emoji.short_names[0]
    if (favoriteEmojiData) {
      onRemoveFavorite(name, favoriteEmojiData.get('emoji_type'), favoriteEmojiData.get('position'))
    }
    onClose()
  };

  render() {
    const { position, isFavorite, isInFavoritesCategory } = this.props

    const style = {
      position: 'fixed',
      left: position.x,
      top: position.y,
    }

    const isCustom = this.props.emoji.custom

    let content
    if (isInFavoritesCategory && isFavorite) {
      content = (
        <button
          type="button"
          className="emoji-context-menu__item"
          onClick={this.handleRemoveFavorite}
        >
          {this.props.removeFromFavoritesLabel || 'Remove from Favorites'}
        </button>
      )
    } else if (!isInFavoritesCategory && isFavorite) {
      content = (
        <span className="emoji-context-menu__item emoji-context-menu__item--disabled">
          {this.props.alreadyInFavoritesLabel || 'Already in Favorites'}
        </span>
      )
    } else if (isCustom) {
      content = (
        <button
          type="button"
          className="emoji-context-menu__item"
          onClick={this.handleAddFavorite}
        >
          {this.props.addToFavoritesLabel || 'Add to Favorites'}
        </button>
      )
    } else {
      content = null
    }

    if (!content) return null

    return createPortal(
      <div
        className="emoji-context-menu"
        style={style}
        ref={(c) => { this.node = c }}
      >
        {content}
      </div>,
      document.body,
    )
  }
}

EmojiContextMenu.propTypes = {
  emoji: PropTypes.object.isRequired,
  isFavorite: PropTypes.bool.isRequired,
  isInFavoritesCategory: PropTypes.bool,
  onAddFavorite: PropTypes.func.isRequired,
  onRemoveFavorite: PropTypes.func.isRequired,
  position: PropTypes.shape({
    x: PropTypes.number.isRequired,
    y: PropTypes.number.isRequired,
  }).isRequired,
  onClose: PropTypes.func.isRequired,
}

EmojiContextMenu.defaultProps = {
  isInFavoritesCategory: false,
}
