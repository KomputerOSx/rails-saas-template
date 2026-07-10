require "test_helper"

class AdminPriceMigrationsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "a non-system user cannot reach the price migration page" do
    member = users(:two)
    post login_path, params: { email: member.email, password: "password123" }

    get new_admin_price_migration_path
    assert_response :redirect
  end

  test "previewing shows eligible and grandfathered organizations separately" do
    eligible = Organization.create_personal_for!(users(:two))
    grandfathered_owner = User.create!(email: "grandfathered@example.com", password: "Xk92!vTqZmR7", confirmed_at: Time.current)
    grandfathered = Organization.create_personal_for!(grandfathered_owner)
    grandfathered.grandfather!

    with_active_subscription(eligible, Billing::Plans::STARTER) do
      with_active_subscription(grandfathered, Billing::Plans::STARTER) do
        with_resolvable_price(Billing::Plans::STARTER) do
          get new_admin_price_migration_path(plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd")
        end
      end
    end

    assert_response :success
    assert_match eligible.name, response.body
    assert_match grandfathered.name, response.body
    assert_match "Migrate 1 organization", response.body
  end

  test "create enqueues the migration job and logs an audit event" do
    assert_enqueued_with(job: Billing::MigratePriceJob) do
      with_resolvable_price(Billing::Plans::STARTER) do
        post admin_price_migrations_path, params: { plan_key: "starter", currency: "usd", old_price_id: "price_old_starter_usd" }
      end
    end

    assert_redirected_to new_admin_price_migration_path(plan_key: "starter", currency: "usd")
    assert AuditLog.exists?(event_type: :price_migration_started)
  end

  test "create refuses when Billing::Plans doesn't resolve a different price" do
    # Credentials may carry real Stripe price ids in some environments - pin the resolved
    # "new" price to the same id as old so the refuse path is what we exercise, not success.
    with_resolvable_price(Billing::Plans::STARTER) do
      post admin_price_migrations_path, params: {
        plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd"
      }
    end

    assert_redirected_to new_admin_price_migration_path(plan_key: "starter", currency: "usd", old_price_id: "price_fake_starter_usd")
    assert_no_enqueued_jobs
  end
end
