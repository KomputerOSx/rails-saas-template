ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each parallel worker gets its own test database - load the reference-data seeds
    # (system_admin, owner/admin/user roles and their permissions) into each one, once,
    # outside any per-test transaction, so tests exercise the real seeded permission
    # catalog instead of ad-hoc reimplementations of it. Below the parallelization
    # threshold Rails runs single-process and parallelize_setup never fires, so seed
    # loading also happens unconditionally right here.
    parallelize_setup do |_worker|
      Rails.application.load_seed
    end
    Rails.application.load_seed

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rails.cache is a real (in-memory) store in test (see config/environments/test.rb)
    # so cache-backed state - PendingRegistration, Rack::Attack's throttle counters -
    # persists across requests within a test. Without this, repeated login/signup
    # attempts across different test cases in the same worker would accumulate and
    # trip rate limits that have nothing to do with the test being run.
    setup { Rails.cache.clear }

    # Add more helper methods to be used by all tests here...
  end
end
