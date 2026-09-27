# app/helpers/sections_helper.rb
module SectionsHelper
  # Thumbnail of the part's first drawing (Part#file_thumbnail_url, page 1
  # for PDFs), linking to the full preview in a new tab. Nothing when the
  # part has no previewable file, so the cell just collapses to the text.
  def part_thumb(part, width: 44)
    return if part.nil?
    idx = part.previewable_file_indexes.first
    return if idx.nil?
    thumb = part.file_thumbnail_url(idx, width: width)
    return if thumb.blank?
    link_to part.file_preview_url(idx), target: "_blank", rel: "noopener",
            class: "shrink-0 block rounded border border-gray-200 overflow-hidden bg-white hover:ring-2 hover:ring-blue-400",
            title: "#{part.file_display_name(idx)} — open drawing" do
      image_tag thumb, alt: "", loading: "lazy", width: width, height: (width * 1.35).round, class: "block"
    end
  end
end
