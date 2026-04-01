import React from 'react'
import PropTypes from 'prop-types'

import frequently from '../utils/frequently'
import { getData } from '../utils'
import NimbleEmoji from './emoji/nimble-emoji'
import NotFound from './not-found'
import 'intersection-observer'

export default class Category extends React.Component {
  constructor(props) {
    super(props)

    this.data = props.data
    this.setContainerRef = this.setContainerRef.bind(this)
    this.setLabelRef = this.setLabelRef.bind(this)
    this.handleLabelClick = this.handleLabelClick.bind(this)

    this.imageObserver = new window.IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const image = entry.target;
          image.src = image.dataset.src;
          image.classList.remove("lazy");
          this.imageObserver.unobserve(image);
        }
      });
    });

    this.state = {
      isCollapsed: this.loadCollapsedState(props.name)
    }
  }

  componentDidMount() {
    this.margin = 0
    this.minMargin = 0

    this.memoizeSize()

    this.lazyloadImages = []
    this.addLazyloadObserver()

    this.updateCategoryVisibility()
  }

  componentDidUpdate(prevProps, prevState) {
    this.addLazyloadObserver()

    if (prevState.isCollapsed !== this.state.isCollapsed) {
      this.updateCategoryVisibility()
    }
  }

  componentWillUnmount() {
    this.removeLazyloadObserver()
  }

  shouldComponentUpdate(nextProps, nextState) {
    var {
        name,
        perLine,
        native,
        hasStickyPosition,
        emojis,
        emojiProps,
      } = this.props,
      { skin, size, set } = emojiProps,
      {
        perLine: nextPerLine,
        native: nextNative,
        hasStickyPosition: nextHasStickyPosition,
        emojis: nextEmojis,
        emojiProps: nextEmojiProps,
      } = nextProps,
      { skin: nextSkin, size: nextSize, set: nextSet } = nextEmojiProps,
      shouldUpdate = false

    if (name == 'Recent' && perLine != nextPerLine) {
      shouldUpdate = true
    }

    if (name == 'Search') {
      shouldUpdate = true
    }

    if (
      skin != nextSkin ||
      size != nextSize ||
      native != nextNative ||
      set != nextSet ||
      hasStickyPosition != nextHasStickyPosition
    ) {
      shouldUpdate = true
    }

    if (this.state.isCollapsed !== nextState.isCollapsed) {
      shouldUpdate = true
    }

    if (emojis !== nextEmojis) {
      shouldUpdate = true
    }

    return shouldUpdate
  }

  loadCollapsedState(categoryName) {
    try {
      const saved = localStorage.getItem('mastodon-emojimart-categories-setting')
      const collapsedCategories = saved ? JSON.parse(saved) : {"Recent":false, "Search":false}
      return collapsedCategories[categoryName] === true
    } catch (e) {
      return false
    }
  }

  saveCollapsedState(categoryName, isCollapsed) {
    try {
      const saved = localStorage.getItem('mastodon-emojimart-categories-setting')
      const collapsedCategories = saved ? JSON.parse(saved) : {}
      collapsedCategories[categoryName] = isCollapsed
      localStorage.setItem('mastodon-emojimart-categories-setting', JSON.stringify(collapsedCategories))
    } catch (e) {
      // ignore save fail
    }
  }

  handleLabelClick(e) {
    e.preventDefault()
    e.stopPropagation()

    const newCollapsedState = !this.state.isCollapsed
    this.setState({ isCollapsed: newCollapsedState })
    this.saveCollapsedState(this.props.name, newCollapsedState)
  }

  expand() {
    if (this.state.isCollapsed) {
      this.setState({ isCollapsed: false })
      this.saveCollapsedState(this.props.name, false)
    }
  }

  updateCategoryVisibility() {
    if (!this.container) return

    if (this.state.isCollapsed) {
      this.container.classList.remove('shown')
      this.container.classList.add('collapsed')
    } else {
      this.container.classList.add('shown')
      this.container.classList.remove('collapsed')
    }
  }

  memoizeSize() {
    if (!this.container) {
      // probably this is a test environment, e.g. jest
      this.top = 0
      this.maxMargin = 0
      return
    }
    var parent = this.container.parentElement
    var { top, height } = this.container.getBoundingClientRect()
    var { top: parentTop } = parent.getBoundingClientRect()
    var { height: labelHeight } = this.label.getBoundingClientRect()

    this.top = top - parentTop + parent.scrollTop

    if (height == 0) {
      this.maxMargin = 0
    } else {
      this.maxMargin = height - labelHeight
    }
  }

  addLazyloadObserver() {
    this.removeLazyloadObserver()
    this.lazyloadImages = this.container.querySelectorAll(".lazy");

    this.lazyloadImages.forEach((image) => {
      this.imageObserver.observe(image);
    });
  }

  removeLazyloadObserver() {
    this.lazyloadImages.forEach((image) => {
      this.imageObserver.unobserve(image);
    })
  }

  handleOnContextMenu(e) {
    e.preventDefault();
  }

  handleScroll(scrollTop) {
    var margin = scrollTop - this.top
    margin = margin < this.minMargin ? this.minMargin : margin
    margin = margin > this.maxMargin ? this.maxMargin : margin

    if (margin == this.margin) return

    if (!this.props.hasStickyPosition) {
      this.label.style.top = `${margin}px`
    }

    this.margin = margin
    return true
  }

  getEmojis() {
    var { name, emojis, recent, perLine } = this.props

    if (name == 'Recent') {
      let { custom } = this.props
      let frequentlyUsed = recent || frequently.get(perLine)

      if (frequentlyUsed.length) {
        emojis = frequentlyUsed
          .map((id) => {
            const emoji = custom.filter((e) => e.id === id)[0]
            if (emoji) {
              return emoji
            }

            return id
          })
          .filter((id) => !!getData(id, null, null, this.data))
      }

      if (emojis.length === 0 && frequentlyUsed.length > 0) {
        return null
      }
    }

    if (emojis) {
      emojis = emojis.slice(0)
    }

    return emojis
  }

  updateDisplay(display) {
    var emojis = this.getEmojis()

    if (!emojis || !this.container) {
      return
    }

    this.container.style.display = display
  }

  setContainerRef(c) {
    this.container = c
  }

  setLabelRef(c) {
    this.label = c
  }

  render() {
    var {
        id,
        name,
        hasStickyPosition,
        emojiProps,
        i18n,
        notFound,
        notFoundEmoji,
      } = this.props,
      emojis = this.getEmojis(),
      labelStyles = {},
      labelSpanStyles = {},
      containerStyles = {}

    if (!emojis) {
      containerStyles = {
        display: 'none',
      }
    }

    if (!hasStickyPosition) {
      labelStyles = {
        height: 28,
      }

      labelSpanStyles = {
        position: 'absolute',
      }
    }

    labelStyles = {
      ...labelStyles,
    }

    const label = i18n.categories[id] || name

    const shouldRenderEmojis = !this.state.isCollapsed

    return (
      <section
        ref={this.setContainerRef}
        className="emoji-mart-category"
        aria-label={label}
        style={containerStyles}
      >
        <button
          style={labelStyles}
          data-name={name}
          className="emoji-mart-category-label"
          onClick={this.handleLabelClick}
          type="button"
        >
          <span
            style={labelSpanStyles}
            ref={this.setLabelRef}
            aria-hidden={true /* already labeled by the section aria-label */}
          >
            {label}
          </span>
        </button>

        {shouldRenderEmojis && (
          <ul className="emoji-mart-category-list">
            {emojis &&
              emojis.map((emoji) => (
                <li
                  key={
                    (emoji.short_names && emoji.short_names.join('_')) || emoji
                  }
                >
                  {NimbleEmoji({ emoji: emoji, data: this.data, ...emojiProps, lazy: true })}
                </li>
              ))}
          </ul>
        )}

        {shouldRenderEmojis && emojis && !emojis.length && (
          <NotFound
            i18n={i18n}
            notFound={notFound}
            notFoundEmoji={notFoundEmoji}
            data={this.data}
            emojiProps={emojiProps}
          />
        )}
      </section>
    )
  }
}

Category.propTypes /* remove-proptypes */ = {
  emojis: PropTypes.array,
  hasStickyPosition: PropTypes.bool,
  name: PropTypes.string.isRequired,
  native: PropTypes.bool.isRequired,
  perLine: PropTypes.number.isRequired,
  emojiProps: PropTypes.object.isRequired,
  recent: PropTypes.arrayOf(PropTypes.string),
  notFound: PropTypes.func,
  notFoundEmoji: PropTypes.string.isRequired,
}

Category.defaultProps = {
  emojis: [],
  hasStickyPosition: true,
}
