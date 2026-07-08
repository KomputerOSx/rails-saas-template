require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "slug must be unique and DNS-safe" do
    Organization.create!(name: "Acme", slug: "acme")

    duplicate = Organization.new(name: "Acme Two", slug: "acme")
    assert_not duplicate.valid?

    invalid = Organization.new(name: "Bad", slug: "Not_Valid!")
    assert_not invalid.valid?
  end

  test "reserved slugs are rejected" do
    org = Organization.new(name: "Admin", slug: "admin")
    assert_not org.valid?
  end

  test "create_personal_for! derives name and slug from the email local-part" do
    user = User.create!(email: "jane.doe@example.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)

    organization = Organization.create_personal_for!(user)

    assert_equal "Jane Doe", organization.name
    assert_equal "jane-doe", organization.slug
    assert user.memberships.exists?(organization: organization)
    assert user.memberships.first.has_role?(Role::APP_OWNER, scope: :app)
  end

  test "create_personal_for! resolves slug collisions across different email domains" do
    user_one = User.create!(email: "jane.doe@gmail.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)
    user_two = User.create!(email: "jane.doe@yahoo.com", password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52", confirmed_at: Time.current)

    org_one = Organization.create_personal_for!(user_one)
    org_two = Organization.create_personal_for!(user_two)

    assert_not_equal org_one.slug, org_two.slug
    assert_equal "jane-doe", org_one.slug
    assert_equal "jane-doe-2", org_two.slug
  end

  test "current_plan defaults to Free with no subscription" do
    organization = Organization.create_personal_for!(users(:one))

    assert_equal Billing::Plans::FREE, organization.current_plan
    assert_equal 1, organization.member_limit
  end

  test "current_plan resolves to the plan matching the active subscription's price" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      assert_equal Billing::Plans::STARTER, organization.current_plan
      assert_equal 5, organization.member_limit
    end
  end

  test "current_plan falls back to Free once the subscription is canceled" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      organization.payment_processor.subscription.update!(status: "canceled", ends_at: 1.day.ago)
    end

    assert_equal Billing::Plans::FREE, organization.current_plan
  end

  test "member_count_with_pending counts memberships and outstanding invitations, not revoked ones" do
    organization = Organization.create_personal_for!(users(:one))
    role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)

    assert_equal 1, organization.member_count_with_pending

    invitation, = OrganizationInvitation.generate_for!(organization: organization, email: "a@example.com", role: role)
    assert_equal 2, organization.member_count_with_pending

    invitation.revoke!
    assert_equal 1, organization.member_count_with_pending
  end

  test "at_member_limit? is true for a fresh Free-tier org (the owner already fills the sole seat)" do
    organization = Organization.create_personal_for!(users(:one))

    assert organization.at_member_limit?
    assert_equal 0, organization.remaining_seats
  end

  test "at_member_limit? is false while a paid plan has open seats" do
    organization = Organization.create_personal_for!(users(:one))

    with_active_subscription(organization, Billing::Plans::STARTER) do
      assert_not organization.at_member_limit?
      assert_equal 4, organization.remaining_seats
    end
  end

  test "over_member_limit? reflects the over_member_limit_at flag, not a live recompute" do
    organization = Organization.create_personal_for!(users(:one))

    assert_not organization.over_member_limit?
    organization.update!(over_member_limit_at: Time.current)
    assert organization.over_member_limit?
  end

  test "change_plan! raises without a payment method on file" do
    organization = Organization.create_personal_for!(users(:one))

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_raises(ArgumentError) { organization.change_plan!(Billing::Plans.find("starter")) }
    end
  end

  test "change_plan! starts a 14-day trial for a first-ever Starter subscription" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_difference "Pay::Subscription.count", 1 do
        assert_equal :trial_started, organization.change_plan!(Billing::Plans.find("starter"))
      end
    end

    assert organization.reload.trial_used_at.present?
    assert organization.payment_processor.subscription.trial_ends_at.present?
  end

  test "change_plan! never grants a second trial once trial_used_at is set" do
    organization = Organization.create_personal_for!(users(:one))
    organization.update!(trial_used_at: 1.year.ago)
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_equal :created, organization.change_plan!(Billing::Plans.find("starter"))
    end

    assert_nil organization.payment_processor.subscription.trial_ends_at
  end

  test "change_plan! subscribes Growth from Free with no trial (Starter-only trials)" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_resolvable_price(Billing::Plans::GROWTH) do
      assert_equal :created, organization.change_plan!(Billing::Plans.find("growth"))
    end

    assert_nil organization.reload.trial_used_at
    assert_nil organization.payment_processor.subscription.trial_ends_at
  end

  test "change_plan! upgrades in place, keeping a single subscription" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(organization, Billing::Plans::STARTER) do
      with_resolvable_price(Billing::Plans::GROWTH) do
        assert_no_difference "Pay::Subscription.count" do
          assert_equal :upgraded, organization.change_plan!(Billing::Plans.find("growth"))
        end
      end
    end
  end

  test "change_plan! passes an applied promotion code through to Stripe on upgrade" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    customer.payment_methods.create!(processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    # `swap` reads the subscription's current item id off the locally-synced `object` JSON
    # (Pay::Stripe::Subscription#subscription_items => stripe_object.items) rather than making a
    # live Stripe API call as long as that column is already populated - set it directly so this
    # test doesn't need to stub Stripe::Subscription.retrieve too.
    fake_stripe_subscription = customer.subscriptions.create!(
      name: "default", processor_id: "sub_test123", processor_plan: "price_fake_starter_usd", status: "active", quantity: 1,
      object: { id: "sub_test123", items: { object: "list", data: [ { id: "si_test123" } ] } }
    )
    captured_params = nil

    Stripe::Subscription.stub(:update, ->(_id, params, _opts) { captured_params = params; fake_stripe_subscription }) do
      Billing::Plans.stub(:for_stripe_price, Billing::Plans::STARTER) do
        with_resolvable_price(Billing::Plans::GROWTH) do
          organization.change_plan!(Billing::Plans.find("growth"), promotion_code: "promo_test123")
        end
      end
    end

    assert_equal [ { promotion_code: "promo_test123" } ], captured_params[:discounts]
  end

  test "change_plan! schedules a downgrade at period end instead of applying it now" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    period_end = 20.days.from_now.to_i
    phase_item = Struct.new(:price, :quantity).new("price_fake_growth_usd", 1)
    phase = Struct.new(:items, :start_date, :end_date).new([ phase_item ], 10.days.ago.to_i, period_end)
    fake_schedule = Struct.new(:id, :phases).new("sub_sched_test123", [ phase ])
    schedule_update_args = nil

    with_active_subscription(organization, Billing::Plans::GROWTH) do
      with_resolvable_price(Billing::Plans::STARTER) do
        Stripe::SubscriptionSchedule.stub(:create, fake_schedule) do
          Stripe::SubscriptionSchedule.stub(:update, ->(id, params) { schedule_update_args = [ id, params ]; fake_schedule }) do
            assert_equal :downgrade_scheduled, organization.change_plan!(Billing::Plans.find("starter"))
          end
        end
      end

      # The live subscription is untouched until Stripe flips it at renewal.
      assert_equal "price_fake_growth_usd", organization.payment_processor.subscription.processor_plan
    end

    organization.reload
    assert_equal "starter", organization.pending_plan_key
    assert_equal "sub_sched_test123", organization.stripe_subscription_schedule_id
    assert_in_delta period_end, organization.pending_plan_change_at.to_i, 1

    assert_equal "sub_sched_test123", schedule_update_args[0]
    assert_equal "release", schedule_update_args[1][:end_behavior]
    assert_equal "price_fake_starter_usd", schedule_update_args[1][:phases].last[:items].first[:price]
  end

  test "cancel_scheduled_downgrade! releases the schedule and clears pending state" do
    organization = Organization.create_personal_for!(users(:one))
    organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_test123")

    released_id = nil
    Stripe::SubscriptionSchedule.stub(:release, ->(id) { released_id = id }) do
      organization.cancel_scheduled_downgrade!
    end

    assert_equal "sub_sched_test123", released_id
    organization.reload
    assert_nil organization.pending_plan_key
    assert_nil organization.pending_plan_change_at
    assert_nil organization.stripe_subscription_schedule_id
  end

  test "cancel_subscription! cancels at period end and keeps the subscription active until then" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(organization, Billing::Plans::STARTER) do
      organization.cancel_subscription!

      subscription = organization.payment_processor.subscription.reload
      assert subscription.active?
      assert subscription.ends_at.present?
      assert subscription.on_grace_period?
    end
  end

  test "trial_eligible? is Starter-only and one-shot" do
    organization = Organization.create_personal_for!(users(:one))

    assert organization.trial_eligible?(Billing::Plans::STARTER)
    assert_not organization.trial_eligible?(Billing::Plans::GROWTH)

    organization.update!(trial_used_at: Time.current)
    assert_not organization.trial_eligible?(Billing::Plans::STARTER)
  end

  test "preferred_currency must be a supported currency" do
    organization = Organization.create_personal_for!(users(:one))

    organization.preferred_currency = "eur"
    assert_not organization.valid?

    organization.preferred_currency = "gbp"
    assert organization.valid?
  end

  test "billing_currency defaults to preferred_currency while on Free" do
    organization = Organization.create_personal_for!(users(:one))
    organization.update!(preferred_currency: "gbp")

    assert_equal "gbp", organization.billing_currency
  end

  test "billing_currency locks to the active subscription's currency once subscribed, ignoring preferred_currency" do
    organization = Organization.create_personal_for!(users(:one))
    organization.update!(preferred_currency: "usd")

    with_active_subscription(organization, Billing::Plans::STARTER, currency: "gbp") do
      assert_equal "gbp", organization.billing_currency
    end
  end

  test "stripe_billing_address is nil until any address field is set" do
    organization = Organization.create_personal_for!(users(:one))
    assert_nil organization.stripe_billing_address

    organization.update!(billing_address_city: "Springfield")
    assert_equal "Springfield", organization.stripe_billing_address[:city]
  end

  test "sync_billing_details! persists locally and pushes name/address to the Stripe customer" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")

    update_attributes = nil
    fake_update = ->(_processor_id, attributes, _opts) { update_attributes = attributes }

    Stripe::Customer.stub(:update, fake_update) do
      organization.sync_billing_details!(name: "Jane Doe", address: { line1: "1 Main St", country: "US" })
    end

    assert_equal "Jane Doe", organization.billing_name
    assert_equal "1 Main St", organization.billing_address_line1
    assert_equal "Jane Doe", update_attributes[:name]
    assert_equal "1 Main St", update_attributes[:address][:line1]
  end

  test "the Stripe customer attributes fall back to the organization's own name until a billing name is set" do
    organization = Organization.create_personal_for!(users(:one))
    customer = organization.set_payment_processor(:stripe)

    assert_equal organization.name, customer.api_record_attributes[:name]
    assert_nil customer.api_record_attributes[:address]

    organization.update!(billing_name: "Custom Billing Name", billing_address_country: "US")
    assert_equal "Custom Billing Name", customer.api_record_attributes[:name]
    assert_equal "US", customer.api_record_attributes[:address][:country]
  end
end
