require_relative "../lib/importmap_picoruby"
require_relative "support/simple_url"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
