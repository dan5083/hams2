# app/helpers/sections_helper.rb
module SectionsHelper
  # Thumbnail of the part's designated file (Part#thumbnail_file_index - the
  # last previewable upload; page 1 for PDFs), linking to the full preview
  # in a new tab. Nothing when the part has no previewable file, so the
  # cell just collapses to the text.
  def part_thumb(part, width: 44)
    return if part.nil?
    idx = part.thumbnail_file_index
    return if idx.nil?
    thumb = part.file_thumbnail_url(idx, width: width)
    return if thumb.blank?
    link_to part.file_preview_url(idx), target: "_blank", rel: "noopener",
            class: "shrink-0 block rounded border border-gray-200 overflow-hidden bg-white hover:ring-2 hover:ring-blue-400",
            title: "#{part.file_display_name(idx)} — open drawing" do
      image_tag thumb, alt: "", loading: "lazy", width: width, height: (width * 1.35).round, class: "block"
    end
  end

  # "⚡ Lacquer — fast track" for jobs carrying stopping-off lacquer.
  def fast_track_pill(job)
    return unless job.lacquered?
    content_tag :span, "⚡ Lacquer — fast track",
      class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold whitespace-nowrap bg-fuchsia-600 text-white",
      title: "Stopping-off lacquer on this job: jumps the queue on every board"
  end

  # Every pill a board row carries under the WO number: fast track first,
  # then the promise. Nothing when the job has neither.
  def job_pills(job)
    pills = [fast_track_pill(job), promise_pill(job.promise)].compact
    return if pills.empty?
    content_tag :div, safe_join(pills, " "), class: "mt-1 flex flex-wrap gap-1"
  end

  # Row tint: lacquer beats the promise colour, since it sorts above it.
  def board_row_class(job)
    job.lacquered? ? "bg-fuchsia-50" : promise_row_class(job.promise)
  end

  # Dye pill coloured for the dye. Matched on the label text ("Black dye
  # for 25-30 minutes"); anything unrecognised falls back to purple.
  DYE_PILL_CLASSES = [
    [/\bblack\b/i, "bg-gray-900 text-white"],
    [/\bred\b/i,   "bg-red-600 text-white"],
    [/\bgreen\b/i, "bg-green-600 text-white"],
    [/\bgold\b/i,  "bg-yellow-400 text-yellow-950"],
    [/\bblue\b/i,  "bg-blue-600 text-white"],
  ].freeze

  def dye_pill(label)
    return content_tag(:span, "—", class: "text-gray-400") if label.blank?
    klass = DYE_PILL_CLASSES.find { |re, _| label.match?(re) }&.last || "bg-purple-100 text-purple-800"
    content_tag :span, label, class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold whitespace-nowrap #{klass}"
  end
end
