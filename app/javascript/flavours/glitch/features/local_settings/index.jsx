//  Package imports.
import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import ImmutablePropTypes from 'react-immutable-proptypes';
import { connect } from 'react-redux';

//  Our imports
import { changeLocalSetting, pushLocalSettingsToServer, fetchLocalSettingsFromServer } from 'flavours/glitch/actions/local_settings';
import { closeModal } from 'flavours/glitch/actions/modal';

import LocalSettingsNavigation from './navigation';
import LocalSettingsPage from './page';

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
    const { onChange, onSyncToServer, onSyncFromServer, onClose, settings } = this.props;
    const { currentIndex } = this.state;

    return (
      <div className='glitch modal-root__modal local-settings'>
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
    );
  }

}

export default connect(mapStateToProps, mapDispatchToProps)(LocalSettings);
