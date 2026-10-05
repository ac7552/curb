# Your details (name, where you live, the kinds of car you like) and your plan.
class AccountsController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(params.expect(user: [ :first_name, :last_name, :country, :postal_code, car_types: [] ]))
    if @user.save(context: :profile)
      redirect_to account_path, notice: "Saved."
    else
      render :show, status: :unprocessable_entity
    end
  end
end
