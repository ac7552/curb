module MaintenanceGuides
  module Rules
    # The jobs to replace or rotate in one mileage checklist (Toyota, Lexus), read with plain rules: each
    # "Replace …" or "Rotate …" line, joined with any line it wraps onto. Checked against Gemma's readings of
    # 62 Toyota guides: the same answer for 59, and right where they differed (Gemma counted items under
    # "Inspect the following:" as replacements).
    module ChecklistItems
      module_function

      BULLET = /\A[^\p{L}\p{N}(]*/ # any symbols before the words: ■, ❑, ❏, _, •

      def from(text)
        joined(text).filter_map do |line|
          next unless line.match?(/\A(Replace|Rotate)\b/)
          next if line.match?(/\bif\b|inspect/i) # conditional work and inspections aren't the normal schedule

          name = line.sub(/\s+\d+\z/, "") # a footnote number after the name
          { "name" => name, "action" => name.start_with?("Rotate") ? "rotate" : "replace",
            "applies_to" => name[/\(([^)]*(?:only|equipped|models?|engine)[^)]*)\)/i, 1] }
        end
      end

      # Lines with wrapped ones joined back on. A line with no bullet that starts in lower case or with "("
      # continues the one before it ("Replace spark plugs" / "(2GR-FKS engine only)").
      def joined(text)
        text.lines.map { _1.gsub(/[[:cntrl:]]/, " ").strip }.reject(&:empty?).each_with_object([]) do |raw, out|
          line = raw.sub(BULLET, "").sub(/\A([A-Z]) (?=[a-z])/, '\1') # "R eplace": a gap after a capital
          if out.any? && raw == raw.sub(BULLET, "") && line.match?(/\A[a-z(]/)
            out[-1] = "#{out[-1]} #{line}"
          else
            out << line
          end
        end
      end
    end
  end
end
