import { getOverflowHighlightText } from '../overflow_highlight';

describe('compose overflow highlight', () => {
  it('splits text at the first character beyond the compose limit', () => {
    expect(getOverflowHighlightText('safeoverflow', 4)).toEqual({
      before: 'safe',
      overflow: 'overflow',
    });
  });

  it('stays out of the upstream textarea when there is no overflow', () => {
    expect(getOverflowHighlightText('safe', -1)).toBeNull();
    expect(getOverflowHighlightText('safe', 4)).toBeNull();
  });
});
