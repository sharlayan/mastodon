import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { FormattedMessage } from 'react-intl';

import ImmutablePropTypes from 'react-immutable-proptypes';

import { injectIntl } from '@/flavours/glitch/components/intl';
import SettingToggle from 'flavours/glitch/features/notifications/components/setting_toggle';

class ColumnSettings extends PureComponent {

  static propTypes = {
    settings: ImmutablePropTypes.map.isRequired,
    onChange: PropTypes.func.isRequired,
    intl: PropTypes.object.isRequired,
    columnId: PropTypes.string,
  };

  render () {
    const { settings, onChange } = this.props;

    return (
      <div className='column-settings'>
        <section>
          <div className='column-settings__row'>
            <SettingToggle settings={settings} settingPath={['other', 'hidePublic']} onChange={onChange} label={<FormattedMessage id='admin_timeline.column_settings.hide_public' defaultMessage='Hide public posts' />} />
            <SettingToggle settings={settings} settingPath={['other', 'hideUnlisted']} onChange={onChange} label={<FormattedMessage id='admin_timeline.column_settings.hide_unlisted' defaultMessage='Hide unlisted posts' />} />
            <SettingToggle settings={settings} settingPath={['other', 'hidePrivate']} onChange={onChange} label={<FormattedMessage id='admin_timeline.column_settings.hide_private' defaultMessage='Hide followers-only posts' />} />
            <SettingToggle settings={settings} settingPath={['other', 'groupDirect']} onChange={onChange} label={<FormattedMessage id='admin_timeline.column_settings.group_direct' defaultMessage='Group direct conversations' />} />
          </div>
        </section>
      </div>
    );
  }

}

export default injectIntl(ColumnSettings);
