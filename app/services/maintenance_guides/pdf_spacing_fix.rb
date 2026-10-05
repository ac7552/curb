module MaintenanceGuides
  # Subaru's booklet draws the gaps in its schedule grid as spaces stretched by word spacing, and tags each
  # with ActualText saying it's a tab. pdf-reader 2.16 then takes the glyph for a tab rather than a space,
  # skips the word spacing (PDF 32000-1, 9.3.3 applies it to every single-byte space), and squeezes the
  # grid's marks into the wrong columns. Ignoring ActualText that's only whitespace keeps the real spaces.
  # Applied when a guide is read (pdf-reader is only in the development bundle).
  module PdfSpacingFix
    def self.apply
      require "pdf-reader"
      PDF::Reader::PageTextReceiver.prepend(self) unless PDF::Reader::PageTextReceiver <= self
      true
    end

    def begin_marked_content_with_pl(tag, properties)
      text = properties.is_a?(Hash) && properties[:ActualText]
      return if text && PDF::Reader::EncodingUtils.string_to_utf8(text).match?(/\A\s*\z/)
      super
    end
  end
end
