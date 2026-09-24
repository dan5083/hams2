# app/services/quote_service.rb
#
# The assistant's entry point for quoting. Two calls, deliberately:
#
#   1. create_from_request — in the SAME run the drawings were uploaded in
#      (base64 is stripped from the request when the run ends). Finds or
#      creates the part for each line, attaches the run's drawings to every
#      part it creates, and raises the quote. Nothing is emailed.
#   2. send! — after the user has seen the quote and said "send it". Emails
#      the enquirer with the quote PDF and the parts' drawings (fetched from
#      Cloudinary, so it works on any later turn).
#
# Parts are created FULLY CONFIGURED: the caller supplies the same
# customisation_data["operation_selection"] the part form would (treatments
# with operation_id + selected_jig_type, alloy, aerospace flag...), plus a
# jigging location, because the shop wants jigging decided at quote time.
# A part that fails Part's own validation fails the whole call — no half-
# built parts and no quote against a part that doesn't exist.
#
# Usage from AI assistant:
#   QuoteService.create_from_request(
#     customer_name:  "Exact Customer Name",
#     title:          "PD67711-00 — Door Upper Hinge Insert",
#     summary:        "Hard Anodising 50µm, Hot Water Seal, DEF-STAN 03-25",
#     enquirer_email: "buyer@customer.com",
#     enquirer_name:  "Jane Buyer",
#     items: [
#       { part_number: "PD67711-00", part_issue: "A", quantity: 10, unit_amount: 4.50,
#         description: "Hard Anodising 50µm — PD67711-00, Door Upper Hinge Insert",
#         part: {                      # omit when the part already exists in HAMS
#           description: "Door Upper Hinge Insert",
#           specification: "DEF-STAN 03-25 Type III 50µm",
#           material: "6082-T6", specified_thicknesses: "50 µm",
#           process_type: "anodising", aerospace_defense: false,
#           jigging_location: "Hang from Ø6.5 hole, contact inside bore only",
#           operation_selection: { "treatments" => [ { ...as the part form posts... } ] }
#         },
#         attachment_indexes: [0]      # which of the run's files are this part's drawing(s); omit = all
#       }
#     ],
#     request_id: @request_id
#   )
class QuoteService
  class Error < StandardError; end

  # An uploaded-file stand-in for base64 blocks out of an assistant run, so
  # Part#upload_file / CloudinaryService see what they'd see from a form.
  RequestFile = Struct.new(:original_filename, :content_type, :tempfile) do
    def path = tempfile.path
  end

  def self.create_from_request(customer_name:, items:, request_id:, title: nil, summary: nil,
                               enquirer_email: nil, enquirer_name: nil, valid_days: 30, notes: nil)
    customer = find_customer(customer_name) or raise Error, "Customer '#{customer_name}' not found in HAMS. Check the exact name."
    raise Error, "At least one line item is required" if items.blank?

    request = AiAssistantRequest.find(request_id)
    files = request_files(request)
    created_parts = []

    quote = Quote.transaction do
      q = Quote.create!(
        customer: customer, title: title, summary: summary, notes: notes,
        enquirer_email: enquirer_email.presence, enquirer_name: enquirer_name.presence,
        valid_until: Date.current + valid_days.to_i.days,
        ai_request_id: request_id.to_s,
        created_by: request.user # the job runs outside a request; Current.user is unset
      )

      items.each_with_index do |raw, idx|
        item = raw.to_h.transform_keys(&:to_sym)
        part = resolve_part!(customer, item, created_parts)

        if part && created_parts.include?(part)
          wanted = Array(item[:attachment_indexes]).map(&:to_i)
          (wanted.empty? ? files.each_index.to_a : wanted).each do |i|
            f = files[i] or next
            attach!(part, f)
          end
          part.update!(each_price: item[:unit_amount].to_f) if item[:unit_amount].present?
        end

        q.quote_items.create!(
          part: part, position: idx,
          description: item[:description].presence || "#{part&.display_name} #{part&.description}".strip,
          quantity: item[:quantity].to_i.nonzero? || 1,
          unit_amount: item[:unit_amount].to_f.round(2)
        )
      end
      q
    end

    {
      success: true,
      quote_id: quote.id,
      quote_number: quote.display_name,
      url: "/quotes/#{quote.id}",
      customer: customer.name,
      total_ex_tax: quote.total_ex_tax.to_f.round(2),
      valid_until: quote.valid_until,
      enquirer_email: quote.enquirer_email,
      parts_created: created_parts.map { |p| { id: p.id, part: p.display_name, drawings: p.files.length, url: "/parts/#{p.id}" } },
      parts_reused:  (quote.parts.to_a - created_parts).map { |p| { id: p.id, part: p.display_name, url: "/parts/#{p.id}" } },
      files_in_run:  files.length,
      message: "#{quote.display_name} raised for #{customer.name} — £#{'%.2f' % quote.total_ex_tax} ex-VAT. Not yet sent: call QuoteService.send!(quote_id: \"#{quote.id}\") once the user confirms."
    }
  rescue => e
    Rails.logger.error "[QuoteService] create_from_request: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  ensure
    files&.each { |f| f.tempfile.close! rescue nil }
  end

  # Email the quote. `to` overrides the stored enquirer address (and is saved
  # back); cc goes to the raising user and QUOTES_CC if set.
  def self.send!(quote_id:, to: nil, cc: nil)
    quote = Quote.find(quote_id)
    quote.update!(enquirer_email: to) if to.present?
    raise Error, "#{quote.display_name} has no enquirer email — pass to:" unless quote.can_send?

    mail = QuoteMailer.quote_email(quote, cc: Array(cc).reject(&:blank?))
    mail.deliver_now
    quote.update!(status: "sent", sent_at: Time.current, sent_to: Array(mail.to) + Array(mail.cc))

    {
      success: true, quote_number: quote.display_name, url: "/quotes/#{quote.id}",
      sent_to: quote.sent_to, attachments: mail.attachments.map(&:filename),
      message: "#{quote.display_name} emailed to #{quote.sent_to.join(', ')} with #{mail.attachments.size} attachment(s)."
    }
  rescue => e
    Rails.logger.error "[QuoteService] send!: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  # ---------------------------------------------------------------------------

  def self.resolve_part!(customer, item, created_parts)
    if item[:part_id].present?
      return Part.find(item[:part_id])
    end
    return nil if item[:part_number].blank?

    number = item[:part_number].to_s
    issue  = item[:part_issue].presence || "A"
    existing = Part.matching(customer_id: customer.id, part_number: number, part_issue: issue).first
    return existing if existing

    spec = (item[:part] || {}).to_h.transform_keys(&:to_s)
    raise Error, "#{number}-#{issue} is not in HAMS for #{customer.name}; supply part: { ... } to create it" if spec.blank?

    op_sel = spec["operation_selection"].to_h.transform_keys(&:to_s)
    raise Error, "#{number}-#{issue}: part.operation_selection.treatments is required (with operation_id and selected_jig_type)" if op_sel["treatments"].blank?
    raise Error, "#{number}-#{issue}: part.jigging_location is required — the shop wants jigging decided at quote time" if spec["jigging_location"].blank?
    op_sel["aerospace_defense"] = spec["aerospace_defense"] if spec.key?("aerospace_defense")

    part = Part.new(
      customer: customer,
      part_number: number, part_issue: issue,
      description: spec["description"], specification: spec["specification"],
      material: spec["material"], specified_thicknesses: spec["specified_thicknesses"],
      special_instructions: spec["special_instructions"],
      process_type: spec["process_type"].presence || "anodising",
      each_price: item[:unit_amount].to_f,
      customisation_data: {
        "operation_selection" => op_sel,
        # Where/how it hangs. Free text for now; surfaced on the part page
        # and route card once those learn about it.
        "jigging" => { "location" => spec["jigging_location"], "decided_at" => "quote" }
      }
    )
    unless part.save
      raise Error, "Part #{number}-#{issue} failed validation: #{part.errors.full_messages.join('; ')}"
    end
    created_parts << part
    part
  end
  private_class_method :resolve_part!

  def self.attach!(part, file)
    return if part.upload_file(file)
    raise Error, "Drawing #{file.original_filename} failed to attach to #{part.display_name}: #{part.errors.full_messages.join('; ')}"
  end
  private_class_method :attach!

  # Base64 attachments in the run, in upload order, as RequestFile objects.
  def self.request_files(request)
    files = []
    request.messages.each do |msg|
      content = msg["content"]
      next unless content.is_a?(Array)
      content.each do |block|
        source = block["source"]
        next unless source&.dig("type") == "base64" && source["data"].present?
        media = source["media_type"].to_s
        ext = { "application/pdf" => "pdf", "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }[media] or next
        tf = Tempfile.new(["drawing", ".#{ext}"], binmode: true)
        tf.write(Base64.decode64(source["data"])); tf.flush
        files << RequestFile.new("drawing_#{files.length + 1}.#{ext}", media, tf)
      end
    end
    files
  end
  private_class_method :request_files

  def self.find_customer(name)
    return nil if name.blank?
    clean = name.strip
    Organization.where("LOWER(name) = ?", clean.downcase).first ||
      Organization.where("name ILIKE ?", "#{clean}%").first ||
      Organization.where("name ILIKE ?", "%#{clean}%").order(Arel.sql("LENGTH(name)")).first
  end
  private_class_method :find_customer
end
