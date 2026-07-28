'use strict';

const REPLACEMENT = '⬛';
const TEXT_KEYS = new Set(['content', 'text', 'cw', 'spoiler_text', 'display_name', 'note', 'title', 'value', 'name']);

const parseIdentity = (value, domain = '') => {
  const token = String(value ?? '').replace(/^:/, '').replace(/:$/, '');
  const separator = token.indexOf('@');

  if (separator === -1) {
    return { shortcode: token, domain: String(domain ?? '').toLowerCase() };
  }

  const embeddedDomain = token.slice(separator + 1);
  return {
    shortcode: token.slice(0, separator),
    domain: embeddedDomain === '.' ? '' : embeddedDomain.toLowerCase(),
  };
};

const isMuted = (identity, rules) => {
  const shortcode = identity.shortcode.toLowerCase();
  return rules.some((rule) => {
    const prefix = String(rule.prefix ?? '').trim().toLowerCase();
    const domain = String(rule.domain ?? '').trim().toLowerCase();
    return prefix.length > 0 && (!domain || domain === identity.domain) && shortcode.startsWith(prefix);
  });
};

const isCustomReaction = (name) => typeof name === 'string' && name.startsWith(':') && name.endsWith(':');

const mutedReactionNotification = (value, rules) => (
  value?.type === 'reaction' &&
  value.reaction?.url &&
  isMuted(parseIdentity(value.reaction.name, value.reaction.domain), rules)
);

const mutedNoteUpdate = (type, body, rules) => (
  type === 'noteUpdated' &&
  isCustomReaction(body?.body?.reaction) &&
  isMuted(parseIdentity(body.body.reaction), rules)
);

const filterPayload = (payload, rules) => {
  if (!payload || !Array.isArray(rules) || rules.length === 0) return payload;

  const visit = (value, inheritedIdentities = []) => {
    if (Array.isArray(value)) {
      for (let index = value.length - 1; index >= 0; index--) {
        if (mutedReactionNotification(value[index], rules)) value.splice(index, 1);
      }
      value.forEach((item) => visit(item, inheritedIdentities));
      return;
    }
    if (!value || typeof value !== 'object') return;

    const identities = inheritedIdentities.slice();
    if (Array.isArray(value.emojis)) {
      value.emojis = value.emojis.filter((emoji) => {
        if (!emoji || typeof emoji !== 'object') return true;
        const identity = parseIdentity(emoji.shortcode, emoji.domain);
        if (!isMuted(identity, rules)) return true;
        identities.push(identity);
        return false;
      });
    } else if (value.emojis && typeof value.emojis === 'object') {
      for (const name of Object.keys(value.emojis)) {
        const identity = parseIdentity(name);
        if (isMuted(identity, rules)) {
          identities.push(identity);
          delete value.emojis[name];
        }
      }
    }

    if (Array.isArray(value.reactions)) {
      value.reactions = value.reactions.filter((reaction) => {
        if (!reaction?.url) return true;
        return !isMuted(parseIdentity(reaction.name, reaction.domain), rules);
      });
    } else if (value.reactions && typeof value.reactions === 'object') {
      for (const name of Object.keys(value.reactions)) {
        if (isCustomReaction(name) && isMuted(parseIdentity(name), rules)) delete value.reactions[name];
      }
      if (value.reactionEmojis && typeof value.reactionEmojis === 'object') {
        for (const name of Object.keys(value.reactionEmojis)) {
          if (isMuted(parseIdentity(name), rules)) delete value.reactionEmojis[name];
        }
      }
      if (isCustomReaction(value.myReaction) && isMuted(parseIdentity(value.myReaction), rules)) value.myReaction = null;
    }

    for (const [key, child] of Object.entries(value)) {
      if (TEXT_KEYS.has(key) && typeof child === 'string') {
        for (const identity of identities) {
          const escaped = identity.shortcode.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          value[key] = value[key].replace(new RegExp(`:${escaped}:`, 'gi'), REPLACEMENT);
        }
      }
    }

    Object.values(value).forEach((child) => visit(child, identities));
  };

  visit(payload);
  return payload;
};

export { filterPayload, isMuted, mutedNoteUpdate, mutedReactionNotification, parseIdentity };
