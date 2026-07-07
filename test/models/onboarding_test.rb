require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  test "steps are welcome, profile, team, finish in order" do
    assert_equal %w[welcome profile team finish], Onboarding.keys
  end

  test "find returns the step matching a key, or nil for an unknown key" do
    assert_equal "Welcome", Onboarding.find("welcome").title
    assert_equal "welcome", Onboarding.find(:welcome).key
    assert_nil Onboarding.find("not_a_step")
  end

  test "first_step and last_step return the boundary steps" do
    assert_equal "welcome", Onboarding.first_step.key
    assert_equal "finish", Onboarding.last_step.key
  end

  test "last_step? is true only for the final step" do
    assert Onboarding.last_step?("finish")
    assert_not Onboarding.last_step?("welcome")
  end

  test "step_before returns the previous step, or nil for the first step" do
    assert_equal "welcome", Onboarding.step_before("profile").key
    assert_nil Onboarding.step_before("welcome")
  end

  test "step_after returns the next step, or nil for the last step" do
    assert_equal "profile", Onboarding.step_after("welcome").key
    assert_nil Onboarding.step_after("finish")
  end

  test "index_of returns the position of a step key" do
    assert_equal 0, Onboarding.index_of("welcome")
    assert_equal 3, Onboarding.index_of("finish")
    assert_nil Onboarding.index_of("not_a_step")
  end
end
