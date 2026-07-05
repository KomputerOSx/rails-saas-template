module Onboarding
  Step = Struct.new(:key, :title, :description, :view, keyword_init: true)

  STEPS = [
    Step.new(key: "welcome", title: "Welcome",
      description: "Let's get your account set up.",
      view: "onboarding/steps/welcome"),
    Step.new(key: "profile", title: "Tell us about you",
      description: "A little context helps us tailor your experience.",
      view: "onboarding/steps/profile"),
    Step.new(key: "team", title: "Invite your team",
      description: "Bring your teammates along — you can always do this later.",
      view: "onboarding/steps/team"),
    Step.new(key: "finish", title: "You're all set",
      description: "You're ready to go.",
      view: "onboarding/steps/finish"),
  ].freeze

  module_function

  def steps = STEPS
  def keys = STEPS.map(&:key)
  def find(key) = STEPS.find { |s| s.key == key.to_s }
  def first_step = STEPS.first
  def last_step = STEPS.last
  def last_step?(key) = key.to_s == last_step.key
  def index_of(key) = keys.index(key.to_s)
  def step_before(key) = (i = index_of(key)) && i > 0 ? STEPS[i - 1] : nil
  def step_after(key) = (i = index_of(key)) && STEPS[i + 1]
end
