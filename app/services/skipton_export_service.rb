require 'csv'

class SkiptonExportService
  def initialize(xero_file)
    @xero_file = xero_file
  end

  def transform
    # Load customer mapping from database
    customer_map = SkiptonCustomerMapping.mapping_hash

    output_rows = []
    missing_customers = []
    processed_invoices = Set.new

    CSV.parse(@xero_file.read, headers: true) do |row|
      contact_name = row['ContactName']&.strip
      invoice_number = row['InvoiceNumber']&.strip
      invoice_date = row['InvoiceDate']&.strip
      total = row['Total']&.strip

      # Skip if we've already processed this invoice
      next if processed_invoices.include?(invoice_number)
      processed_invoices.add(invoice_number)

      # Look up Skipton ID from database
      skipton_id = customer_map[contact_name]

      if skipton_id.present?
        output_rows << {
          'CUSTOMER ID' => skipton_id,
          'REFERENCE' => invoice_number,
          'DATE' => invoice_date,
          'TOTAL AMOUNT' => total,
          'TYPE' => 'Invoice'
        }
      else
        missing_customers << contact_name unless missing_customers.include?(contact_name)
      end
    end

    # Generate CSV content
    csv_content = CSV.generate(headers: true) do |csv|
      csv << ['CUSTOMER ID', 'REFERENCE', 'DATE', 'TOTAL AMOUNT', 'TYPE']
      output_rows.each do |row|
        csv << row.values
      end
    end

    {
      csv_content: csv_content,
      invoices_count: output_rows.size,
      missing_customers: missing_customers
    }
  end
end
