# frozen_string_literal: true

namespace :multi_accounts do
  desc 'Run database migration for multi-account switching'
  task setup: :environment do
    puts 'Multi-account switching is enabled by default.'
    puts 'No additional configuration is required.'
    puts ''
    puts 'Run `rails db:migrate` if you have not already done so.'
  end
end
