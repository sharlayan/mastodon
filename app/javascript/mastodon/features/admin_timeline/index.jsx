import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import { connect } from 'react-redux';

import ManufacturingIcon from '@/material-icons/400-24px/manufacturing.svg?react';
import { injectIntl } from '@/mastodon/components/intl';

import { addColumn, removeColumn, moveColumn } from '../../actions/columns';
import { adminTimelineId, expandAdminTimeline } from './actions';
import Column from '../../components/column';
import ColumnHeader from '../../components/column_header';
import StatusListContainer from '../ui/containers/status_list_container';

import ColumnSettingsContainer from './containers/column_settings_container';

const messages = defineMessages({
  title: { id: 'column.admin_timeline', defaultMessage: 'Management timeline' },
});

const mapStateToProps = (state, { columnId }) => {
  const uuid = columnId;
  const columns = state.getIn(['settings', 'columns']);
  const index = columns.findIndex(c => c.get('uuid') === uuid);
  const getOther = key => (columnId && index >= 0) ? columns.get(index).getIn(['params', 'other', key]) : state.getIn(['settings', 'admin', 'other', key]);

  const filters = {
    hidePublic: !!getOther('hidePublic'),
    hideUnlisted: !!getOther('hideUnlisted'),
    hidePrivate: !!getOther('hidePrivate'),
    groupDirect: !!getOther('groupDirect'),
  };

  const timelineState = state.getIn(['timelines', adminTimelineId(filters)]);

  return {
    hasUnread: !!timelineState && timelineState.get('unread') > 0,
    columnId: uuid,
    ...filters,
  };
};

class AdminTimeline extends PureComponent {
  static propTypes = {
    dispatch: PropTypes.func.isRequired,
    columnId: PropTypes.string,
    intl: PropTypes.object.isRequired,
    hasUnread: PropTypes.bool,
    multiColumn: PropTypes.bool,
    hidePublic: PropTypes.bool,
    hideUnlisted: PropTypes.bool,
    hidePrivate: PropTypes.bool,
    groupDirect: PropTypes.bool,
  };

  filters = () => {
    const { hidePublic, hideUnlisted, hidePrivate, groupDirect } = this.props;
    return { hidePublic, hideUnlisted, hidePrivate, groupDirect };
  };

  handlePin = () => {
    const { columnId, dispatch } = this.props;

    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('ADMIN_TIMELINE', { other: this.filters() }));
    }
  };

  handleMove = (dir) => {
    const { columnId, dispatch } = this.props;
    dispatch(moveColumn(columnId, dir));
  };

  handleHeaderClick = () => {
    this.column.scrollTop();
  };

  componentDidMount () {
    const { dispatch } = this.props;
    dispatch(expandAdminTimeline(this.filters()));
  }

  componentDidUpdate (prevProps) {
    const { dispatch, hidePublic, hideUnlisted, hidePrivate, groupDirect } = this.props;

    if (prevProps.hidePublic !== hidePublic || prevProps.hideUnlisted !== hideUnlisted || prevProps.hidePrivate !== hidePrivate || prevProps.groupDirect !== groupDirect) {
      dispatch(expandAdminTimeline(this.filters()));
    }
  }

  setRef = c => {
    this.column = c;
  };

  handleLoadMore = maxId => {
    const { dispatch } = this.props;
    dispatch(expandAdminTimeline({ maxId, ...this.filters() }));
  };

  render () {
    const { intl, hasUnread, columnId, multiColumn } = this.props;
    const pinned = !!columnId;

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label={intl.formatMessage(messages.title)}>
        <ColumnHeader
          icon='manufacturing'
          iconComponent={ManufacturingIcon}
          active={hasUnread}
          title={intl.formatMessage(messages.title)}
          onPin={this.handlePin}
          onMove={this.handleMove}
          onClick={this.handleHeaderClick}
          pinned={pinned}
          multiColumn={multiColumn}
        >
          <ColumnSettingsContainer columnId={columnId} />
        </ColumnHeader>

        <StatusListContainer
          trackScroll={!pinned}
          scrollKey={`admin_timeline-${columnId}`}
          timelineId={adminTimelineId(this.filters())}
          onLoadMore={this.handleLoadMore}
          emptyMessage={<FormattedMessage id='empty_column.admin_timeline' defaultMessage='There are no posts here yet.' />}
          bindToDocument={!multiColumn}
        />

        <Helmet>
          <title>{intl.formatMessage(messages.title)}</title>
          <meta name='robots' content='noindex' />
        </Helmet>
      </Column>
    );
  }
}

export default connect(mapStateToProps)(injectIntl(AdminTimeline));
