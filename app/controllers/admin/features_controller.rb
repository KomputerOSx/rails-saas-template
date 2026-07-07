module Admin
  class FeaturesController < BaseController
    before_action :set_feature, only: [ :edit, :update ]

    def index
      @q = params[:q].to_s.strip

      @features = Feature.order(:key)
      @features = @features.where("key LIKE ? OR name LIKE ?", like(@q), like(@q)) if @q.present?
    end

    def edit
      @organizations = Organization.order(:name)
      render partial: "edit_frame"
    end

    def update
      if @feature.update(feature_params)
        sync_organization_access!
        log_audit(:feature_updated, resource: @feature, metadata: { key: @feature.key, enabled: @feature.enabled })
        @organizations = Organization.order(:name)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:toast] = { message: "Feature updated.", type: "success" }
            render turbo_stream: [
              turbo_stream.replace(dom_id(@feature, :enabled_cell), partial: "admin/features/enabled_cell", locals: { feature: @feature }),
              turbo_stream.replace(dom_id(@feature, :opt_in_cell), partial: "admin/features/opt_in_cell", locals: { feature: @feature }),
              turbo_stream.replace(dom_id(@feature, :org_count_cell), partial: "admin/features/org_count_cell", locals: { feature: @feature }),
              turbo_stream.replace(dom_id(@feature, :edit_frame), partial: "edit_frame"),
              turbo_stream.update("flash_messages", partial: "shared/flash")
            ]
          end
          format.html { redirect_to admin_features_path, notice: "Feature updated." }
        end
      else
        @organizations = Organization.order(:name)
        flash.now[:alert] = @feature.errors.full_messages.join(", ")
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(dom_id(@feature, :edit_frame), partial: "edit_frame"),
                   status: :unprocessable_entity
          end
          format.html { render partial: "edit_frame", status: :unprocessable_entity }
        end
      end
    end

    private

    def set_feature
      @feature = Feature.find(params[:id])
    end

    def feature_params
      params.require(:feature).permit(:enabled, :manager_activation_required)
    end

    def like(term)
      "%#{Feature.sanitize_sql_like(term)}%"
    end

    # Submitted organization_ids is the full desired "granted" set. Never deletes
    # FeatureOrganizationAccess rows - flips enabled true/false instead, so access
    # history is preserved rather than lost.
    def sync_organization_access!
      submitted_ids = Array(params[:feature][:organization_ids]).reject(&:blank?).map(&:to_i)

      Organization.where(id: submitted_ids).find_each do |organization|
        access = @feature.feature_organization_accesses.find_or_initialize_by(organization: organization)
        was_enabled = access.persisted? && access.enabled?
        access.update!(enabled: true)
        log_audit(:feature_access_granted, resource: @feature, metadata: { organization_id: organization.id }) unless was_enabled
      end

      @feature.feature_organization_accesses.where.not(organization_id: submitted_ids).find_each do |access|
        next unless access.enabled?

        access.update!(enabled: false)
        log_audit(:feature_access_revoked, resource: @feature, metadata: { organization_id: access.organization_id })
      end
    end
  end
end
