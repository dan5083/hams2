# app/controllers/quality_documents_controller.rb
class QualityDocumentsController < ApplicationController
  before_action :set_document, only: [:show, :edit, :update, :destroy, :show_pdf]

  def index
    @documents = QualityDocument.all

    # Filter by document type if provided
    if params[:document_type].present?
      @documents = @documents.where(document_type: params[:document_type])
    end

    # Search by code, title, or approved_by if provided
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @documents = @documents.where(
        "code ILIKE ? OR title ILIKE ? OR approved_by ILIKE ?",
        search_term, search_term, search_term
      )
    end

    @documents = @documents.order(:document_type, :code)

    # Load amendment records if requested
    @show_amendments = params[:view] == 'amendments'
    if @show_amendments
      amendment_scope = QualityDocumentRevision.joins(:quality_document)
      if params[:document_type].present?
        amendment_scope = amendment_scope.where(quality_documents: { document_type: params[:document_type] })
      end
      @amendments = amendment_scope.includes(:quality_document).order(changed_at: :desc, issue_number: :desc)
    end
  end

  def show
    @revisions = @document.revisions.order(issue_number: :desc)
  end

  def new
    @document = QualityDocument.new
    @document.content = { 'sections' => [], 'references' => [] }
  end

  def create
    @document = QualityDocument.new(document_params)

    # Handle sections and references from form
    @document.content = build_content_from_params

    if @document.save
      redirect_to @document, notice: 'Quality document was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # Handle sections and references from form
    updated_content = build_content_from_params

    # Check if this is a reissue (increment issue number)
    should_reissue = params[:commit] == 'Update & Reissue'

    # Prepare update parameters
    update_params = document_params.except(:content).merge(content: updated_content)

    if should_reissue
      # Only Jim Ledger and Chris Connon can reissue
      unless Current.user&.can_reissue_documents?
        redirect_to @document, alert: 'You are not authorised to reissue documents.'
        return
      end

      # Increment the issue number
      update_params[:current_issue_number] = @document.current_issue_number + 1
      # Pass reissue metadata for the revision record
      @document.skip_revision_tracking = false
      @document.reissue_change_description = params[:reissue_change_description]
      @document.reissue_authorised_by = params[:reissue_authorised_by].presence || Current.user&.display_name
    else
      # Skip revision tracking for regular updates during migration
      @document.skip_revision_tracking = true
      # Preserve existing timestamps
      QualityDocument.record_timestamps = false
    end

    if @document.update(update_params)
      # Re-enable timestamps
      QualityDocument.record_timestamps = true

      message = should_reissue ?
        "Quality document was successfully updated and reissued as Issue #{@document.current_issue_number}." :
        'Quality document was successfully updated.'
      redirect_to @document, notice: message
    else
      # Re-enable timestamps even on failure
      QualityDocument.record_timestamps = true
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to quality_documents_url, notice: 'Quality document was successfully deleted.'
  end

  def show_pdf
    render layout: false
  end

  private

  def set_document
    @document = QualityDocument.find(params[:id])
  end

  def document_params
    params.require(:quality_document).permit(
      :document_type,
      :code,
      :title,
      :current_issue_number,
      :approved_by
    )
  end

  def build_content_from_params
    content = {
      'sections'   => [],
      'references' => []
    }

    if @document.document_type == 'M' && !@document.content.dig('skills_matrix')
      # ── Testing Matrix: structured rows editor ──────────────────────────────
      if params[:matrix_sections].present?
        params[:matrix_sections].each do |_idx, section_data|
          section = {
            'heading' => section_data[:heading].to_s,
            'rows'    => []
          }

          (section_data[:rows] || {}).sort_by { |k, _| k.to_s }.each do |_ridx, row_data|
            case row_data[:type]
            when 'ref'
              # Single-cell reference row — stored as 1-element array
              section['rows'] << [row_data[:ref_text].to_s]

            when 'span'
              # Partial row: explicit cols + a spanning cell + optional NADCAP note
              cols = (row_data[:cols] || {})
                       .sort_by { |k, _| k.to_i }
                       .map { |_, v| v.to_s }
                       .reject(&:blank?)
              row_hash = { 'cols' => cols, 'span' => row_data[:span].to_s }
              row_hash['note'] = row_data[:note].to_s if row_data[:note].present?
              section['rows'] << row_hash

            else
              # Standard 7-cell array row
              cells = (0..6).map { |i| row_data[:cells]&.dig(i.to_s).to_s }
              section['rows'] << cells
            end
          end

          content['sections'] << section
        end
      end

    else
      # ── Standard / Skills Matrix: TinyMCE sections ─────────────────────────
      if params[:sections].present?
        params[:sections].each do |_index, section_data|
          section = {
            'heading' => section_data[:heading],
            'content' => section_data[:content]
          }
          section['flowchart'] = section_data[:flowchart] if section_data[:flowchart].present?
          content['sections'] << section
        end
      end
    end

    # References — common to all document types
    if params[:document].present? && params[:document][:references].present?
      content['references'] = params[:document][:references].reject(&:blank?)
    end

    content
  end
end
