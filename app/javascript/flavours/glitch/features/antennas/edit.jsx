import PropTypes from 'prop-types';
import { useEffect, useState, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { withRouter } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import api from 'flavours/glitch/api';
import {
  fetchAntenna,
  updateAntenna,
  addAntennaDomains,
  removeAntennaDomains,
  addAntennaTags,
  removeAntennaTags,
  addAntennaAccount,
  removeAntennaAccount,
} from 'flavours/glitch/actions/antennas';
import Column from 'flavours/glitch/components/column';
import ColumnHeader from 'flavours/glitch/components/column_header';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { WithRouterPropTypes } from 'flavours/glitch/utils/react_router';

const messages = defineMessages({
  heading: { id: 'column.antennas', defaultMessage: 'Antennas' },
});

const ChipList = ({ label, items, onAdd, onRemove, placeholder, children }) => {
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
          <span key={item} className='antenna-editor__chip'>
            {item}
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
  onAdd: PropTypes.func.isRequired,
  onRemove: PropTypes.func.isRequired,
  placeholder: PropTypes.string,
  children: PropTypes.node,
};

const toArray = value => (value && value.toJS ? value.toJS() : (value || []));

const AntennaEdit = ({ params, multiColumn }) => {
  const { id } = params;
  const dispatch = useDispatch();
  const intl = useIntl();
  const antenna = useSelector(state => state.getIn(['antennas', id]));

  const [title, setTitle] = useState('');
  const [keywords, setKeywords] = useState('');
  const [excludeKeywords, setExcludeKeywords] = useState('');

  useEffect(() => {
    dispatch(fetchAntenna(id));
  }, [dispatch, id]);

  useEffect(() => {
    if (antenna && antenna.get) {
      setTitle(antenna.get('title') || '');
      setKeywords(toArray(antenna.get('keywords')).join('\n'));
      setExcludeKeywords(toArray(antenna.get('exclude_keywords')).join('\n'));
    }
  }, [antenna]);

  const handleSave = useCallback(() => {
    dispatch(updateAntenna(id, {
      title: title.trim(),
      keywords: keywords.split('\n').map(s => s.trim()).filter(s => s.length > 0),
      exclude_keywords: excludeKeywords.split('\n').map(s => s.trim()).filter(s => s.length > 0),
    }));
  }, [dispatch, id, title, keywords, excludeKeywords]);

  const handleToggle = useCallback((field) => (e) => {
    dispatch(updateAntenna(id, { [field]: e.target.checked }));
  }, [dispatch, id]);

  const handleAddAccount = useCallback((exclude) => (acct) => {
    api().get('/api/v1/accounts/lookup', { params: { acct: acct.replace(/^@/, '') } })
      .then(({ data }) => dispatch(addAntennaAccount(id, data.id, exclude)))
      .catch(() => {});
  }, [dispatch, id]);

  if (!antenna || !antenna.get) {
    return (
      <Column>
        <div className='scrollable'><LoadingIndicator /></div>
      </Column>
    );
  }

  const bool = field => antenna.get(field);

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.heading)}>
      <ColumnHeader title={antenna.get('title')} icon='radar' iconComponent={RadarIcon} multiColumn={multiColumn} showBackButton />

      <div className='scrollable'>
        <div className='antenna-editor'>
          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.title' defaultMessage='Title' /></h4>
            <input className='setting-text' value={title} onChange={e => { setTitle(e.target.value); }} onBlur={handleSave} />
          </section>

          <section className='antenna-editor__section'>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('available')} onChange={handleToggle('available')} /> <FormattedMessage id='antennas.available' defaultMessage='Enabled' /></label>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('with_media_only')} onChange={handleToggle('with_media_only')} /> <FormattedMessage id='antennas.with_media_only' defaultMessage='Media only' /></label>
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('ignore_reblog')} onChange={handleToggle('ignore_reblog')} /> <FormattedMessage id='antennas.ignore_reblog' defaultMessage='Exclude boosts' /></label>
          </section>

          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.keywords' defaultMessage='Keywords (one per line)' /></h4>
            <textarea className='setting-text' rows={4} value={keywords} onChange={e => { setKeywords(e.target.value); }} onBlur={handleSave} />
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('any_keywords')} onChange={handleToggle('any_keywords')} /> <FormattedMessage id='antennas.any_keywords' defaultMessage='Match any keyword (ignore this condition when empty)' /></label>
          </section>

          <section className='antenna-editor__section'>
            <h4><FormattedMessage id='antennas.exclude_keywords' defaultMessage='Excluded keywords (one per line)' /></h4>
            <textarea className='setting-text' rows={3} value={excludeKeywords} onChange={e => { setExcludeKeywords(e.target.value); }} onBlur={handleSave} />
          </section>

          <ChipList
            label={<FormattedMessage id='antennas.domains' defaultMessage='Domains' />}
            items={toArray(antenna.get('domains'))}
            onAdd={domain => dispatch(addAntennaDomains(id, [domain]))}
            onRemove={domain => dispatch(removeAntennaDomains(id, [domain]))}
            placeholder='example.com'
          >
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('any_domains')} onChange={handleToggle('any_domains')} /> <FormattedMessage id='antennas.any_domains' defaultMessage='Match any domain' /></label>
          </ChipList>

          <ChipList
            label={<FormattedMessage id='antennas.exclude_domains' defaultMessage='Excluded domains' />}
            items={toArray(antenna.get('exclude_domains'))}
            onAdd={domain => dispatch(addAntennaDomains(id, [domain], true))}
            onRemove={domain => dispatch(removeAntennaDomains(id, [domain], true))}
            placeholder='example.com'
          />

          <ChipList
            label={<FormattedMessage id='antennas.tags' defaultMessage='Hashtags' />}
            items={toArray(antenna.get('tags'))}
            onAdd={tag => dispatch(addAntennaTags(id, [tag]))}
            onRemove={tag => dispatch(removeAntennaTags(id, [tag]))}
            placeholder='#art'
          >
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('any_tags')} onChange={handleToggle('any_tags')} /> <FormattedMessage id='antennas.any_tags' defaultMessage='Match any hashtag' /></label>
          </ChipList>

          <ChipList
            label={<FormattedMessage id='antennas.exclude_tags' defaultMessage='Excluded hashtags' />}
            items={toArray(antenna.get('exclude_tags'))}
            onAdd={tag => dispatch(addAntennaTags(id, [tag], true))}
            onRemove={tag => dispatch(removeAntennaTags(id, [tag], true))}
            placeholder='#spoiler'
          />

          <ChipList
            label={<FormattedMessage id='antennas.accounts' defaultMessage='Accounts' />}
            items={toArray(antenna.get('accounts'))}
            onAdd={handleAddAccount(false)}
            onRemove={accountId => dispatch(removeAntennaAccount(id, accountId))}
            placeholder='@user@example.com'
          >
            <label className='antenna-editor__check'><input type='checkbox' checked={bool('any_accounts')} onChange={handleToggle('any_accounts')} /> <FormattedMessage id='antennas.any_accounts' defaultMessage='Match any account' /></label>
          </ChipList>

          <ChipList
            label={<FormattedMessage id='antennas.exclude_accounts' defaultMessage='Excluded accounts' />}
            items={toArray(antenna.get('exclude_accounts'))}
            onAdd={handleAddAccount(true)}
            onRemove={accountId => dispatch(removeAntennaAccount(id, accountId, true))}
            placeholder='@user@example.com'
          />
        </div>
      </div>

      <Helmet>
        <title>{antenna.get('title')}</title>
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
