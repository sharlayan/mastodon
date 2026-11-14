import { connect } from 'react-redux';

import { authorizeFollowRequest, rejectFollowRequest } from 'flavours/glitch-classic/actions/accounts';
import { makeGetAccount } from 'flavours/glitch-classic/selectors';

import FollowRequest from '../components/follow_request';

const makeMapStateToProps = () => {
  const getAccount = makeGetAccount();

  const mapStateToProps = (state, props) => ({
    account: getAccount(state, props.id),
  });

  return mapStateToProps;
};

const mapDispatchToProps = (dispatch, { id }) => ({
  onAuthorize () {
    dispatch(authorizeFollowRequest(id));
  },

  onReject () {
    dispatch(rejectFollowRequest(id));
  },
});

export default connect(makeMapStateToProps, mapDispatchToProps)(FollowRequest);
