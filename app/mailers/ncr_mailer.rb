# app/mailers/ncr_mailer.rb
class NcrMailer < ApplicationMailer
  NCR_NOTIFICATION_RECIPIENTS = %w[
    phil@hardanodisingstl.com
    quality@hardanodisingstl.com
    chris@hardanodisingstl.com
    tariq@hardanodisingstl.com
  ].freeze

  def draft_created(external_ncr)
    @external_ncr = external_ncr
    @creator      = external_ncr.created_by
    @ncr_url      = external_ncr_url(external_ncr)

    mail(
      to:      NCR_NOTIFICATION_RECIPIENTS,
      subject: "New External NCR #{external_ncr.display_name} received – #{external_ncr.customer_name}"
    )
  end
end
