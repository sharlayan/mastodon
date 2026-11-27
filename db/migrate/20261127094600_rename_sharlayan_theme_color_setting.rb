# frozen_string_literal: true

class RenameSharlayanThemeColorSetting < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute("DELETE FROM settings WHERE var = 'branding_theme_color' AND EXISTS (SELECT 1 FROM settings AS previous WHERE previous.var = 'theme_color' AND previous.value ~ '#[0-9a-fA-F]{3}')")
      execute("UPDATE settings SET var = 'branding_theme_color' WHERE var = 'theme_color' AND value ~ '#[0-9a-fA-F]{3}'")
    end
  end

  def down
    safety_assured do
      execute("DELETE FROM settings WHERE var = 'theme_color' AND EXISTS (SELECT 1 FROM settings AS renamed WHERE renamed.var = 'branding_theme_color')")
      execute("UPDATE settings SET var = 'theme_color' WHERE var = 'branding_theme_color'")
    end
  end
end
