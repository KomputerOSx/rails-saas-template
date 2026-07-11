module Admin
  class EmailCampaignsController < BaseController
    before_action { authorize :system, :manage_email_campaigns?, policy_class: SystemPolicy }
    before_action :set_email_campaign, only: [ :show, :edit, :update, :destroy, :deliver, :recipients ]
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
        max_width: params[:email_campaign][:max_width],
        bg_color: params[:email_campaign][:bg_color],
        fg_color: params[:email_campaign][:fg_color],
        category: params[:email_campaign][:category],
        to: recipients_from_params,
        created_by: current_user
      )
      log_audit(:email_campaign_created, resource: email_campaign, metadata: { recipient_count: email_campaign.email_campaign_recipients.count })
      redirect_to admin_email_campaign_path(email_campaign), notice: "Campaign saved as draft with #{email_campaign.email_campaign_recipients.count} recipient(s). Review and send when ready."
    rescue ArgumentError => e
      new_attrs = { subject: params.dig(:email_campaign, :subject), body_html: params.dig(:email_campaign, :body_html) }
      new_attrs[:max_width] = params.dig(:email_campaign, :max_width) if params.dig(:email_campaign, :max_width).present?
      new_attrs[:bg_color] = params.dig(:email_campaign, :bg_color) if params.dig(:email_campaign, :bg_color).present?
      new_attrs[:fg_color] = params.dig(:email_campaign, :fg_color) if params.dig(:email_campaign, :fg_color).present?
      new_attrs[:category] = params.dig(:email_campaign, :category) if params.dig(:email_campaign, :category).present?
      @email_campaign = EmailCampaign.new(new_attrs)
      @users = User.order(:email)
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def show
      @recipient_counts = @email_campaign.recipient_counts
    end

    def recipients
      @email_campaign_recipients = @email_campaign.email_campaign_recipients.includes(:user).order(:id)
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
          body_html: params[:email_campaign][:body_html],
          max_width: params[:email_campaign][:max_width],
          bg_color: params[:email_campaign][:bg_color],
          fg_color: params[:email_campaign][:fg_color],
          category: params[:email_campaign][:category]
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
      if @email_campaign.images_too_large_to_send?
        total_mb = (@email_campaign.referenced_images_total_bytes / 1.megabyte.to_f).round(1)
        max_mb = EmailCampaign::MAX_TOTAL_INLINE_IMAGE_BYTES / 1.megabyte
        return redirect_to admin_email_campaign_path(@email_campaign),
          alert: "This campaign's images total #{total_mb} MB - over the #{max_mb} MB limit. " \
                 "Images are embedded directly in every recipient's email, so remove or shrink some before sending."
      end

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
