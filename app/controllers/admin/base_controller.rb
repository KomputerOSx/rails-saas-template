module Admin
  class BaseController < ApplicationController
    before_action { authorize :system, :manage?, policy_class: SystemPolicy }
    after_action :verify_authorized
  end
end
