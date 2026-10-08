ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)
Report.check_cars_exist = false

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    def load_reference_data = Curb::ReferenceData.load!

    # Calculator inputs for a US car, with anything overridable.
    def build_inputs(**overrides)
      TrueCost::Inputs.new(**{
        market: Market.fetch("US"), make_key: "FORD", model_key: "FOCUS", engine_key: nil, model_year: 2020,
        first_used_on: Date.new(2020, 1, 1), as_of: Date.new(2023, 1, 1), mileage: 36_000, price: 10_000,
        years: 3, miles_per_year: 12_000, labor_rate: 100.0, addon_warranty: "none", addon_years: nil,
        addon_miles: nil, addon_coverage: nil, emergency_savings: nil, monthly_budget: nil, recall_category_ids: []
      }.merge(overrides))
    end
  end
end

class ActionDispatch::IntegrationTest
  def sign_in_as(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: }
  end
end

# Runs the block as if the Claude API key were `key` (nil for none), whatever this machine has set.
module Claude
  def self.stub_key(key)
    original = method(:api_key)
    define_singleton_method(:api_key) { key }
    yield
  ensure
    define_singleton_method(:api_key, original)
  end
end

# Runs the block with plans and payments switched on (or off), as if an admin had flipped the switch. The switch is a
# database row, so the test's transaction undoes it.
module BillingSwitch
  def with_billing(on = true)
    Feature.set!(:billing, on)
    yield
  ensure
    Current.feature_states = nil
  end
end
ActiveSupport::TestCase.include BillingSwitch
ActionDispatch::IntegrationTest.include BillingSwitch
