require "test_helper"

class BillingAddressesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot update the billing address" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    patch billing_billing_address_path, params: { organization: { billing_name: "Should not save" } }
    assert_redirected_to root_path
  end

  test "the owner can update the billing name and address, which syncs to Stripe" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")

    update_attributes = nil
    fake_update = ->(_processor_id, attributes, _opts) { update_attributes = attributes }

    Stripe::Customer.stub(:update, fake_update) do
      patch billing_billing_address_path, params: {
        organization: {
          billing_name: "Acme Inc",
          billing_address_line1: "1 Infinite Loop",
          billing_address_city: "Cupertino",
          billing_address_state: "CA",
          billing_address_postal_code: "95014",
          billing_address_country: "US"
        }
      }
    end

    assert_redirected_to billing_path
    assert_equal "Billing details updated.", flash[:notice]

    @organization.reload
    assert_equal "Acme Inc", @organization.billing_name
    assert_equal "1 Infinite Loop", @organization.billing_address_line1
    assert_equal "Acme Inc", update_attributes[:name]
    assert_equal "Cupertino", update_attributes[:address][:city]
    assert AuditLog.exists?(event_type: :billing_details_updated, resource_type: "Organization", resource_id: @organization.id)
  end

  test "a Stripe error while updating billing details shows an alert instead of crashing" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")

    Stripe::Customer.stub(:update, ->(*) { raise Pay::Stripe::Error.new(Stripe::StripeError.new("boom")) }) do
      patch billing_billing_address_path, params: { organization: { billing_name: "Acme Inc" } }
    end

    assert_redirected_to billing_path
    assert_equal "boom", flash[:alert]
  end
end
