# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BrandingHelper do
  describe '#branding_logo_styles' do
    def upload_with_url(url)
      instance_double(SiteUpload, file: instance_double(Paperclip::Attachment, url: url))
    end

    it 'uses the custom icon for symbol and CSS logos' do
      presenter = instance_double(InstancePresenter, logo_icon: upload_with_url('/system/site_uploads/logo_icon/icon.png'), logo_wordmark_dark: nil, logo_wordmark_light: nil)
      allow(helper).to receive(:instance_presenter).and_return(presenter)

      expect(helper.branding_logo_styles).to include('--branding-logo-icon:url(/system/site_uploads/logo_icon/icon.png)', '--logo:url')
    end

    it 'switches full logos by color scheme' do
      presenter = instance_double(
        InstancePresenter,
        logo_icon: nil,
        logo_wordmark_dark: upload_with_url('/system/site_uploads/logo_wordmark_dark/dark.png'),
        logo_wordmark_light: upload_with_url('/system/site_uploads/logo_wordmark_light/light.png')
      )
      allow(helper).to receive(:instance_presenter).and_return(presenter)

      styles = helper.branding_logo_styles

      expect(styles).to include('html{--branding-logo-wordmark:url(/system/site_uploads/logo_wordmark_dark/dark.png)}')
      expect(styles).to include('html[data-color-scheme=light]{--branding-logo-wordmark:url(/system/site_uploads/logo_wordmark_light/light.png)}')
      expect(styles).to include('@media(prefers-color-scheme:light)')
    end

    it 'uses the available full logo for both color schemes' do
      presenter = instance_double(InstancePresenter, logo_icon: nil, logo_wordmark_dark: upload_with_url('/dark.png'), logo_wordmark_light: nil)
      allow(helper).to receive(:instance_presenter).and_return(presenter)

      expect(helper.branding_logo_styles.scan('url(/dark.png)').size).to eq(3)
    end
  end
end
