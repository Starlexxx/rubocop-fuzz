# frozen_string_literal: true

require_relative '../lib/rubocop_fuzz'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
