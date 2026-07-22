import { describe, expect, it } from 'vitest';

import pixelfedIconSource from 'flavours/glitch/images/software/pixelfed.svg?raw';

import { softwareIconFor } from '../software_icon';

describe('softwareIconFor', () => {
  it('uses repository-sourced icons for included software', () => {
    expect(softwareIconFor('Mastodon')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Misskey')).not.toBe(softwareIconFor());
    expect(softwareIconFor('FoundKey')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Catodon')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Sharkey')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Iceshrimp')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Iceshrimp.NET')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Iceshrimp.NET')).toBe(softwareIconFor('Iceshrimp'));
    expect(softwareIconFor('CherryPick')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Hollo')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Fedify')).not.toBe(softwareIconFor());
    expect(softwareIconFor('HackersPub')).not.toBe(softwareIconFor());
    expect(softwareIconFor('Pleroma')).not.toBe(softwareIconFor());
    expect(softwareIconFor('PeerTube')).not.toBe(softwareIconFor());
    expect(softwareIconFor('PeerTube')).toContain("width='34'%20height='34'");
    expect(softwareIconFor('Pixelfed')).not.toBe(softwareIconFor());
    expect(pixelfedIconSource).toContain('viewBox="0 0 50 50"');
  });

  it('uses the Fediverse icon for unknown or missing software', () => {
    expect(softwareIconFor('unknown')).toBe(softwareIconFor());
    expect(softwareIconFor('glitchsoc')).toBe(softwareIconFor());
    expect(softwareIconFor('Firefish')).toBe(softwareIconFor());
  });
});
