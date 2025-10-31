import classNames from 'classnames';
import PropTypes from 'prop-types';
import React from 'react';
import ImmutablePureComponent from 'react-immutable-pure-component';

export default class CustomEmojiContainer extends ImmutablePureComponent {
  static propTypes = {
    draggable: PropTypes.bool.isRequired,
    alt: PropTypes.string.isRequired,
    title: PropTypes.string.isRequired,
    src: PropTypes.string.isRequired,
    dataOriginal: PropTypes.string.isRequired,
    dataStatic: PropTypes.string.isRequired,
  };

  state = {
    hovered: false
  }

  setTargetRef = c => {
    this.target = c;
  };

  findTarget = () => {
    return this.target;
  };

  handleMouseEnter = () => this.setState({ hovered: true });

  handleMouseLeave = () => this.setState({ hovered: false });

  render() {
    const { draggable, alt, title, src, dataOriginal, dataStatic } = this.props;
    const { hovered } = this.state;

    return (
      <React.Fragment>
        <span
          className={classNames('inlined', 'custom-emoji-cover')}
          onMouseEnter={this.handleMouseEnter}
          onMouseLeave={this.handleMouseLeave}
          ref={this.setTargetRef}
        >
          <img
            className={classNames('emojione', 'custom-emoji')}
            draggable={draggable}
            alt={alt}
            title={title}
            src={src}
            data-original={dataOriginal}
            data-static={dataStatic}
          />
        </span>
        <Overlay show={hovered} offset={[0, 5]} placement={'bottom'} flip target={this.findTarget} popperConfig={{ strategy: 'fixed' }}>
          {({ props, placement }) => (
            <div {...props} >
              <div class={`dropdown-animation ${placement}`}>
                <div class='reactions-bar__item__users'>
                  <div className='reactions-bar__item__users__emoji'>
                    <span><img
                      draggable='false'
                      className='emojione custom-emoji'
                      alt={alt}
                      title={title}
                      src={dataOriginal} /></span>
                    <span className='reactions-bar__item__users__emoji__code'>{title}</span>
                  </div>
                </div>
              </div>
            </div>
          )}
        </Overlay>
      </React.Fragment>
    )
  }
}
