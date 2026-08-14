import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import ImmutablePropTypes from 'react-immutable-proptypes';

import { injectIntl } from '@/flavours/glitch/components/intl';
import SettingToggle from 'flavours/glitch/features/notifications/components/setting_toggle';

import SettingText from '../../../components/setting_text';

const messages = defineMessages({
  filter_regex: { id: 'home.column_settings.filter_regex', defaultMessage: 'Filter out by regular expressions' },
  settings: { id: 'home.settings', defaultMessage: 'Column settings' },
});

class ColumnSettings extends PureComponent {

  static propTypes = {
    settings: ImmutablePropTypes.map.isRequired,
    onChange: PropTypes.func.isRequired,
    intl: PropTypes.object.isRequired,
  };

  render () {
    const { settings, onChange, intl } = this.props;

    return (
      <div className='column-settings'>
        <section>
          <div className='column-settings__row'>
            <SettingToggle settings={settings} settingPath={['conversations']} onChange={onChange} label={<FormattedMessage id='direct.group_by_accounts' defaultMessage='Group by account' />} />
            <SettingToggle settings={settings} settingPath={['preserve_group_on_new_mentions']} onChange={onChange} disabled={!settings.get('conversations')} label={<FormattedMessage id='direct.preserve_group_on_new_mentions' defaultMessage='Keep the existing group when mentioning new users' />} />
          </div>
        </section>

        <section>
          <h3><FormattedMessage id='home.column_settings.advanced' defaultMessage='Advanced' /></h3>

          <div className='column-settings__row'>
            <SettingText settings={settings} settingPath={['regex', 'body']} onChange={onChange} label={intl.formatMessage(messages.filter_regex)} />
          </div>
        </section>
      </div>
    );
  }

}

export default injectIntl(ColumnSettings);
