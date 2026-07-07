require "test_helper"

class PayWebhooksTest < ActionDispatch::IntegrationTest
  test "an unsigned request to the Stripe webhook endpoint is rejected" do
    post "/pay/webhooks/stripe", params: { type: "customer.subscription.updated" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
  end

  test "a validly signed request is accepted" do
    payload = { id: "evt_test", type: "customer.subscription.updated", data: { object: { id: "sub_test" } } }.to_json
    secret = "whsec_test_secret"
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    header = Stripe::Webhook::Signature.generate_header(timestamp, signature)

    Pay::Stripe.stub(:signing_secret, secret) do
      post "/pay/webhooks/stripe", params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => header }
    end

    assert_response :ok
  end
end
