require "test_helper"
require "ostruct"

class Billing::SubscriptionSyncHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @organization = Organization.create_personal_for!(users(:one))
    @handler = Billing::SubscriptionSyncHandler.new
  end

  test "enqueues a reconcile job for the subscription's owning organization" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    subscription = customer.subscribe(plan: "price_fake_starter")

    event = stripe_event("customer.subscription.updated", subscription.processor_id)

    assert_enqueued_with(job: Billing::ReconcileOrganizationJob, args: [ @organization.id, { audit_event_type: "subscription_updated" } ]) do
      @handler.call(event)
    end
  end

  test "maps subscription.deleted to the subscription_cancelled audit event type" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    subscription = customer.subscribe(plan: "price_fake_growth")

    event = stripe_event("customer.subscription.deleted", subscription.processor_id)

    assert_enqueued_with(job: Billing::ReconcileOrganizationJob, args: [ @organization.id, { audit_event_type: "subscription_cancelled" } ]) do
      @handler.call(event)
    end
  end

  test "does nothing when no local subscription matches the event" do
    event = stripe_event("customer.subscription.updated", "sub_unknown")

    assert_no_enqueued_jobs do
      @handler.call(event)
    end
  end

  private

  def stripe_event(type, subscription_processor_id)
    OpenStruct.new(type: type, data: OpenStruct.new(object: OpenStruct.new(id: subscription_processor_id)))
  end
end
