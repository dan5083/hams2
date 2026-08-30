# app/helpers/film_thickness_helper.rb
#
# View-side support for the in-line film thickness fields on the paperless
# process record (FilmThickness::ANODIC_FIELD on foil verification ops,
# FilmThickness::ENP_FIELD on ENP ops).
module FilmThicknessHelper
  # One-line summary of a stored thickness value for the drift line and the
  # locked (signed) row: "8 readings · mean 70.4 µm" / "6 pts · mean 25.1 µm".
  def film_thickness_summary(field, raw)
    return "—" if raw.to_s.strip.empty?
    case field.to_s
    when FilmThickness::ENP_FIELD
      growths = FilmThickness.enp_from(raw).map { |m| m["growth_um"] }.compact
      return "—" if growths.empty?
      "#{growths.size} pts · mean #{(growths.sum / growths.size).round(1)} µm"
    when FilmThickness::ANODIC_FIELD
      parsed = FilmThickness.parse(raw)
      readings = parsed.is_a?(Hash) ? FilmThickness.nadcap_from(parsed)["readings"] : FilmThickness.readings_from(parsed)
      return "—" if readings.empty?
      "#{readings.size} readings · mean #{(readings.sum / readings.size).round(1)} µm (#{readings.min}–#{readings.max})"
    else
      raw.to_s
    end
  end

  # Target film thickness for a thickness op: the foil op carries none, so
  # take it from the nearest preceding op that does (the anodise op of the
  # same treatment cycle). ENP ops carry their own via target_thickness or
  # nothing (target lives on the treatment).
  def film_thickness_target_for(ops, op)
    own = op["target_thickness"].to_f
    return own if own > 0
    preceding = ops.select { |o| o["position"].to_i < op["position"].to_i && o["target_thickness"].to_f > 0 }
    preceding.max_by { |o| o["position"].to_i }&.dig("target_thickness").to_f
  end

  # Short display label for the banner / sink label.
  def film_thickness_display_name(ops, op)
    if FilmThickness.field_for(op) == FilmThickness::ENP_FIELD
      op["display_name"].presence || "ENP"
    else
      preceding = ops.select { |o| o["position"].to_i < op["position"].to_i && o["process_type"].to_s.include?("anodis") }
      preceding.max_by { |o| o["position"].to_i }&.dig("process_type").to_s.humanize.presence || "Anodic"
    end
  end
end
