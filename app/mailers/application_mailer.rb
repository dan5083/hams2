class ApplicationMailer < ActionMailer::Base
  default from: "noreply@hams-2.co.uk"
  layout "mailer"

  private

  # Embedded as an inline (cid:) attachment because email clients block remote
  # images by default; views render it via attachments['logo.png'].url and
  # fall back to a text header when the attachment is absent.
  # (Moved up from OrderAcknowledgementMailer - delete it there.)
  def attach_inline_logo
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-with-company-name.png')
    attachments.inline['logo.png'] = File.read(logo_path) if File.exist?(logo_path)
  rescue StandardError => e
    Rails.logger.warn "#{self.class.name}: could not attach logo: #{e.message}"
  end
end
