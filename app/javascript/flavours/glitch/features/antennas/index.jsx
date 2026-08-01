import PropTypes from 'prop-types';
import { useEffect, useCallback, useState } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import ImmutablePropTypes from 'react-immutable-proptypes';
import { useDispatch, useSelector } from 'react-redux';

import AddIcon from '@/material-icons/400-24px/add.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import { fetchAntennas, createAntenna, deleteAntenna } from 'flavours/glitch/actions/antennas';
import { openModal } from 'flavours/glitch/actions/modal';
import Column from 'flavours/glitch/components/column';
import ColumnHeader from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';

const messages = defineMessages({
  heading: { id: 'column.antennas', defaultMessage: 'Antennas' },
  create: { id: 'antennas.create_antenna', defaultMessage: 'Create antenna' },
  edit: { id: 'antennas.edit', defaultMessage: 'Edit antenna' },
  delete: { id: 'antennas.delete', defaultMessage: 'Delete antenna' },
  deleteConfirm: { id: 'confirmations.delete_antenna.confirm', defaultMessage: 'Delete' },
  deleteMessage: { id: 'confirmations.delete_antenna.message', defaultMessage: 'This permanently deletes the antenna and its collected posts. The posts themselves will not be deleted.' },
  deleteTitle: { id: 'confirmations.delete_antenna.title', defaultMessage: 'Delete “{name}”?' },
  title: { id: 'antennas.new.title_placeholder', defaultMessage: 'New antenna title' },
});

const AntennaItem = ({ id, title }) => {
  const dispatch = useDispatch();
  const intl = useIntl();

  const handleDeleteClick = useCallback(() => {
    dispatch(openModal({
      modalType: 'CONFIRM',
      modalProps: {
        title: intl.formatMessage(messages.deleteTitle, { name: title }),
        message: intl.formatMessage(messages.deleteMessage),
        confirm: intl.formatMessage(messages.deleteConfirm),
        onConfirm: () => dispatch(deleteAntenna(id)),
      },
    }));
  }, [dispatch, id, intl, title]);

  return (
    <div className='lists__item'>
      <Link to={`/antennas/${id}`} className='lists__item__title'>
        <Icon id='radar' icon={RadarIcon} />
        <span>{title}</span>
      </Link>

      <Link to={`/antennas/${id}/edit`} className='text-btn column-header__setting-btn' aria-label={intl.formatMessage(messages.edit)}>
        <Icon id='pencil' icon={EditIcon} style={{ width: '24px', height: '24px' }} />
      </Link>

      <button type='button' className='text-btn column-header__setting-btn' onClick={handleDeleteClick} aria-label={intl.formatMessage(messages.delete)}>
        <Icon id='trash' icon={DeleteIcon} style={{ width: '24px', height: '24px' }} />
      </button>
    </div>
  );
};

AntennaItem.propTypes = {
  id: PropTypes.string.isRequired,
  title: PropTypes.string.isRequired,
};

const Antennas = ({ multiColumn }) => {
  const dispatch = useDispatch();
  const intl = useIntl();
  const antennas = useSelector(state => state.get('antennas').filter(item => !!item).toList());
  const [title, setTitle] = useState('');
  const [created, setCreated] = useState(null);

  useEffect(() => {
    dispatch(fetchAntennas());
  }, [dispatch]);

  const handleSubmit = useCallback(e => {
    e.preventDefault();

    if (title.trim().length === 0) {
      return;
    }

    dispatch(createAntenna({ title: title.trim() })).then(antenna => {
      setCreated(antenna);
    }).catch(() => {});
    setTitle('');
  }, [dispatch, title]);

  const emptyMessage = (
    <FormattedMessage id='antennas.no_antennas_yet' defaultMessage='No antennas yet.' />
  );

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.heading)}>
      <ColumnHeader
        title={intl.formatMessage(messages.heading)}
        icon='radar'
        iconComponent={RadarIcon}
        multiColumn={multiColumn}
      />

      <section className='antenna-new'>
        <form className='antenna-new__form' onSubmit={handleSubmit}>
          <input
            className='setting-text'
            value={title}
            onChange={e => { setTitle(e.target.value); }}
            placeholder={intl.formatMessage(messages.title)}
          />

          <button type='submit' className='button' aria-label={intl.formatMessage(messages.create)}>
            <Icon id='plus' icon={AddIcon} />
          </button>
        </form>

        {created && (
          <div className='antenna-new__hint'>
            <FormattedMessage
              id='antennas.created_hint'
              defaultMessage='Created antenna “{name}”. An antenna with no conditions does not collect anything — {link}.'
              values={{
                name: created.title,
                link: (
                  <Link to={`/antennas/${created.id}/edit`}>
                    <FormattedMessage id='antennas.created_hint_link' defaultMessage='click here to edit your new antenna' />
                  </Link>
                ),
              }}
            />
          </div>
        )}
      </section>

      <ScrollableList
        scrollKey='antennas'
        emptyMessage={emptyMessage}
        bindToDocument={!multiColumn}
      >
        {antennas.map(antenna => (
          <AntennaItem key={antenna.get('id')} id={antenna.get('id')} title={antenna.get('title')} />
        ))}
      </ScrollableList>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

Antennas.propTypes = {
  multiColumn: PropTypes.bool,
};

export default Antennas;
