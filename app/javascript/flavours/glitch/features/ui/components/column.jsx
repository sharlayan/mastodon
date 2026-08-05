import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { debounce } from 'lodash';

import ColumnHeader from '../../../components/column_header';
import { isMobile } from '../../../is_mobile';
import { scrollTop } from '../../../scroll';

import { ColumnWidthContext } from '../util/column_width_context';

export default class Column extends PureComponent {

  static contextType = ColumnWidthContext;

  static propTypes = {
    heading: PropTypes.string,
    alwaysShowBackButton: PropTypes.bool,
    icon: PropTypes.string,
    iconComponent: PropTypes.func,
    children: PropTypes.node,
    active: PropTypes.bool,
    hideHeadingOnMobile: PropTypes.bool,
    name: PropTypes.string,
    bindToDocument: PropTypes.bool,
  };

  handleHeaderClick = () => {
    const scrollable = this.props.bindToDocument ? document.scrollingElement : this.node.querySelector('.scrollable');

    if (!scrollable) {
      return;
    }

    this._interruptScrollAnimation = scrollTop(scrollable);
  };

  scrollTop () {
    const scrollable = this.props.bindToDocument ? document.scrollingElement : this.node.querySelector('.scrollable');

    if (!scrollable) {
      return;
    }

    this._interruptScrollAnimation = scrollTop(scrollable);
  }


  handleScroll = debounce(() => {
    if (typeof this._interruptScrollAnimation !== 'undefined') {
      this._interruptScrollAnimation();
    }
  }, 200);

  setRef = (c) => {
    this.node = c;
  };

  render () {
    const { heading, icon, iconComponent, children, active, hideHeadingOnMobile, alwaysShowBackButton, name } = this.props;
    const { customized, width } = this.context;

    const showHeading = heading && (!hideHeadingOnMobile || (hideHeadingOnMobile && !isMobile(window.innerWidth)));

    const columnHeaderId = showHeading && heading.replace(/ /g, '-');

    const header = showHeading && (
      <ColumnHeader icon={icon} iconComponent={iconComponent} active={active} title={heading} onClick={this.handleHeaderClick} columnHeaderId={columnHeaderId} showBackButton={alwaysShowBackButton} />
    );
    return (
      <div
        ref={this.setRef}
        role='region'
        data-column={name}
        aria-labelledby={columnHeaderId}
        className='column'
        onScroll={this.handleScroll}
        style={customized && width ? { '--column-width': `${width}px` } : undefined}
      >
        {header}
        {children}
      </div>
    );
  }

}
