import { useCallback, useState } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import PropTypes from 'prop-types';
import { connect } from 'react-redux';

import { changeLocalSetting } from '@/flavours/glitch/actions/local_settings';
import { injectIntl } from '@/flavours/glitch/components/intl';
import { apiRequestPut } from 'flavours/glitch/api';
import { applyColorScheme, applyContrast, getColorScheme, getContrast, getSupportedColorSchemes } from 'flavours/glitch/utils/theme';

const messages = defineMessages({
  color_scheme_auto: { id: 'settings.color_scheme.auto', defaultMessage: 'Sync with system' },
  color_scheme_light: { id: 'settings.color_scheme.light', defaultMessage: 'Light' },
  color_scheme_dark: { id: 'settings.color_scheme.dark', defaultMessage: 'Dark' },
  contrast_auto: { id: 'settings.contrast.auto', defaultMessage: 'Sync with system' },
  contrast_high: { id: 'settings.contrast.high', defaultMessage: 'High contrast' },
});

const RadioGroup = ({ id, legend, options, value, onChange }) => (
  <div className='glitch local-settings__page__item radio_buttons'>
    <fieldset>
      <legend>{legend}</legend>
      <div className='radio_buttons__options'>
        {options.map((opt) => {
          const optionId = `${id}--${opt.value}`;
          return (
            <label key={optionId} htmlFor={optionId}>
              <input
                type='radio'
                name={id}
                id={optionId}
                value={opt.value}
                onChange={onChange}
                checked={value === opt.value}
              />
              {opt.message}
            </label>
          );
        })}
      </div>
    </fieldset>
  </div>
);

RadioGroup.propTypes = {
  id: PropTypes.string.isRequired,
  legend: PropTypes.node.isRequired,
  options: PropTypes.array.isRequired,
  value: PropTypes.string.isRequired,
  onChange: PropTypes.func.isRequired,
};

const QuickPreferences = ({ intl, useMyArchive, onUseMyArchiveChange }) => {
  const supportedColorSchemes = getSupportedColorSchemes();
  const [currentColorScheme, setCurrentColorScheme] = useState(() => {
    const savedColorScheme = getColorScheme();
    return supportedColorSchemes.includes(savedColorScheme) ? savedColorScheme : supportedColorSchemes[0];
  });
  const [currentContrast, setCurrentContrast] = useState(getContrast());

  const persist = useCallback((data) => {
    apiRequestPut('v1/appearance', data).catch(() => undefined);
  }, []);

  const handleColorSchemeChange = useCallback((e) => {
    const value = e.target.value;
    setCurrentColorScheme(value);
    applyColorScheme(value);
    persist({ color_scheme: value });
  }, [persist]);

  const handleContrastChange = useCallback((e) => {
    const value = e.target.value;
    setCurrentContrast(value);
    applyContrast(value);
    persist({ contrast: value });
  }, [persist]);

  const handleUseMyArchiveChange = useCallback((e) => {
    const value = e.target.checked;
    onUseMyArchiveChange(value);
    persist({ use_my_archive: value });
  }, [onUseMyArchiveChange, persist]);

  return (
    <div className='glitch local-settings__page quick_preferences'>
      <h1><FormattedMessage id='settings.quick_preferences' defaultMessage='Quick preferences' /></h1>
      <p className='hint'>
        <FormattedMessage id='settings.quick_preferences.hint' defaultMessage='These settings are saved to your account and apply on all your devices.' />
      </p>
      <RadioGroup
        id='mastodon-settings--color_scheme'
        legend={<FormattedMessage id='settings.color_scheme' defaultMessage='Theme color' />}
        value={currentColorScheme}
        onChange={handleColorSchemeChange}
        options={[
          { value: 'auto', message: intl.formatMessage(messages.color_scheme_auto) },
          { value: 'light', message: intl.formatMessage(messages.color_scheme_light) },
          { value: 'dark', message: intl.formatMessage(messages.color_scheme_dark) },
        ].filter(({ value }) => supportedColorSchemes.includes(value))}
      />
      <div className='glitch local-settings__page__item boolean optional user_setting_use_my_archive'>
        <label htmlFor='mastodon-settings--use_my_archive'>
          <input
            id='mastodon-settings--use_my_archive'
            type='checkbox'
            checked={useMyArchive}
            onChange={handleUseMyArchiveChange}
          />
          <FormattedMessage id='settings.use_my_archive' defaultMessage='Use My archive' />
          <span className='hint'>
            <FormattedMessage id='settings.use_my_archive.hint' defaultMessage='Combine Favorites, Bookmarks, Reactions, and Clips into one navigation section.' />
          </span>
        </label>
      </div>
      <RadioGroup
        id='mastodon-settings--contrast'
        legend={<FormattedMessage id='settings.contrast' defaultMessage='Contrast' />}
        value={currentContrast}
        onChange={handleContrastChange}
        options={[
          { value: 'auto', message: intl.formatMessage(messages.contrast_auto) },
          { value: 'high', message: intl.formatMessage(messages.contrast_high) },
        ]}
      />
    </div>
  );
};

QuickPreferences.propTypes = {
  intl: PropTypes.object.isRequired,
  useMyArchive: PropTypes.bool.isRequired,
  onUseMyArchiveChange: PropTypes.func.isRequired,
};

const mapStateToProps = state => ({
  useMyArchive: state.getIn(['local_settings', 'use_my_archive'], false),
});

const mapDispatchToProps = dispatch => ({
  onUseMyArchiveChange: value => dispatch(changeLocalSetting(['use_my_archive'], value)),
});

export default connect(mapStateToProps, mapDispatchToProps)(injectIntl(QuickPreferences));
