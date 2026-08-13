import { useCallback, useMemo, useRef, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { Button } from '@/flavours/glitch/components/button';
import { apiRequestPut } from 'flavours/glitch/api';
import { userTheme, userThemeCatalog, userThemeDefaults } from 'flavours/glitch/initial_state';
import { containsUnsafeUserThemeValue, encodeUserThemeStorage, isSafeUserThemeValue, parseUserThemeCatalog, portableUserThemeConfig, resolveUserThemeConfig, USER_THEME_VARIABLE_GROUPS, watchUserTheme } from 'flavours/glitch/sharlayan/user_theme';

const hexColor = (value) => {
  const match = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value);
  if (!match) return '#000000';
  if (match[1].length === 6) return value;
  return `#${match[1].split('').map(character => character.repeat(2)).join('')}`;
};

const UserThemePage = () => {
  const catalog = useMemo(() => parseUserThemeCatalog(userThemeCatalog), []);
  const serverDefaults = useMemo(() => resolveUserThemeConfig({}, userThemeDefaults), []);
  const [config, setConfig] = useState(() => resolveUserThemeConfig(userTheme, userThemeDefaults));
  const [importError, setImportError] = useState(false);
  const [unsafeValue, setUnsafeValue] = useState(false);
  const importInput = useRef(null);

  const persist = useCallback((nextConfig) => {
    setConfig(nextConfig);
    watchUserTheme(nextConfig, catalog);
    apiRequestPut('v1/appearance', { user_theme: encodeUserThemeStorage(nextConfig) }).catch(() => undefined);
  }, [catalog]);

  const changeTheme = useCallback((scheme, theme) => {
    persist({ ...config, [scheme]: { ...config[scheme], theme } });
  }, [config, persist]);

  const editVariable = useCallback((scheme, variable, value) => {
    const nextConfig = {
      ...config,
      [scheme]: {
        ...config[scheme],
        variables: { ...config[scheme].variables, [variable]: value },
      },
    };
    setConfig(nextConfig);
  }, [config]);

  const persistVariable = useCallback((scheme, variable, value) => {
    const variables = { ...config[scheme].variables };
    if (value.trim() && isSafeUserThemeValue(variable, value.trim())) {
      variables[variable] = value.trim();
      setUnsafeValue(false);
    } else if (value.trim()) {
      delete variables[variable];
      setUnsafeValue(true);
    } else delete variables[variable];
    persist({ ...config, [scheme]: { ...config[scheme], variables } });
  }, [config, persist]);

  const resetScheme = useCallback((scheme) => {
    persist({ ...config, [scheme]: serverDefaults[scheme] });
  }, [config, persist, serverDefaults]);

  const exportTheme = useCallback(() => {
    const contents = JSON.stringify({ format: 'sharlayan-user-theme', version: 1, theme: portableUserThemeConfig(config, catalog) }, null, 2);
    const url = URL.createObjectURL(new Blob([contents], { type: 'application/json' }));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'sharlayan-user-theme.json';
    anchor.click();
    URL.revokeObjectURL(url);
  }, [catalog, config]);

  const importTheme = useCallback(async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;

    try {
      const parsed = JSON.parse(await file.text());
      const imported = parsed?.format === 'sharlayan-user-theme' ? parsed.theme : parsed;
      if (!imported || typeof imported !== 'object' || Array.isArray(imported)) throw new TypeError();
      const discardedUnsafeValue = containsUnsafeUserThemeValue(imported);
      setImportError(false);
      setUnsafeValue(discardedUnsafeValue);
      persist(resolveUserThemeConfig(imported, {}));
    } catch {
      setImportError(true);
    }
  }, [persist]);

  return (
    <div className='glitch local-settings__page user-theme'>
      <h1><FormattedMessage id='settings.user_theme' defaultMessage='User theme' /></h1>
      <p className='hint'><FormattedMessage id='settings.user_theme.hint' defaultMessage='Layer a server theme and your own allowed CSS variable values over the selected flavour and theme.' /></p>
      <div className='user-theme__share'>
        <Button onClick={exportTheme}><FormattedMessage id='settings.user_theme.export' defaultMessage='Export' /></Button>
        <Button secondary onClick={() => importInput.current?.click()}><FormattedMessage id='settings.user_theme.import' defaultMessage='Import' /></Button>
        <input ref={importInput} type='file' accept='application/json,.json' onChange={importTheme} />
      </div>
      <p className='hint'><FormattedMessage id='settings.user_theme.share_hint' defaultMessage='Theme files contain only the selected light/dark themes and allowed variable overrides.' /></p>
      {importError && <p className='user-theme__error'><FormattedMessage id='settings.user_theme.import_invalid' defaultMessage='This theme file is invalid.' /></p>}
      {unsafeValue && <p className='user-theme__error'><FormattedMessage id='settings.user_theme.unsafe_value' defaultMessage='An unsupported or unsafe CSS value was removed.' /></p>}
      {['light', 'dark'].map(scheme => (
        <section className='user-theme__scheme' key={scheme}>
          <div className='user-theme__scheme__heading'>
            <h2><FormattedMessage id={`settings.user_theme.${scheme}`} defaultMessage={scheme === 'light' ? 'Light mode' : 'Dark mode'} /></h2>
            <Button secondary onClick={() => resetScheme(scheme)}><FormattedMessage id='settings.user_theme.reset' defaultMessage='Reset' /></Button>
          </div>
          <label className='user-theme__select' htmlFor={`user-theme-${scheme}`}>
            <span><FormattedMessage id='settings.user_theme.base' defaultMessage='Base variable theme' /></span>
            <select id={`user-theme-${scheme}`} value={config[scheme].theme} onChange={event => changeTheme(scheme, event.target.value)}>
              <option value='default'><FormattedMessage id='settings.user_theme.default' defaultMessage='Flavour default' /></option>
              {catalog.filter(theme => Object.keys(theme.variables[scheme]).length > 0).map(theme => <option key={theme.id} value={theme.id}>{theme.name}</option>)}
            </select>
          </label>
          <div className='user-theme__variables'>
            {USER_THEME_VARIABLE_GROUPS.map(group => (
              <section className='user-theme__variable-group' key={group.id}>
                <h3><FormattedMessage id={`settings.user_theme.category.${group.id}`} defaultMessage={group.id} /></h3>
                <div className='user-theme__variable-group__items'>
                  {group.variables.map(({ name, type }) => {
                    const value = config[scheme].variables[name] ?? '';
                    return (
                      <label className='user-theme__variable' key={name}>
                        <code>{name}</code>
                        <span className={`user-theme__variable__inputs user-theme__variable__inputs--${type}`}>
                          {type === 'color' && <input type='color' value={hexColor(value)} aria-label={name} onChange={event => editVariable(scheme, name, event.target.value)} onBlur={event => persistVariable(scheme, name, event.target.value)} />}
                          <input type='text' value={value} placeholder='inherit' onChange={event => editVariable(scheme, name, event.target.value)} onBlur={event => persistVariable(scheme, name, event.target.value)} />
                        </span>
                      </label>
                    );
                  })}
                </div>
              </section>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
};

export default UserThemePage;
