import PropTypes from 'prop-types';
import { useEffect, useState, useCallback, useMemo } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { withRouter } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import api from 'flavours/glitch/api';
import {
  fetchAntenna,
  saveAntenna,
} from 'flavours/glitch/actions/antennas';
import Column from 'flavours/glitch/components/column';
import ColumnHeader from 'flavours/glitch/components/column_header';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { WithRouterPropTypes } from 'flavours/glitch/utils/react_router';

const messages = defineMessages({
  heading: { id: 'column.antennas', defaultMessage: 'Antennas' },
  saveError: { id: 'antennas.save_error', defaultMessage: 'Could not save changes. Please check your input.' },
});

const ChipList = ({ label, items, getKey, getLabel, onAdd, onRemove, placeholder, children }) => {
  const [value, setValue] = useState('');

  const handleAdd = useCallback(e => {
    e.preventDefault();
    const trimmed = value.trim();
    if (trimmed.length === 0) return;
    onAdd(trimmed);
    setValue('');
  }, [value, onAdd]);

  return (
    <section className='antenna-editor__section'>
      <h4>{label}</h4>
      <div className='antenna-editor__chips'>
        {items.map(item => (
          <span key={getKey(item)} className='antenna-editor__chip'>
            {getLabel(item)}
            <button type='button' onClick={() => { onRemove(item); }} aria-label='Remove'>×</button>
          </span>
        ))}
      </div>
      <form className='antenna-editor__form' onSubmit={handleAdd}>
        <input className='setting-text' value={value} placeholder={placeholder} onChange={e => { setValue(e.target.value); }} />
        <button type='submit' className='button button-secondary'>
          <FormattedMessage id='antennas.add' defaultMessage='Add' />
        </button>
      </form>
      {children}
    </section>
  );
};

ChipList.propTypes = {
  label: PropTypes.node.isRequired,
  items: PropTypes.array.isRequired,
  getKey: PropTypes.func.isRequired,
  getLabel: PropTypes.func.isRequired,
  onAdd: PropTypes.func.isRequired,
  onRemove: PropTypes.func.isRequired,
  placeholder: PropTypes.string,
  children: PropTypes.node,
};

const toArray = value => (value && value.toJS ? value.toJS() : (value || []));
const identity = value => value;

const BOOL_FIELDS = ['available', 'with_media_only', 'ignore_reblog'];

const buildInitialState = (antenna) => ({
  title: antenna.get('title') || '',
  keywords: toArray(antenna.get('keywords')).join('\n'),
  excludeKeywords: toArray(antenna.get('exclude_keywords')).join('\n'),
  bools: BOOL_FIELDS.reduce((acc, field) => ({ ...acc, [field]: !!antenna.get(field) }), {}),
  domains: toArray(antenna.get('domains')),
  excludeDomains: toArray(antenna.get('exclude_domains')),
  tags: toArray(antenna.get('tags')),
  excludeTags: toArray(antenna.get('exclude_tags')),
  accounts: toArray(antenna.get('accounts')).map(acct => ({ id: String(acct), label: String(acct) })),
  excludeAccounts: toArray(antenna.get('exclude_accounts')).map(acct => ({ id: String(acct), label: String(acct) })),
});

const diffStrings = (current, original) => ({
  add: current.filter(item => !original.includes(item)),
  remove: original.filter(item => !current.includes(item)),
});

const diffAccounts = (current, original) => {
  const currentIds = current.map(a => a.id);
  const originalIds = original.map(a => a.id);
  return {
    add: currentIds.filter(id => !originalIds.includes(id)),
    remove: originalIds.filter(id => !currentIds.includes(id)),
  };
};

const AntennaEdit = ({ params, multiColumn }) => {
  const { id } = params;
  const dispatch = useDispatch();
  const intl = useIntl();
  const antenna = useSelector(state => state.getIn(['antennas', id]));

  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    dispatch(fetchAntenna(id));
  }, [dispatch, id]);

  useEffect(() => {
    if (antenna && antenna.get) {
      setForm(buildInitialState(antenna));
    }
  }, [antenna]);

  const original = useMemo(() => (antenna && antenna.get ? buildInitialState(antenna) : null), [antenna]);

  const dirty = useMemo(() => {
    if (!form || !original) return false;
    return JSON.stringify(form) !== JSON.stringify(original);
  }, [form, original]);

  const update = useCallback((patch) => {
    setForm(prev => ({ ...prev, ...patch }));
  }, []);

  const handleToggle = useCallback((field) => (e) => {
    setForm(prev => ({ ...prev, bools: { ...prev.bools, [field]: e.target.checked } }));
  }, []);

  const addChip = useCallback((field) => (value) => {
    setForm(prev => (prev[field].includes(value) ? prev : { ...prev, [field]: [...prev[field], value] }));
  }, []);

  const removeChip = useCallback((field) => (value) => {
    setForm(prev => ({ ...prev, [field]: prev[field].filter(item => item !== value) }));
  }, []);

  const addAccount = useCallback((field) => (acct) => {
    api().get('/api/v1/accounts/lookup', { params: { acct: acct.replace(/^@/, '') } })
      .then(({ data }) => {
        setForm(prev => (prev[field].some(a => a.id === String(data.id))
          ? prev
          : { ...prev, [field]: [...prev[field], { id: String(data.id), label: acct }] }));
      })
      .catch(() => {});
  }, []);

  const removeAccount = useCallback((field) => (account) => {
    setForm(prev => ({ ...prev, [field]: prev[field].filter(a => a.id !== account.id) }));
  }, []);

  const handleSave = useCallback(() => {
    if (!form || !original || saving) return;

    const keywords = form.keywords.split('\n').map(s => s.trim()).filter(s => s.length > 0);

    const main = {
      title: form.title.trim(),
      keywords,
      exclude_keywords: form.excludeKeywords.split('\n').map(s => s.trim()).filter(s => s.length > 0),
      ...form.bools,
      any_keywords: keywords.length === 0,
      any_domains: form.domains.length === 0,
      any_tags: form.tags.length === 0,
      any_accounts: form.accounts.length === 0,
    };

    const domains = diffStrings(form.domains, original.domains);
    const excludeDomains = diffStrings(form.excludeDomains, original.excludeDomains);
    const tags = diffStrings(form.tags, original.tags);
    const excludeTags = diffStrings(form.excludeTags, original.excludeTags);
    const accounts = diffAccounts(form.accounts, original.accounts);
    const excludeAccounts = diffAccounts(form.excludeAccounts, original.excludeAccounts);

    setSaving(true);
    setError(null);
    dispatch(saveAntenna(id, {
      main,
      add: {
        domains: domains.add,
        exclude_domains: excludeDomains.add,
        tags: tags.add,
        exclude_tags: excludeTags.add,
        accounts: accounts.add,
        exclude_accounts: excludeAccounts.add,
      },
      remove: {
        domains: domains.remove,
        exclude_domains: excludeDomains.remove,
        tags: tags.remove,
        exclude_tags: excludeTags.remove,
        accounts: accounts.remove,
        exclude_accounts: excludeAccounts.remove,
      },
    })).catch(err => {
      setError(err?.response?.data?.error || intl.formatMessage(messages.saveError));
    }).finally(() => setSaving(false));
  }, [dispatch, id, form, original, saving, intl]);

  if (!antenna || !antenna.get || !form) {
    return (
      <Column>
        <div className='scrollable'><LoadingIndicator /></div>
      </Column>
    );
  }

  const bool = field => form.bools[field];

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.heading)}>
      <ColumnHeader title={form.title} icon='radar' iconComponent={RadarIcon} multiColumn={multiColumn} showBackButton />

      <div className='scrollable'>
        <div className='antenna-editor'>
          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.title' defaultMessage='Title' /></h4>
            <input className='setting-text' value={form.title} onChange={e => { update({ title: e.target.value }); }} />
          </section>

          <section className='antenna-editor__section'>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('available')} onChange={handleToggle('available')} /> <FormattedMessage id='antennas.available' defaultMessage='Enabled' /></label>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('with_media_only')} onChange={handleToggle('with_media_only')} /> <FormattedMessage id='antennas.with_media_only' defaultMessage='Media only' /></label>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('ignore_reblog')} onChange={handleToggle('ignore_reblog')} /> <FormattedMessage id='antennas.ignore_reblog' defaultMessage='Exclude boosts' /></label>
          </section>

          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.keywords' defaultMessage='Keywords (one per line)' /></h4>
            <textarea className='setting-text' rows={4} value={form.keywords} onChange={e => { update({ keywords: e.target.value }); }} />
            <p className='antenna-editor__hint'><FormattedMessage id='antennas.keywords_hint' defaultMessage='When empty, this condition is ignored.' /></p>
          </section>

          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.exclude_keywords' defaultMessage='Excluded keywords (one per line)' /></h4>
            <textarea className='setting-text' rows={3} value={form.excludeKeywords} onChange={e => { update({ excludeKeywords: e.target.value }); }} />
          </section>

          <ChipList
            label={<FormattedMessage id='antennas.domains' defaultMessage='Domains' />}
            items={form.domains}
            getKey={identity}
            getLabel={identity}
            onAdd={addChip('domains')}
            onRemove={removeChip('domains')}
            placeholder='example.com'
          />

          <ChipList
            label={<FormattedMessage id='antennas.exclude_domains' defaultMessage='Excluded domains' />}
            items={form.excludeDomains}
            getKey={identity}
            getLabel={identity}
            onAdd={addChip('excludeDomains')}
            onRemove={removeChip('excludeDomains')}
            placeholder='example.com'
          />

          <ChipList
            label={<FormattedMessage id='antennas.tags' defaultMessage='Hashtags' />}
            items={form.tags}
            getKey={identity}
            getLabel={identity}
            onAdd={addChip('tags')}
            onRemove={removeChip('tags')}
            placeholder='#art'
          />

          <ChipList
            label={<FormattedMessage id='antennas.exclude_tags' defaultMessage='Excluded hashtags' />}
            items={form.excludeTags}
            getKey={identity}
            getLabel={identity}
            onAdd={addChip('excludeTags')}
            onRemove={removeChip('excludeTags')}
            placeholder='#spoiler'
          />

          <ChipList
            label={<FormattedMessage id='antennas.accounts' defaultMessage='Accounts' />}
            items={form.accounts}
            getKey={account => account.id}
            getLabel={account => account.label}
            onAdd={addAccount('accounts')}
            onRemove={removeAccount('accounts')}
            placeholder='@user@example.com'
          />

          <ChipList
            label={<FormattedMessage id='antennas.exclude_accounts' defaultMessage='Excluded accounts' />}
            items={form.excludeAccounts}
            getKey={account => account.id}
            getLabel={account => account.label}
            onAdd={addAccount('excludeAccounts')}
            onRemove={removeAccount('excludeAccounts')}
            placeholder='@user@example.com'
          />

          {error && (
            <section className='antenna-editor__section'>
              <p className='antenna-editor__error' role='alert'>{error}</p>
            </section>
          )}

          <section className='antenna-editor__section antenna-editor__actions'>
            <button type='button' className='button' onClick={handleSave} disabled={!dirty || saving}>
              <FormattedMessage id='antennas.save' defaultMessage='Save changes' />
            </button>
            {dirty && (
              <span className='antenna-editor__unsaved'>
                <FormattedMessage id='antennas.unsaved_changes' defaultMessage='You have unsaved changes' />
              </span>
            )}
          </section>
        </div>
      </div>

      <Helmet>
        <title>{form.title}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

AntennaEdit.propTypes = {
  params: PropTypes.object.isRequired,
  multiColumn: PropTypes.bool,
  ...WithRouterPropTypes,
};

export default withRouter(AntennaEdit);
