import mastodonIcon from '../../../images/logo-symbol-icon.svg';

// Source: https://codeberg.org/catodon/catodon
import catodonIcon from 'flavours/glitch/images/software/catodon.svg';
// Source: https://github.com/kokonect-link/cherrypick
import cherrypickIcon from 'flavours/glitch/images/software/cherrypick.svg';
// Source: https://commons.wikimedia.org/wiki/File:Fediverse_logo_proposal.svg
import fediverseIcon from 'flavours/glitch/images/software/fediverse.svg';
// Source: https://github.com/fedify-dev/fedify
import fedifyIcon from 'flavours/glitch/images/software/fedify.svg';
// Source: https://akkoma.dev/FoundKeyGang/FoundKey
import foundkeyIcon from 'flavours/glitch/images/software/foundkey.svg';
// Source: https://github.com/hackers-pub/hackerspub
import hackersPubIcon from 'flavours/glitch/images/software/hackerspub.svg';
// Source: https://github.com/fedify-dev/hollo
import holloIcon from 'flavours/glitch/images/software/hollo.svg';
// Source: https://iceshrimp.dev/iceshrimp/iceshrimp
import iceshrimpIcon from 'flavours/glitch/images/software/iceshrimp.svg';
// Source: https://github.com/misskey-dev/misskey
import misskeyIcon from 'flavours/glitch/images/software/misskey.svg';
// Source: https://github.com/Chocobozzz/PeerTube
import peertubeIcon from 'flavours/glitch/images/software/peertube.svg';
// Source: https://github.com/pixelfed/pixelfed
import pixelfedIcon from 'flavours/glitch/images/software/pixelfed.svg';
// Source: https://git.pleroma.social/pleroma/pleroma
import pleromaIcon from 'flavours/glitch/images/software/pleroma.svg';
// Source: https://activitypub.software/TransFem-org/Sharkey
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
