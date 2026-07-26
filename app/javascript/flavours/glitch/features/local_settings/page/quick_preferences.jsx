import { useCallback, useState } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import PropTypes from 'prop-types';

import { injectIntl } from '@/flavours/glitch/components/intl';
import { apiRequestPut } from 'flavours/glitch/api';
import { applyColorScheme, applyContrast, getColorScheme, getContrast } from 'flavours/glitch/utils/theme';

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

const QuickPreferences = ({ intl }) => {
  const [currentColorScheme, setCurrentColorScheme] = useState(getColorScheme());
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
        ]}
      />
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
};

export default injectIntl(QuickPreferences);
