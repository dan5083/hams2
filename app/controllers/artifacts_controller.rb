# app/controllers/artifacts_controller.rb
class ArtifactsController < ApplicationController
  def index
    # Load counts for what users can actually manage here
    @release_levels_count = ReleaseLevel.count
    @enabled_release_levels_count = ReleaseLevel.enabled.count

    @transport_methods_count = TransportMethod.count
    @enabled_transport_methods_count = TransportMethod.enabled.count
  end
end
