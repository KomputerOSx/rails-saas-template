module Admin
  class BaseController < ApplicationController
    require_system_admin
  end
end
