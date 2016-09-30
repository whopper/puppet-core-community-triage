# spec/spec_helper.rb
require 'bundler/setup'
Bundler.setup
Bundler.require(:spec)

require 'simplecov'
SimpleCov.start

require 'vcr'
require 'webmock/rspec'
require 'stub_env'

VCR.configure do |c|
  c.cassette_library_dir = 'fixtures/.cassettes'
  c.hook_into :webmock
  c.default_cassette_options = { :record => :new_episodes }
  c.configure_rspec_metadata!
  c.filter_sensitive_data('MEMBER_TOKEN') { ENV['MEMBER_TOKEN'] }
end

require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

require_relative '../application'

module RSpecMixin
  include Rack::Test::Methods
  def app() Sinatra::Application end
end


# For RSpec 2.x and 3.x
RSpec.configure { |c|
  c.include RSpecMixin
  c.include StubEnv::Helpers
}
