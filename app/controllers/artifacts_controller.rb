# app/controllers/artifacts_controller.rb
class ArtifactsController < ApplicationController
  def index
    # Load counts for all artifact types
    @transport_methods_count = TransportMethod.count
    @enabled_transport_methods_count = TransportMethod.enabled.count

    @specification_presets_count = SpecificationPreset.count
    @enabled_specification_presets_count = SpecificationPreset.enabled.count

    @additional_charge_presets_count = AdditionalChargePreset.count
    @enabled_additional_charge_presets_count = AdditionalChargePreset.enabled.count

    @total_buyers_count = Buyer.count
    @enabled_buyers_count = Buyer.where(enabled: true).count
    @customers_with_buyers_count = Organization.customers.joins(:buyers).distinct.count
  end
end
