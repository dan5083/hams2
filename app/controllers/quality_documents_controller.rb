# app/controllers/quality_documents_controller.rb
class QualityDocumentsController < ApplicationController
  before_action :set_document, only: [:show, :edit, :update, :destroy, :show_pdf]

  def index
    @documents = QualityDocument.order(:document_type, :code)
    @documents_by_type = @documents.group_by(&:document_type)
  end

  def show
    @revisions = @document.revisions.order(issue_number: :desc)
  end

  def new
    @document = QualityDocument.new
  end

  def create
    @document = QualityDocument.new(document_params)

    if @document.save
      redirect_to @document, notice: 'Quality document was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @document.update(document_params)
      redirect_to @document, notice: 'Quality document was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to quality_documents_url, notice: 'Quality document was successfully deleted.'
  end

  def show_pdf
    render layout: 'pdf'
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
      :approved_by,
      :content
    )
  end
end
