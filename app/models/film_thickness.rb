# app/lib/film_thickness.rb
#
# Film thickness recording rules, shared by the process record and the
# release note.
#
# Paperless aero/defence parts record film thickness IN-LINE, as an OCV
# field on the operation where it is physically measured:
#   - anodic: the foil verification op that follows unjig, one Elcometer
#     set per batch (8 readings, or the MIL-PRF-8625F Type III NADCAP sample
#     plan when the WO spec calls for it)
#   - ENP:    the ENP op itself, six micrometer points A-F, start and finish
#             either side of the plating cycle
# The value stored in ocv_readings[batch][field] is the same JSON the
# release note form has always posted, so the RN snapshot builder and the
# CofC read one shape whether the readings were captured here or on the RN.
#
# Everything here is pure: no ActiveRecord, no I/O. WorksOrder calls it at
# sign-off; ReleaseNote calls it for form-captured (non-paperless) records.
module FilmThickness
  ANODIC_FIELD = "elcometer_readings".freeze  # foil verification op
  ENP_FIELD    = "enp_growth".freeze          # ENP op
  FIELDS       = [ANODIC_FIELD, ENP_FIELD].freeze

  ANODIC_READINGS_PER_BATCH = 8
  ENP_POINTS  = %w[A B C D E F].freeze
  MAX_MICRONS = 1000

  # ==========================================================================
  # NADCAP sample plan (MIL-PRF-8625F Type III hard anodise)
  # parts_per_batch -> sample size. Total readings for the batch is
  # max(8, sample_size), distributed as evenly as possible across the
  # sampled parts:
  #   - Lot 1  -> sample 1  -> 8 readings on the one part          (8 total)
  #   - Lot 6  -> sample 6  -> 2 parts x 2 readings, 4 parts x 1   (8 total)
  #   - Lot 32 -> sample 12 -> 1 reading per part                  (12 total)
  # ==========================================================================
  def self.nadcap_sample_size(parts_per_batch)
    n = parts_per_batch.to_i
    return 0 if n < 1
    return n if n <= 12
    return 12 if n <= 288
    return 16 if n <= 544
    return 20 if n <= 960
    return 24 if n <= 1632
    32
  end

  def self.nadcap_total_readings(parts_per_batch)
    ss = nadcap_sample_size(parts_per_batch)
    ss < 1 ? 0 : [ANODIC_READINGS_PER_BATCH, ss].max
  end

  # Per-part allocation, most heavily loaded parts first: lot 6 -> [2,2,1,1,1,1]
  def self.nadcap_readings_plan(parts_per_batch)
    ss = nadcap_sample_size(parts_per_batch)
    return [] if ss < 1
    total = [ANODIC_READINGS_PER_BATCH, ss].max
    base, extra = total.divmod(ss)
    Array.new(ss) { |i| base + (i < extra ? 1 : 0) }
  end

  # A works order spec triggers NADCAP sampling when it names "PRF" and
  # "III" as a whole token (so "IIIA" etc. do not false-positive).
  def self.nadcap_sampling_specification?(specification)
    spec = specification.to_s.upcase
    return false if spec.blank?
    spec.include?("PRF") && /\bIII\b/.match?(spec)
  end

  # ==========================================================================
  # Parsing - tolerant of the JSON strings the JS controllers post and of
  # already-parsed arrays/hashes.
  # ==========================================================================
  def self.parse(value)
    return value unless value.is_a?(String)
    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end

  # Numeric readings rounded to 1dp. Non-numeric entries dropped; sign kept
  # so a bad value is reported rather than silently vanishing.
  def self.readings_from(value)
    list = parse(value)
    list = [list] unless list.is_a?(Array)
    list.filter_map do |v|
      next nil if v.blank?
      (Float(v.to_s) * 10).round / 10.0
    rescue ArgumentError, TypeError
      nil
    end
  end

  # { 'parts_per_batch' => n, 'parts' => [{ 'part_label' => 'B1p1', 'readings' => [...] }] }
  def self.nadcap_from(value, parts_per_batch: nil)
    data = parse(value)
    data = {} unless data.is_a?(Hash)
    parts = (data["parts"] || []).each_with_index.map do |part, idx|
      {
        "part_label" => part["part_label"].presence || "p#{idx + 1}",
        "readings"   => readings_from(part["readings"] || [])
      }
    end
    {
      "parts_per_batch" => (parts_per_batch.presence || data["parts_per_batch"]).to_i,
      "parts"           => parts,
      "readings"        => parts.flat_map { |p| p["readings"] }
    }
  end

  # Per-works-order traceability (grouped bars for customers who want their
  # own 8 readings on their own release note - see
  # WorksOrder#thickness_per_works_order?):
  #   { 'mode' => 'per_wo', 'parts' => [{ 'wo' => 'WO1234', 'part_label' => 'WO1234 · P/N', 'readings' => [8] }] }
  PER_WO_MODE = "per_wo".freeze

  def self.per_wo?(value)
    data = parse(value)
    data.is_a?(Hash) && data["mode"].to_s == PER_WO_MODE
  end

  def self.per_wo_from(value)
    data = parse(value)
    data = {} unless data.is_a?(Hash)
    parts = (data["parts"] || []).map do |part|
      {
        "wo"         => part["wo"].to_s,
        "part_label" => part["part_label"].presence || part["wo"].to_s,
        "readings"   => readings_from(part["readings"] || [])
      }
    end
    { "mode" => PER_WO_MODE, "parts" => parts, "readings" => parts.flat_map { |p| p["readings"] } }
  end

  # Every expected works order present with a full 8-reading set.
  def self.per_wo_errors(data, expected_wos)
    parts = data["parts"] || []
    Array(expected_wos).flat_map do |wo|
      part = parts.find { |p| p["wo"] == wo }
      if part.nil? || part["readings"].empty?
        ["#{wo} has no readings"]
      else
        anodic_errors(part["readings"]).map { |e| "#{wo} #{e}" }
      end
    end
  end

  # [{ 'point' => 'A', 'start_mm' => 1.234, 'finish_mm' => 1.259, 'growth_um' => 25.0 }, ...]
  def self.enp_from(value)
    data = parse(value)
    return [] unless data.is_a?(Array)
    data.filter_map do |m|
      next nil unless m.is_a?(Hash) && ENP_POINTS.include?(m["point"].to_s)
      {
        "point"     => m["point"].to_s,
        "start_mm"  => m["start_mm"].presence&.to_f,
        "finish_mm" => m["finish_mm"].presence&.to_f,
        "growth_um" => m["growth_um"].presence&.to_f
      }
    end
  end

  # ==========================================================================
  # Rules - each returns an array of error strings with no batch/treatment
  # prefix; callers add context.
  # ==========================================================================
  def self.anodic_errors(readings)
    return ["thickness readings are required"] if readings.blank?
    errors = []
    unless readings.count % ANODIC_READINGS_PER_BATCH == 0
      errors << "requires a multiple of #{ANODIC_READINGS_PER_BATCH} readings (#{readings.count} provided)"
    end
    errors.concat(reading_value_errors(readings))
    errors
  end

  def self.nadcap_errors(data, parts_per_batch)
    ppb   = parts_per_batch.to_i
    parts = data["parts"] || []
    return ["requires 'Parts in this batch' (NADCAP sampling)"] if ppb < 1

    expected_size  = nadcap_sample_size(ppb)
    expected_plan  = nadcap_readings_plan(ppb)
    expected_total = nadcap_total_readings(ppb)

    if parts.count != expected_size
      return ["requires #{expected_size} sampled part(s) for a lot of #{ppb} (got #{parts.count})"]
    end

    # The plan is a multiset of per-part counts; any assignment is fine.
    actual = parts.map { |p| (p["readings"] || []).count }
    if actual.sort != expected_plan.sort
      breakdown = expected_plan.tally.sort_by { |c, _| -c }
                               .map { |c, n| "#{n} part(s) × #{c} reading(s)" }.join(" + ")
      return ["requires #{expected_total} readings for a lot of #{ppb}, distributed as #{breakdown} " \
              "(got #{actual.sum} readings across #{parts.count} part(s))"]
    end

    parts.flat_map do |part|
      reading_value_errors(part["readings"] || []).map { |e| "#{part['part_label']} #{e}" }
    end
  end

  def self.enp_errors(measurements)
    return ["ENP measurements are required"] if measurements.blank?
    errors = []
    measurements.each do |m|
      g = m["growth_um"]
      if g.nil?
        errors << "point #{m['point']} is incomplete"
      elsif g < 0
        errors << "point #{m['point']} has negative growth (#{g}µm)"
      elsif g > MAX_MICRONS
        errors << "point #{m['point']} seems unrealistically high (#{g}µm)"
      end
    end
    missing = ENP_POINTS - measurements.map { |m| m["point"] }
    errors << "requires all 6 measurement points (A-F)" if missing.any?
    errors
  end

  def self.reading_value_errors(readings)
    readings.each_with_index.filter_map do |r, i|
      if r <= 0
        "reading #{i + 1} must be greater than 0"
      elsif r > MAX_MICRONS
        "reading #{i + 1} seems unrealistically high (>#{MAX_MICRONS}µm)"
      end
    end
  end

  # ==========================================================================
  # Process record integration - operates on the frozen op hash shape
  # ==========================================================================

  # Which in-line thickness field this op carries, or nil.
  def self.field_for(op)
    fields = (op.dig("ocv", "fields") || []).map(&:to_s)
    FIELDS.find { |f| fields.include?(f) }
  end

  def self.thickness_op?(op)
    field_for(op).present?
  end

  # NADCAP sampling applies to the HARD anodise foil op on a PRF/Type III
  # WO - a chromic or standard anodise treatment on the same WO still takes
  # the plain 8-per-batch set. Mirrors ReleaseNote#get_required_treatments.
  def self.nadcap_for?(op, specification)
    nadcap_sampling_specification?(specification) &&
      op["id"].to_s.upcase.include?("HARD_ANODISING")
  end

  # Validate one batch's row at sign-off. parts_per_batch is the SECTION's
  # batch qty - the process record already knows the lot size, so NADCAP
  # sampling never asks for it twice.
  # per_wo: list of works order labels that must each carry 8 readings
  # (nil/empty = shared batch set). Takes precedence over nadcap.
  def self.row_errors(op, row, parts_per_batch: nil, nadcap: false, per_wo: nil)
    field = field_for(op)
    return [] unless field
    raw = row[field]
    return ["#{field.humanize} not recorded"] if raw.to_s.strip.empty?

    case field
    when ENP_FIELD
      enp_errors(enp_from(raw))
    when ANODIC_FIELD
      if per_wo.present?
        per_wo_errors(per_wo_from(raw), per_wo)
      elsif nadcap
        nadcap_errors(nadcap_from(raw, parts_per_batch: parts_per_batch), parts_per_batch)
      else
        anodic_errors(readings_from(raw))
      end
    end
  end

  # The batch hash ReleaseNote#measured_thicknesses stores - identical to
  # what the RN form produced, plus provenance.
  # `wo` - the release note's works order label; in per_wo mode only that
  # works order's set is returned, so its CofC carries its own 8 readings.
  def self.batch_from_row(op, row, batch_number, parts_per_batch: nil, nadcap: false, wo: nil)
    field = field_for(op)
    raw   = row[field]
    return nil if raw.to_s.strip.empty?

    base = { "batch_number" => batch_number.to_i, "source" => "process_record", "position" => op["position"] }
    case field
    when ENP_FIELD
      m = enp_from(raw)
      m.any? ? base.merge("enp_measurements" => m) : nil
    when ANODIC_FIELD
      if per_wo?(raw)
        data = per_wo_from(raw)
        part = wo ? data["parts"].find { |p| p["wo"] == wo } : nil
        return nil if part.nil? || part["readings"].empty?
        base.merge("readings" => part["readings"], "part_label" => part["part_label"], "traceability" => PER_WO_MODE)
      elsif nadcap
        base.merge(nadcap_from(raw, parts_per_batch: parts_per_batch))
      else
        r = readings_from(raw)
        r.any? ? base.merge("readings" => r) : nil
      end
    end
  end
end
