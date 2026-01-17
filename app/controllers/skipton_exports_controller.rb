# app/controllers/skipton_exports_controller.rb
class SkiptonExportsController < ApplicationController
  # GET /skipton_exports
  def index
    # Show any missing customers from previous attempt (stored in session)
    @missing_customers = session.delete(:missing_customers) || []
  end

  # POST /skipton_exports
  def create
    unless params[:xero_file].present?
      redirect_to skipton_exports_path, alert: "Please select a Xero CSV file to upload"
      return
    end

    begin
      # Transform the CSV
      service = SkiptonExportService.new(params[:xero_file])
      result = service.transform

      # Check if there are missing customers
      if result[:missing_customers].present?
        # Store missing customers in session and show form
        session[:missing_customers] = result[:missing_customers]
        redirect_to skipton_exports_path and return
      end

      # Success - send the file to user
      send_data result[:csv_content],
                filename: "skipton_export_#{Date.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'

    rescue => e
      Rails.logger.error "Skipton export error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to skipton_exports_path, alert: "Export failed: #{e.message}"
    end
  end
end
