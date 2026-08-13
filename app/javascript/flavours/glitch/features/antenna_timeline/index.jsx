import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { Link, withRouter } from 'react-router-dom';

import ImmutablePropTypes from 'react-immutable-proptypes';
import { connect } from 'react-redux';

import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import { fetchAntenna, deleteAntenna } from 'flavours/glitch/actions/antennas';
import { openModal } from 'flavours/glitch/actions/modal';
import { addColumn, removeColumn, moveColumn } from 'flavours/glitch/actions/columns';
import { connectAntennaStream } from 'flavours/glitch/actions/streaming';
import { expandAntennaTimeline } from 'flavours/glitch/actions/timelines';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { Icon }  from 'flavours/glitch/components/icon';
import { injectIntl } from 'flavours/glitch/components/intl';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import BundleColumnError from 'flavours/glitch/features/ui/components/bundle_column_error';
import StatusListContainer from 'flavours/glitch/features/ui/containers/status_list_container';
import { WithRouterPropTypes } from 'flavours/glitch/utils/react_router';

const messages = defineMessages({
  deleteConfirm: { id: 'confirmations.delete_antenna.confirm', defaultMessage: 'Delete' },
  deleteMessage: { id: 'confirmations.delete_antenna.message', defaultMessage: 'This permanently deletes the antenna and its collected posts. The posts themselves will not be deleted.' },
  deleteTitle: { id: 'confirmations.delete_antenna.title', defaultMessage: 'Delete “{name}”?' },
});

const mapStateToProps = (state, props) => ({
  antenna: state.getIn(['antennas', props.params.id]),
  hasUnread: state.getIn(['timelines', `antenna:${props.params.id}`, 'unread']) > 0,
});

class AntennaTimeline extends PureComponent {

  static propTypes = {
    params: PropTypes.object.isRequired,
    dispatch: PropTypes.func.isRequired,
    columnId: PropTypes.string,
    hasUnread: PropTypes.bool,
    multiColumn: PropTypes.bool,
    antenna: PropTypes.oneOfType([ImmutablePropTypes.map, PropTypes.bool]),
    intl: PropTypes.object.isRequired,
    ...WithRouterPropTypes,
  };

  handlePin = () => {
    const { columnId, dispatch } = this.props;

    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('ANTENNA', { id: this.props.params.id }));
      this.props.history.push('/');
    }
  };

  handleMove = (dir) => {
    const { columnId, dispatch } = this.props;
    dispatch(moveColumn(columnId, dir));
  };

  componentDidMount () {
    const { dispatch } = this.props;
    const { id } = this.props.params;

    dispatch(fetchAntenna(id));
    dispatch(expandAntennaTimeline(id));

    this.disconnect = dispatch(connectAntennaStream(id));
  }

  componentDidUpdate (prevProps) {
    const { dispatch, params: { id } } = this.props;

    if (id !== prevProps.params.id) {
      if (this.disconnect) {
        this.disconnect();
        this.disconnect = null;
      }

      dispatch(fetchAntenna(id));
      dispatch(expandAntennaTimeline(id));

      this.disconnect = dispatch(connectAntennaStream(id));
    }
  }

  componentWillUnmount () {
    if (this.disconnect) {
      this.disconnect();
      this.disconnect = null;
    }
  }

  handleLoadMore = maxId => {
    const { id } = this.props.params;
    this.props.dispatch(expandAntennaTimeline(id, { maxId }));
  };

  handleDeleteClick = () => {
    const { antenna, columnId, dispatch, history, intl } = this.props;
    const { id } = this.props.params;
    const title = antenna ? antenna.get('title') : id;

    dispatch(openModal({
      modalType: 'CONFIRM',
      modalProps: {
        title: intl.formatMessage(messages.deleteTitle, { name: title }),
        message: intl.formatMessage(messages.deleteMessage),
        confirm: intl.formatMessage(messages.deleteConfirm),
        onConfirm: () => {
          dispatch(deleteAntenna(id));

          if (columnId) {
            dispatch(removeColumn(columnId));
          } else {
            history.push('/antennas');
          }
        },
      },
    }));
  };

  render () {
    const { hasUnread, columnId, multiColumn, antenna } = this.props;
    const { id } = this.props.params;
    const pinned = !!columnId;
    const title  = antenna ? antenna.get('title') : id;

    if (typeof antenna === 'undefined') {
      return (
        <Column>
          <div className='scrollable'>
            <LoadingIndicator />
          </div>
        </Column>
      );
    } else if (antenna === false) {
      return (
        <BundleColumnError multiColumn={multiColumn} errorType='routing' />
      );
    }

    return (
      <Column bindToDocument={!multiColumn} label={title}>
        <ColumnHeader
          icon='radar'
          iconComponent={RadarIcon}
          active={hasUnread}
          title={title}
          onPin={this.handlePin}
          onMove={this.handleMove}
          scrollTopOnClick
          pinned={pinned}
          multiColumn={multiColumn}
        >
          <div className='column-settings'>
            <section className='column-header__links'>
              <Link to={`/antennas/${id}/edit`} className='text-btn column-header__setting-btn'>
                <Icon id='pencil' icon={EditIcon} /> <FormattedMessage id='antennas.edit' defaultMessage='Edit antenna' />
              </Link>

              <button type='button' className='text-btn column-header__setting-btn' tabIndex={0} onClick={this.handleDeleteClick}>
                <Icon id='trash' icon={DeleteIcon} /> <FormattedMessage id='antennas.delete' defaultMessage='Delete antenna' />
              </button>
            </section>
          </div>
        </ColumnHeader>

        <StatusListContainer
          trackScroll={!pinned}
          scrollKey={`antenna_timeline-${columnId}`}
          timelineId={`antenna:${id}`}
          onLoadMore={this.handleLoadMore}
          emptyMessage={<FormattedMessage id='empty_column.antenna' defaultMessage='There is nothing in this antenna yet. When matching statuses are posted, they will appear here.' />}
          bindToDocument={!multiColumn}
        />

        <Helmet>
          <title>{title}</title>
          <meta name='robots' content='noindex' />
        </Helmet>
      </Column>
    );
  }

}

export default withRouter(injectIntl(connect(mapStateToProps)(AntennaTimeline)));
