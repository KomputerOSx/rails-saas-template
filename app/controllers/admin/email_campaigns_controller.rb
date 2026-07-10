module Admin
  class EmailCampaignsController < BaseController
    before_action { authorize :system, :manage_email_campaigns?, policy_class: SystemPolicy }
    before_action :set_email_campaign, only: [ :show, :edit, :update, :destroy, :deliver ]
    before_action :require_draft!, only: [ :edit, :update, :destroy, :deliver ]

    def index
      @q      = params[:q].to_s.strip
      @status = params[:status].to_s.strip

      @email_campaigns = EmailCampaign.recent.includes(:created_by, :email_campaign_recipients)
      @email_campaigns = @email_campaigns.where("subject LIKE ?", "%#{EmailCampaign.sanitize_sql_like(@q)}%") if @q.present?
      @email_campaigns = @email_campaigns.where(status: @status) if EmailCampaign.statuses.key?(@status)
    end

    def new
      @email_campaign = EmailCampaign.new
      @users = User.order(:email)
    end

    def create
      email_campaign = EmailCampaign.create_draft!(
        subject: params[:email_campaign][:subject],
        body_html: params[:email_campaign][:body_html],
        to: recipients_from_params,
        created_by: current_user
      )
      log_audit(:email_campaign_created, resource: email_campaign, metadata: { recipient_count: email_campaign.email_campaign_recipients.count })
      redirect_to admin_email_campaign_path(email_campaign), notice: "Campaign saved as draft with #{email_campaign.email_campaign_recipients.count} recipient(s). Review and send when ready."
    rescue ArgumentError => e
      @email_campaign = EmailCampaign.new(subject: params.dig(:email_campaign, :subject), body_html: params.dig(:email_campaign, :body_html))
      @users = User.order(:email)
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def show
      @email_campaign_recipients = @email_campaign.email_campaign_recipients.includes(:user)
    end

    def edit
      @users = User.order(:email)
      @selected_user_ids = @email_campaign.recipients.pluck(:id)
    end

    def update
      recipient_ids = recipients_from_params.pluck(:id)
      raise ArgumentError, "no recipients given" if recipient_ids.empty?

      ActiveRecord::Base.transaction do
        @email_campaign.update!(
          subject: params[:email_campaign][:subject],
          body_html: params[:email_campaign][:body_html]
        )
        @email_campaign.email_campaign_recipients.where.not(user_id: recipient_ids).destroy_all
        existing_user_ids = @email_campaign.recipients.pluck(:id)
        (recipient_ids - existing_user_ids).each do |user_id|
          @email_campaign.email_campaign_recipients.create!(user_id: user_id)
        end
      end

      log_audit(:email_campaign_updated, resource: @email_campaign, metadata: { recipient_count: @email_campaign.email_campaign_recipients.count })
      redirect_to admin_email_campaign_path(@email_campaign), notice: "Campaign updated."
    rescue ArgumentError => e
      @users = User.order(:email)
      @selected_user_ids = recipient_ids || []
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @email_campaign.destroy!
      log_audit(:email_campaign_deleted, resource: @email_campaign)
      redirect_to admin_email_campaigns_path, notice: "Campaign deleted."
    end

    def deliver
      recipient_count = @email_campaign.email_campaign_recipients.count
      @email_campaign.update!(status: :sending)
      SendEmailCampaignJob.perform_later(@email_campaign.id)
      log_audit(:email_campaign_sent, resource: @email_campaign, metadata: { recipient_count: recipient_count })
      redirect_to admin_email_campaign_path(@email_campaign), notice: "Sending to #{recipient_count} user(s)..."
    end

    private

    def set_email_campaign
      @email_campaign = EmailCampaign.find(params[:id])
    end

    def require_draft!
      return if @email_campaign.deliverable?
      redirect_to admin_email_campaign_path(@email_campaign), alert: "This campaign has already been sent."
    end

    def recipients_from_params
      if params[:email_campaign][:send_to_all] == "1"
        User.all
      else
        User.where(id: Array(params[:email_campaign][:user_ids]).reject(&:blank?))
      end
    end
  end
end
