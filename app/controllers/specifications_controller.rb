# app/controllers/specifications_controller.rb
class SpecificationsController < ApplicationController
  before_action :set_specification, only: [:show, :edit, :update, :destroy, :download_document, :archive, :unarchive]

  def index
    @specifications = Specification.includes(:created_by, :updated_by)

    # Filter by type (QS/Non-QS)
    if params[:type].present?
      @specifications = case params[:type]
      when 'qs'
        @specifications.qs_specs
      when 'non_qs'
        @specifications.non_qs_specs
      else
        @specifications
      end
    end

    # Filter by status (active/archived)
    @specifications = if params[:show_archived] == 'true'
      @specifications.archived
    else
      @specifications.active
    end

    # Search functionality
    if params[:search].present?
      @specifications = @specifications.search(params[:search])
    end

    @specifications = @specifications.recent.page(params[:page]).per(20)
  end

  def show
  end

  def new
    @specification = Specification.new
    # Pre-fill is_qs if coming from a filtered view
    @specification.is_qs = params[:is_qs] == 'true' if params[:is_qs].present?
  end

  def create
    @specification = Specification.new(specification_params)
    @specification.created_by = Current.user

    # Handle file upload first, then save the specification
    uploaded_file = params[:specification][:temp_document]

    if uploaded_file.present?
      begin
        # Upload to Cloudinary with folder organization
        spec_type = @specification.is_qs? ? "QS" : "Non-QS"
        year = Date.current.year
        folder_path = "Specs/#{spec_type}/#{year}"

        filename_prefix = if @specification.spec_number.present?
          "SPEC#{@specification.spec_number}"
        else
          @specification.title.parameterize[0..50] # Limit length
        end

        upload_result = CloudinaryService.upload_file(
          uploaded_file,
          folder_path,
          filename_prefix: filename_prefix
        )

        # Store document metadata
        @specification.store_document_metadata(upload_result)

        Rails.logger.info "Successfully uploaded document for Specification: #{upload_result[:public_id]}"

      rescue CloudinaryService::CloudinaryError => e
        Rails.logger.error "Failed to upload document: #{e.message}"
        @specification.errors.add(:temp_document, "could not be uploaded: #{e.message}")
        render :new, status: :unprocessable_entity
        return
      end
    else
      # Require document for new specifications
      @specification.errors.add(:temp_document, "is required")
      render :new, status: :unprocessable_entity
      return
    end

    if @specification.save
      redirect_to @specification, notice: "Specification '#{@specification.display_name}' was successfully created."
    else
      # If save failed and we uploaded a file, clean up
      if @specification.cloudinary_public_id.present?
        begin
          CloudinaryService.delete_file(@specification.cloudinary_public_id)
        rescue => e
          Rails.logger.error "Failed to cleanup uploaded file: #{e.message}"
        end
      end

      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Don't allow editing archived specifications
    if @specification.archived?
      redirect_to @specification, alert: 'Archived specifications cannot be edited. Unarchive it first.'
      return
    end
  end

  def update
    # Don't allow updating archived specifications
    if @specification.archived?
      redirect_to @specification, alert: 'Archived specifications cannot be updated.'
      return
    end

    @specification.updated_by = Current.user

    # Handle document replacement
    uploaded_file = params[:specification][:temp_document]

    if uploaded_file.present? && @specification.can_edit_document?
      begin
        # Upload new file to Cloudinary
        spec_type = @specification.is_qs? ? "QS" : "Non-QS"
        year = Date.current.year
        folder_path = "Specs/#{spec_type}/#{year}"

        filename_prefix = if @specification.spec_number.present?
          "SPEC#{@specification.spec_number}"
        else
          @specification.title.parameterize[0..50]
        end

        upload_result = CloudinaryService.upload_file(
          uploaded_file,
          folder_path,
          filename_prefix: filename_prefix
        )

        # Replace the document
        @specification.replace_document!(upload_result)

        Rails.logger.info "Successfully replaced document for Specification #{@specification.id}"

      rescue CloudinaryService::CloudinaryError => e
        Rails.logger.error "Failed to replace document: #{e.message}"
        redirect_to edit_specification_path(@specification), alert: "Failed to replace document: #{e.message}"
        return
      end
    end

    # Regular update
    if @specification.update(specification_params)
      redirect_to @specification, notice: "Specification '#{@specification.display_name}' was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Only allow deletion of non-archived specs
    if @specification.archived?
      redirect_to @specification, alert: 'Cannot delete archived specifications. Unarchive it first if you need to delete it.'
      return
    end

    # Delete document from Cloudinary if it exists
    if @specification.cloudinary_public_id.present?
      begin
        CloudinaryService.delete_file(@specification.cloudinary_public_id)
      rescue => e
        Rails.logger.error "Failed to delete Cloudinary document for Specification #{@specification.id}: #{e.message}"
        # Continue with deletion even if Cloudinary deletion fails
      end
    end

    spec_name = @specification.display_name
    @specification.destroy
    redirect_to specifications_url, notice: "Specification '#{spec_name}' was successfully deleted."
  end

  def download_document
    if @specification.has_document?
      begin
        Rails.logger.info "Starting download for Specification #{@specification.id}"

        # Generate a signed URL for download
        download_url = CloudinaryService.generate_download_url(@specification.cloudinary_public_id)

        if download_url
          Rails.logger.info "Generated download URL, redirecting to Cloudinary"
          redirect_to download_url, allow_other_host: true
        else
          Rails.logger.error "Failed to generate download URL"
          redirect_to @specification, alert: 'Unable to generate download link. Please try again.'
        end

      rescue => e
        Rails.logger.error "Download error: #{e.class} - #{e.message}"
        redirect_to @specification, alert: "Download failed: #{e.message}"
      end
    else
      redirect_to @specification, alert: 'No document available for download.'
    end
  end

  def archive
    if @specification.archive!
      redirect_to @specification, notice: 'Specification archived successfully.'
    else
      redirect_to @specification, alert: 'Failed to archive specification.'
    end
  end

  def unarchive
    if @specification.unarchive!
      redirect_to @specification, notice: 'Specification unarchived successfully.'
    else
      redirect_to @specification, alert: 'Failed to unarchive specification.'
    end
  end

  private

  def set_specification
    @specification = Specification.find(params[:id])
  end

  def specification_params
    params.require(:specification).permit(
      :title, :description, :spec_number, :version, :is_qs
      # Note: temp_document is handled separately
    )
  end
end
