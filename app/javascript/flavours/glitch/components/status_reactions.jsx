import PropTypes from 'prop-types';
import React from 'react';
import classNames from 'classnames';
import ImmutablePropTypes from 'react-immutable-proptypes';
import ImmutablePureComponent from 'react-immutable-pure-component';

import { unicodeMapping } from '../features/emoji/emoji_unicode_mapping_light';
import { autoPlayGif, reactionCustomEmojiSize } from '../initial_state';
import { assetHost } from '../utils/config';

import Overlay from 'react-overlays/Overlay';
import { Avatar } from './avatar';
import { DisplayName } from './display_name';
import { AnimatedNumber } from './animated_number';

import { createAccountFromServerJSON } from '../models/account';
import { List } from 'immutable';

export default class StatusReactions extends ImmutablePureComponent {

  static propTypes = {
    statusId: PropTypes.string.isRequired,
    reactions: ImmutablePropTypes.list.isRequired,
    numVisible: PropTypes.number,
    addReaction: PropTypes.func.isRequired,
    canReact: PropTypes.bool.isRequired,
    removeReaction: PropTypes.func.isRequired,
  };

  render() {
    const { reactions, numVisible } = this.props;

    let visibleReactions = reactions
      .filter(x => x.get('count') > 0)
      .sort((a, b) => b.get('count') - a.get('count'));

    if (numVisible >= 0) {
      visibleReactions = visibleReactions.filter((_, i) => i < numVisible);
    }

    return (
      <div className={classNames('reactions-bar', { 'reactions-bar--empty': visibleReactions.isEmpty() })}>
        {visibleReactions.map(reaction => (
          <Reaction
            key={reaction.get('name')}
            statusId={this.props.statusId}
            reaction={reaction}
            addReaction={this.props.addReaction}
            removeReaction={this.props.removeReaction}
            canReact={this.props.canReact}
          />
        ))}
      </div>
    );
  }

}

class Reaction extends ImmutablePureComponent {
  static propTypes = {
    statusId: PropTypes.string,
    reaction: ImmutablePropTypes.map.isRequired,
    addReaction: PropTypes.func.isRequired,
    removeReaction: PropTypes.func.isRequired,
    canReact: PropTypes.bool.isRequired,
    style: PropTypes.object,
    accounts: ImmutablePropTypes.map.isRequired,
  };

  state = {
    hovered: false,
  };

  handleClick = () => {
    const { reaction, statusId, addReaction, removeReaction } = this.props;

    if (reaction.get('me')) {
      removeReaction(statusId, reaction.get('name'));
    } else {
      addReaction(statusId, reaction.get('name'));
    }
  };

  setTargetRef = c => {
    this.target = c;
  };

  findTarget = () => {
    return this.target;
  };

  handleMouseEnter = () => this.setState({ hovered: true });

  handleMouseLeave = () => this.setState({ hovered: false });

  render() {
    const { reaction } = this.props;
    const { hovered } = this.state;

    const name = reaction.get('name');
    const count = reaction.get('count', 0);
    const users = reaction.get('users');
    const url = reaction.get('url');
    const staticUrl = reaction.get('static_url');

    const validUsers = users ? users
      .filter(user => user && (user.get ? user.get('acct') : user.acct))
      .map(user => {
        try {
          const userJson = user.toJS ? user.toJS() : user;

          if (!userJson.id || !userJson.username) {
            console.warn('Invalid user data:', userJson);
            return null;
          }

          return createAccountFromServerJSON(userJson);
        } catch (error) {
          console.error('Failed to convert user to Account:', error, user);
          return null;
        }
      })
      .filter(account => account !== null)
      : List();

    const hasValidUsers = validUsers.size > 0;

    let shortCode = name;
    let title;
    if (unicodeMapping[shortCode]) {
      shortCode = unicodeMapping[shortCode].shortCode;
      title = `:${shortCode}:`;
    } else {
      title = `:${shortCode}:`;
    }

    const classes = `reactions-bar__item__users__emoji${reactionCustomEmojiSize ? ' horizontal-origin' : ''}`;

    return (
      <React.Fragment>
        <span
          onMouseEnter={this.handleMouseEnter}
          onMouseLeave={this.handleMouseLeave}
          ref={this.setTargetRef}
        >
          <button
            className={classNames('reactions-bar__item', { active: reaction.get('me') })}
            onClick={this.handleClick}
            disabled={!this.props.canReact}
          >
            <span className={classes}>
              <Emoji
                hovered={hovered}
                emoji={reaction.get('name')}
                url={reaction.get('url')}
                staticUrl={reaction.get('static_url')}
              />
            </span>
            <span className='reactions-bar__item__count'>
              <AnimatedNumber value={reaction.get('count')} />
            </span>
          </button>
        </span>
        {hasValidUsers && (
          <Overlay
            show={hovered}
            offset={[0, 5]}
            placement={'bottom'}
            flip
            target={this.findTarget}
            popperConfig={{ strategy: 'fixed' }}
          >
            {({ props, placement }) => (
              <div {...props}>
                <div className={`dropdown-animation ${placement}`}>
                  <div className='reactions-bar__item__users'>
                    <div className={classes}>
                      <span>
                        <Emoji
                          hovered={hovered}
                          emoji={name}
                          url={url}
                          staticUrl={staticUrl}
                        />
                      </span>
                      <span className='reactions-bar__item__users__emoji__code'>{title}</span>
                    </div>
                    <div className='reactions-bar__item__users__list'>
                      {validUsers.map(user => (
                        <span className='reactions-bar__item__users__item' key={user.get('acct')}>
                          <Avatar account={user} size={24} />
                          <DisplayName account={user} />
                        </span>
                      ))}
                      {count > 11 && (
                        <span className='reactions-bar__item__users__item'>
                          +{count - 11}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            )}
          </Overlay>
        )}
      </React.Fragment>
    );
  }

}

class Emoji extends React.PureComponent {

  static propTypes = {
    emoji: PropTypes.string.isRequired,
    hovered: PropTypes.bool.isRequired,
    url: PropTypes.string,
    staticUrl: PropTypes.string,
  };

  render() {
    const { emoji, hovered, url, staticUrl } = this.props;

    if (unicodeMapping[emoji]) {
      const { filename, shortCode } = unicodeMapping[this.props.emoji];
      const title = shortCode ? `:${shortCode}:` : '';

      return (
        <img
          draggable='false'
          className='emojione'
          alt={emoji}
          src={`${assetHost}/emoji/${filename}.svg`}
        />
      );
    } else {
      const filename = (autoPlayGif || hovered) ? url : staticUrl;
      const shortCode = `:${emoji}:`;
      const classes = `emojione custom-emoji${reactionCustomEmojiSize ? ' horizontal-origin-custom-emoji' : ''}`;
      return (
        <img
          draggable='false'
          className={classes}
          alt={shortCode}
          src={filename}
        />
      );
    }
  }

}
