class ChristmasMailer < ApplicationMailer
  # Uses default from: "noreply@hams-2.co.uk" from ApplicationMailer

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
