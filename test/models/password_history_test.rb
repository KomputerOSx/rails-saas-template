require "test_helper"

class PasswordHistoryTest < ActiveSupport::TestCase
  test "password_used_before? is true when a past digest matches" do
    users(:one).password_histories.create!(password_digest: BCrypt::Password.create("Xk92!vTqZmR7"))

    assert PasswordHistory.password_used_before?(users(:one), "Xk92!vTqZmR7")
    assert_not PasswordHistory.password_used_before?(users(:one), "SomethingElse99!")
  end

  test "password_used_before? only checks the 10 most recent entries" do
    11.times { |i| users(:one).password_histories.create!(password_digest: BCrypt::Password.create("Password#{i}!Aa")) }

    assert_not PasswordHistory.password_used_before?(users(:one), "Password0!Aa")
    assert PasswordHistory.password_used_before?(users(:one), "Password10!Aa")
  end
end
