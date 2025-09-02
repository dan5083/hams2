# app/controllers/artifacts_controller.rb
class ArtifactsController < ApplicationController
  def index
    # Load counts for all artifact types
    @release_levels_count = ReleaseLevel.count
    @enabled_release_levels_count = ReleaseLevel.enabled.count

    @transport_methods_count = TransportMethod.count
    @enabled_transport_methods_count = TransportMethod.enabled.count

    @specification_presets_count = SpecificationPreset.count
    @enabled_specification_presets_count = SpecificationPreset.enabled.count

    @additional_charge_presets_count = AdditionalChargePreset.count
    @enabled_additional_charge_presets_count = AdditionalChargePreset.enabled.count
  end
end
