import mastodonIcon from '../../../images/logo-symbol-icon.svg';

import catodonIcon from 'flavours/glitch/images/software/catodon.svg';
import cherrypickIcon from 'flavours/glitch/images/software/cherrypick.svg';
import fediverseIcon from 'flavours/glitch/images/software/fediverse.svg';
import fedifyIcon from 'flavours/glitch/images/software/fedify.svg';
import foundkeyIcon from 'flavours/glitch/images/software/foundkey.svg';
import hackersPubIcon from 'flavours/glitch/images/software/hackerspub.svg';
import holloIcon from 'flavours/glitch/images/software/hollo.svg';
import iceshrimpIcon from 'flavours/glitch/images/software/iceshrimp.svg';
import misskeyIcon from 'flavours/glitch/images/software/misskey.svg';
import peertubeIcon from 'flavours/glitch/images/software/peertube.svg';
import pixelfedIcon from 'flavours/glitch/images/software/pixelfed.svg';
import pleromaIcon from 'flavours/glitch/images/software/pleroma.svg';
import sharkeyIcon from 'flavours/glitch/images/software/sharkey.svg';

const SOFTWARE_ICONS = {
  mastodon: mastodonIcon,
  misskey: misskeyIcon,
  foundkey: foundkeyIcon,
  catodon: catodonIcon,
  sharkey: sharkeyIcon,
  iceshrimp: iceshrimpIcon,
  'iceshrimp.net': iceshrimpIcon,
  cherrypick: cherrypickIcon,
  pleroma: pleromaIcon,
  peertube: peertubeIcon,
  pixelfed: pixelfedIcon,
  fedify: fedifyIcon,
  hollo: holloIcon,
  hackerspub: hackersPubIcon,
};

export const softwareIconFor = software =>
  SOFTWARE_ICONS[software?.toLowerCase()] ?? fediverseIcon;
