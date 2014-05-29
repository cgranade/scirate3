require 'open-uri'

class UsersController < ApplicationController
  before_filter :signed_in_user,
           only: [:feeds, :edit, :update, :destroy, :settings, :settings_password]

  before_filter :correct_user, only: [:edit, :update, :destroy]

  before_filter :profile_data, only: [:activity, :papers, :scites, :comments]

  def profile_data
    @user = User.find_by_username!(params[:username])
  end

  def activity
    @tab = :activity
    @activities = @user.activities.order('created_at DESC').limit(50)

    render 'users/profile'
  end

  def papers
    @tab = :papers

    @authored_papers = @user.authored_papers.paginate(page: params[:page])
    @scited_ids = current_user.scited_papers.pluck(:id) if current_user

    render 'users/profile'
  end

  def scites
    @tab = :scites

    scited_papers = @user.scited_papers.order("scites.created_at DESC")

    @scited_ids = current_user.scited_papers.pluck(:id) if current_user

    @scited_papers = scited_papers
      .includes(:feeds, :authors)
      .paginate(page: params[:page], per_page: 10)

    render 'users/profile'
  end

  def comments
    @tab = :comments

    @comments = @user.comments
      .where(hidden: false, deleted: false)
      .includes(:user, :paper)
      .paginate(page: params[:page], per_page: 20)

    render 'users/profile'
  end

  def new
    if !signed_in?
      @user = User.new
    else
      flash[:error] = "Sign out to create a new user!"
      redirect_to root_path
    end
  end

  def create
    if !signed_in?
      default_username = User.default_username(params[:user][:fullname])
      @user = User.new(params.required(:user).permit(:fullname, :email, :password).merge(username: default_username, password_confirmation: params[:user][:password]))
      if @user.save
        @user.send_signup_confirmation
        sign_in @user
        redirect_to root_path
      else
        render 'new'
      end
    else
      flash[:error] = "Sign out to create a new user!"
      redirect_to root_path
    end
  end

  def edit
  end

  def destroy
    user = User.find_by_id(params[:id])

    if user == current_user
      user.destroy
      flash[:success] = "Your profile has been deleted."
      redirect_to root_path
    else
      redirect_to root_path
    end
  end

  def activate
    user = User.find_by_id(params[:id])

    if user && !user.email_confirmed? && user.confirmation_token == params[:confirmation_token]

      if user.confirmation_sent_at > 2.days.ago
        user.activate
        flash[:success] = "Your account has been activated."
        sign_in(user)
        redirect_to root_url
      else
        user.send_signup_confirmation
        flash[:error] = "Confirmation link has expired: a new confirmation email has been sent to #{user.email}"
        redirect_to root_url
      end
    else
      flash[:error] = "Account is already active or link is invalid!"
      redirect_to root_url
    end
  end

  # Big feed subscriptions page
  def feeds
    @user = current_user
    @subscribed_ids = @user.subscriptions.pluck(:feed_uid)
  end

  def settings
    @user = current_user
    return unless request.post?

    old_email = @user.email

    user_params = params.required(:user)
                        .permit(:fullname, :email, :username, :url, :organization, :location, :author_identifier, :about)

    if @user.update_attributes(user_params)
      if old_email != @user.email
        @user.send_email_change_confirmation(old_email)
        sign_in @user
      end

      sign_in @user
      flash[:success] = "Profile updated"
    else
      flash[:error] = @user.errors.full_messages
    end
  end

  def settings_password
    @user = current_user
    return unless request.post?

    if @user.password_digest.nil? || @user.authenticate(params[:current_password])
      if params[:new_password] == params[:confirm_password]
        if @user.change_password(params[:new_password])
          sign_in @user
          flash[:success] = "Password changed successfully"
        else
          flash[:error] = @user.errors.full_messages
        end
      else
        flash[:error] = "New password confirmation does not match"
      end
    else
      flash[:error] = "Current password is incorrect"
    end
  end

  private
    def correct_user
      @user = User.find_by_username(params[:username])
      unless current_user?(@user)
        redirect_to(root_path)
      end
    end

end
