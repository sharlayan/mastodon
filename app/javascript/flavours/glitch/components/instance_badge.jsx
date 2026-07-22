import React from 'react';
import PropTypes from 'prop-types';
import classNames from 'classnames';

import { softwareIconFor } from './software_icon';

export default class InstanceBadge extends React.PureComponent {

  static propTypes = {
    instanceInfo: PropTypes.shape({
      domain: PropTypes.string.isRequired,
      software: PropTypes.string,
      version: PropTypes.string,
      theme_color: PropTypes.string,
      favicon_url: PropTypes.string,
      instance_name: PropTypes.string
    }).isRequired,
    compact: PropTypes.bool,
  };

  static defaultProps = {
    compact: false,
  };

  render() {
    const { instanceInfo, compact } = this.props;
    const { domain, software, theme_color, favicon_url, instance_name } = instanceInfo;

    const softwareIcon = softwareIconFor(software);
    const style = theme_color ? {
      borderLeftColor: theme_color,
      '--instance-theme-color': theme_color,
    } : {};

    return (
      <div
        className={classNames('instance-badge', { 'instance-badge--compact': compact })}
        style={style}
      >
        <span className='instance-badge__favicon'>
          <img
            src={favicon_url || softwareIcon}
            alt=''
            className='instance-badge__favicon__image'
            onError={(e) => {
              if (e.currentTarget.dataset.fallbackApplied) {
                e.currentTarget.style.display = 'none';
              } else {
                e.currentTarget.dataset.fallbackApplied = 'true';
                e.currentTarget.src = softwareIcon;
              }
            }}
          />
        </span>
        <span className='instance-badge__domain'>{instance_name ?? domain}</span>
        {!compact && software && (
          <span className='instance-badge__software'>{software}</span>
        )}
      </div>
    );
  }

}
