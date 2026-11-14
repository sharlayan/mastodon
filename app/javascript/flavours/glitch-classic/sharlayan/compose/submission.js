export const getSharlayanComposeSubmission = ({ getState, effectiveStatusId, overridePrivacy }) => {
  const privacy = overridePrivacy || getState().getIn(['compose', 'privacy']);
  const limitedScope = privacy !== 'direct' && effectiveStatusId === null && getState().getIn(['compose', 'limited_scope']) === 'reply' ? 'reply' : undefined;
  const circleId = !limitedScope && !overridePrivacy && privacy !== 'direct' && effectiveStatusId === null ? getState().getIn(['compose', 'circle_id']) : null;
  const replyAccountIds = getState().getIn(['compose', 'limited_reply_account_ids']);
  const visibility = circleId || limitedScope ? 'private' : privacy;
  const rawPoll = getState().getIn(['compose', 'poll'], null);
  const options = rawPoll?.get('options');
  const poll = rawPoll ? {
    options: options ? options.map(option => (option && typeof option === 'string' ? option.trim() : String(option).trim())).filter(Boolean).toArray() : [],
    expires_in: rawPoll.get('expires_in'),
    multiple: rawPoll.get('multiple'),
    hide_totals: rawPoll.get('hide_totals'),
  } : null;

  return {
    circleId,
    limitedScope,
    limitedReplyAccountIds: limitedScope ? replyAccountIds?.toArray() : undefined,
    visibility,
    clipIds: effectiveStatusId === null ? getState().getIn(['compose', 'clip_ids']).toArray() : undefined,
    poll,
    quoteApprovalPolicy: ['private', 'direct', 'circle'].includes(visibility) ? 'nobody' : getState().getIn(['compose', 'quote_policy']),
    scheduledAt: effectiveStatusId === null ? getState().getIn(['compose', 'scheduled_at']) : undefined,
    reactionAcceptance: getState().getIn(['compose', 'reaction_acceptance']),
  };
};
