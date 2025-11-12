class SkiptonExportsController < ApplicationController
  def index
    @mapping_file = Rails.root.join('config', 'skipton_customer_mappings.csv')
    @has_mappings = File.exist?(@mapping_file)
  end

  def create
    unless params[:xero_file].present?
      flash[:alert] = "Please select a Xero export file"
      redirect_to skipton_exports_path and return
    end

    begin
      result = SkiptonExportService.new(params[:xero_file]).transform

      if result[:missing_customers].any?
        flash.now[:alert] = "Missing Skipton IDs for #{result[:missing_customers].count} customers"
        @missing_customers = result[:missing_customers]
        @mapping_file = Rails.root.join('config', 'skipton_customer_mappings.csv')
        @has_mappings = File.exist?(@mapping_file)
        render :index and return
      end

      # Send the CSV file for download
      send_data result[:csv_content],
                filename: "skipton_export_#{Date.today.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'

    rescue => e
      flash[:alert] = "Error processing file: #{e.message}"
      redirect_to skipton_exports_path
    end
  end
end
