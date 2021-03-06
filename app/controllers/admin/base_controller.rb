class Admin::BaseController < ApplicationController
  before_filter :signed_in_user, :require_admin

  def require_admin
    unless current_user.is_admin?
      flash[:error] = "You don't have permission to do that!"
      redirect_to root_url
    end
  end

  def index
    render 'admin/index'
  end

  def alert
    System.alert = params[:alert]
    System.save
    redirect_to admin_path
  end
end
