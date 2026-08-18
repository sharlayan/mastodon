import { updateStatusReaction } from 'flavours/glitch/actions/statuses';

export const handleSharlayanStreamingEvent = ({
  data,
  dispatch,
  updateReaction = updateStatusReaction,
}) => {
  if (data.event === 'status.reaction') {
    dispatch(updateReaction(JSON.parse(data.payload)));
    return true;
  }

  return false;
};
