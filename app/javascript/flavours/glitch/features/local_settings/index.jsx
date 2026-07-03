//  Package imports.
import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages } from 'react-intl';

import ImmutablePropTypes from 'react-immutable-proptypes';
import { connect } from 'react-redux';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings-fill.svg?react';
import { Icon } from '@/flavours/glitch/components/icon';
import { injectIntl } from '@/flavours/glitch/components/intl';

//  Our imports
import { changeLocalSetting, pushLocalSettingsToServer, fetchLocalSettingsFromServer } from 'flavours/glitch/actions/local_settings';
import { closeModal } from 'flavours/glitch/actions/modal';
import { preferencesLink } from 'flavours/glitch/utils/backend_links';

import LocalSettingsNavigation from './navigation';
import LocalSettingsPage from './page';

const messages = defineMessages({
  title: { id: 'navigation_bar.app_settings', defaultMessage: 'App settings' },
  preferences: { id: 'settings.preferences', defaultMessage: 'Preferences' },
  close: { id: 'settings.close', defaultMessage: 'Close' },
});

const mapStateToProps = state => ({
  settings: state.get('local_settings'),
});

const mapDispatchToProps = dispatch => ({
  onChange (setting, value) {
    dispatch(changeLocalSetting(setting, value));
  },
  onSyncToServer () {
    dispatch(pushLocalSettingsToServer());
  },
  onSyncFromServer () {
    dispatch(fetchLocalSettingsFromServer());
  },
  onClose () {
    dispatch(closeModal({
      modalType: undefined,
      ignoreFocus: false,
    }));
  },
});

class LocalSettings extends PureComponent {

  static propTypes = {
    intl: PropTypes.object.isRequired,
    onChange: PropTypes.func.isRequired,
    onSyncToServer: PropTypes.func.isRequired,
    onSyncFromServer: PropTypes.func.isRequired,
    onClose: PropTypes.func.isRequired,
    settings: ImmutablePropTypes.map.isRequired,
  };

  state = {
    currentIndex: 0,
  };

  navigateTo = (index) =>
    this.setState({ currentIndex: +index });

  render () {

    const { navigateTo } = this;
    const { intl, onChange, onSyncToServer, onSyncFromServer, onClose, settings } = this.props;
    const { currentIndex } = this.state;

    return (
      <div className='glitch modal-root__modal local-settings'>
        <div className='glitch local-settings__header'>
          <span className='local-settings__header__title'>
            {intl.formatMessage(messages.title)}
          </span>
          <div className='local-settings__header__tools'>
            <a
              href={preferencesLink}
              className='local-settings__header__button'
              title={intl.formatMessage(messages.preferences)}
              aria-label={intl.formatMessage(messages.preferences)}
            >
              <Icon id='cog' icon={SettingsIcon} />
            </a>
            <button
              onClick={onClose}
              className='local-settings__header__button'
              title={intl.formatMessage(messages.close)}
              aria-label={intl.formatMessage(messages.close)}
            >
              <Icon id='times' icon={CloseIcon} />
            </button>
          </div>
        </div>
        <div className='glitch local-settings__content'>
          <div className='local-settings__page__decoration-before' />
          <LocalSettingsNavigation
            index={currentIndex}
            onClose={onClose}
            onNavigate={navigateTo}
          />
          <LocalSettingsPage
            index={currentIndex}
            onChange={onChange}
            onSyncToServer={onSyncToServer}
            onSyncFromServer={onSyncFromServer}
            settings={settings}
          />
          <div className='local-settings__page__decoration-after' />
        </div>
      </div>
    );
  }

}

export default connect(mapStateToProps, mapDispatchToProps)(injectIntl(LocalSettings));
