import type { AnyStatusShape } from '@/flavours/glitch-classic/models/status';

export function statusLink({
  account,
  id,
}: Pick<AnyStatusShape, 'account' | 'id'>) {
  return `/@${typeof account === 'string' ? account : account.acct}/${id}`;
}
