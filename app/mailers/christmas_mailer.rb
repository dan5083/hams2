class ChristmasMailer < ApplicationMailer
  default from: 'noreply@hardanodising.co.uk'

  def season_greetings(buyer, first_name = nil)
    @buyer = buyer
    @organization = buyer.organization
    @first_name = first_name # Can be nil for company-only greetings

    mail(
      to: buyer.email,
      subject: "Season's Greetings from Hard Anodising"
    )
  end
end
