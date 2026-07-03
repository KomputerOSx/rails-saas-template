class Users::SessionsController < Devise::SessionsController
  def create
    super do |resource|
      if resource.persisted?
        flash.delete(:notice)
        flash[:toast] = { message: "Signed in successfully.", type: "success" }
      end
    end
  end

  def destroy
    super do
      flash.delete(:notice)
      flash[:toast] = { message: "Signed out successfully.", type: "success" }
    end
  end
end
