import { useCallback, useMemo, useRef, useState } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';

import { Button } from '@/flavours/glitch/components/button';
import { apiRequestPut } from 'flavours/glitch/api';
import { userTheme, userThemeCatalog, userThemeDefaults } from 'flavours/glitch/initial_state';
import { containsUnsafeUserThemeValue, encodeUserThemeStorage, isSafeUserThemeValue, parseUserThemeOverrides, portableUserThemeConfig, resolveUserThemeConfig, userThemeCatalogForActiveSkin, USER_THEME_VARIABLE_GROUPS, watchUserTheme } from 'flavours/glitch/sharlayan/user_theme';

import ColorPicker from './color_picker';

const UserThemePage = () => {
  const intl = useIntl();
  const catalog = useMemo(() => userThemeCatalogForActiveSkin(userThemeCatalog), []);
  const [overrides, setOverrides] = useState(() => parseUserThemeOverrides(userTheme));
  const config = useMemo(() => resolveUserThemeConfig(overrides, userThemeDefaults), [overrides]);
  const [activeCategories, setActiveCategories] = useState({ light: USER_THEME_VARIABLE_GROUPS[0].id, dark: USER_THEME_VARIABLE_GROUPS[0].id });
  const [importError, setImportError] = useState(false);
  const [unsafeValue, setUnsafeValue] = useState(false);
  const [saveState, setSaveState] = useState('saved');
  const importInput = useRef(null);
  const revision = useRef(0);

  const updateOverrides = useCallback((nextOverrides) => {
    revision.current += 1;
    setOverrides(nextOverrides);
    watchUserTheme(resolveUserThemeConfig(nextOverrides, userThemeDefaults), catalog);
    setSaveState('dirty');
  }, [catalog]);

  const save = useCallback(async () => {
    const savedRevision = revision.current;
    setSaveState('saving');
    try {
      await apiRequestPut('v1/appearance', { user_theme: encodeUserThemeStorage(parseUserThemeOverrides(overrides)) });
      setSaveState(revision.current === savedRevision ? 'saved' : 'dirty');
    } catch {
      setSaveState('error');
    }
  }, [overrides]);

  const changeTheme = useCallback((scheme, theme) => {
    updateOverrides({ ...overrides, [scheme]: { ...overrides[scheme], theme } });
  }, [overrides, updateOverrides]);

  const editVariable = useCallback((scheme, variable, value) => {
    const nextOverrides = {
      ...overrides,
      [scheme]: {
        ...overrides[scheme],
        variables: { ...overrides[scheme]?.variables, [variable]: value },
      },
    };
    updateOverrides(nextOverrides);
  }, [overrides, updateOverrides]);

  const persistVariable = useCallback((scheme, variable, value) => {
    const variables = { ...overrides[scheme]?.variables };
    if (value.trim() && isSafeUserThemeValue(variable, value.trim())) {
      variables[variable] = value.trim();
      setUnsafeValue(false);
    } else if (value.trim()) {
      delete variables[variable];
      setUnsafeValue(true);
    } else delete variables[variable];
    const schemeOverrides = { ...overrides[scheme], variables };
    if (Object.keys(variables).length === 0) delete schemeOverrides.variables;
    updateOverrides({ ...overrides, [scheme]: schemeOverrides });
  }, [overrides, updateOverrides]);

  const deleteVariable = useCallback((scheme, variable) => {
    const variables = { ...overrides[scheme]?.variables };
    delete variables[variable];
    const schemeOverrides = { ...overrides[scheme] };
    if (Object.keys(variables).length > 0) schemeOverrides.variables = variables;
    else delete schemeOverrides.variables;
    const nextOverrides = { ...overrides };
    if (Object.keys(schemeOverrides).length > 0) nextOverrides[scheme] = schemeOverrides;
    else delete nextOverrides[scheme];
    updateOverrides(nextOverrides);
  }, [overrides, updateOverrides]);

  const resetScheme = useCallback((scheme) => {
    const nextOverrides = { ...overrides };
    delete nextOverrides[scheme];
    updateOverrides(nextOverrides);
  }, [overrides, updateOverrides]);

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
      updateOverrides(parseUserThemeOverrides(imported));
    } catch {
      setImportError(true);
    }
  }, [updateOverrides]);

  return (
    <div className='glitch local-settings__page user-theme'>
      <h1><FormattedMessage id='settings.user_theme' defaultMessage='User theme' /></h1>
      <p className='hint'><FormattedMessage id='settings.user_theme.hint' defaultMessage='Layer a server theme and your own allowed CSS variable values over the selected flavour and theme.' /></p>
      <div className='user-theme__share'>
        <Button onClick={save} disabled={saveState === 'saved' || saveState === 'saving'}><FormattedMessage id='settings.user_theme.save' defaultMessage='Save changes' /></Button>
        {saveState === 'saved' && <span><FormattedMessage id='settings.user_theme.saved' defaultMessage='Saved' /></span>}
        {saveState === 'error' && <span className='user-theme__error'><FormattedMessage id='settings.user_theme.save_error' defaultMessage='Could not save the theme.' /></span>}
      </div>
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
            <div className='user-theme__category-tabs' role='tablist'>
              {USER_THEME_VARIABLE_GROUPS.map(group => (
                <button
                  type='button'
                  role='tab'
                  id={`user-theme-${scheme}-category-${group.id}`}
                  aria-controls={`user-theme-${scheme}-variables-${group.id}`}
                  aria-selected={activeCategories[scheme] === group.id}
                  className={activeCategories[scheme] === group.id ? 'active' : undefined}
                  onClick={() => setActiveCategories(current => ({ ...current, [scheme]: group.id }))}
                  key={group.id}
                >
                  <FormattedMessage id={`settings.user_theme.category.${group.id}`} defaultMessage={group.id} />
                </button>
              ))}
            </div>
            {USER_THEME_VARIABLE_GROUPS.filter(group => group.id === activeCategories[scheme]).map(group => (
              <section
                className='user-theme__variable-group'
                role='tabpanel'
                id={`user-theme-${scheme}-variables-${group.id}`}
                aria-labelledby={`user-theme-${scheme}-category-${group.id}`}
                key={group.id}
              >
                <div className='user-theme__variable-group__items'>
                  {group.variables.map(({ name, type }) => {
                    const hasOverride = Object.hasOwn(overrides[scheme]?.variables ?? {}, name);
                    const value = (hasOverride ? overrides[scheme].variables[name] : config[scheme].variables[name]) ?? '';
                    return (
                      <div className='user-theme__variable' key={name}>
                        <code>{name}</code>
                        <span className={`user-theme__variable__inputs user-theme__variable__inputs--${type}`}>
                          {type === 'color' && <ColorPicker value={value} variable={name} onChange={nextValue => editVariable(scheme, name, nextValue)} />}
                          <input type='text' value={value} aria-label={name} placeholder='inherit' onChange={event => editVariable(scheme, name, event.target.value)} onBlur={event => persistVariable(scheme, name, event.target.value)} />
                          <button
                            type='button'
                            className='user-theme__variable__delete'
                            disabled={!hasOverride}
                            aria-label={intl.formatMessage({ id: 'settings.user_theme.delete_value', defaultMessage: 'Remove custom value for {variable}' }, { variable: name })}
                            title={intl.formatMessage({ id: 'settings.user_theme.delete_value', defaultMessage: 'Remove custom value for {variable}' }, { variable: name })}
                            onClick={() => deleteVariable(scheme, name)}
                          >
                            <DeleteIcon />
                          </button>
                        </span>
                      </div>
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
