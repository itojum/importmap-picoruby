require_relative "../lib/picoruby_importmap"
require_relative "support/simple_url"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
