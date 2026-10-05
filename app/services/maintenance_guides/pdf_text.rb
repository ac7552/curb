module MaintenanceGuides
  # The schedule pages of a maintenance guide as plain text. Guides often print two checklists side by
  # side ("5,000 miles" | "10,000 miles"), and plain extraction interleaves their lines, so each half of
  # the page is read as its own column.
  #
  # Uses the pdf-reader gem, which is only in the development bundle: guides are read on a developer's
  # machine (bin/rails curb:guides:extract), never on the server.
  class PdfText
    Page = Data.define(:number, :columns) do
      def text = columns.join("\n\n")
    end

    # A page is part of the schedule when it names mileages to service at.
    SCHEDULE_PAGE = /maintenance (log|schedule)|\d{1,3},000 (miles|mi)\b.*\b(months|mos)\b/i
    MILEAGE = /\b\d{1,3},000\s*(miles|mi)\b/i

    def initialize(path)
      PdfSpacingFix.apply
      @reader = PDF::Reader.new(path.to_s)
    end

    def page_count = @reader.page_count

    # Every page's plain text, in order. Kept, since each way of reading a guide looks at it, and pulling
    # text out of a 1,500-page manual takes a while.
    def page_texts = @page_texts ||= @reader.pages.map(&:text)

    # Owner's manuals mention mileages in many places (tires, warranty, break-in), so when more pages match
    # than a schedule could fill, only the ones that look most like a schedule are kept, in page order.
    MAX_PAGES = 24
    QUICK_HINT = /\d{1,3},\d{3}\s*mi|maintenance\s*(log|schedule)|scheduled\s*maintenance|rotate\s*tires/i
    SCHEDULE_HEADING = /maintenance (log|schedule|items|intervals)|scheduled maintenance|service schedule|maintenance service/i

    def schedule_pages
      pages = @reader.pages.each_with_index.filter_map do |page, index|
        # Quick check first: building words letter by letter is slow on a long manual. The plain text can run
        # words together ("30,000milesor36months") or, on a cropped page, leave headings out altogether, so
        # this lets through anything that looks like maintenance.
        next unless page_texts[index].match?(QUICK_HINT)
        left, _, right, = page.attributes[:CropBox] || page.attributes[:MediaBox] || [ 0, 0, page.width ]
        columns = self.class.columns(self.class.phrases(self.class.words(page.runs(merge: false))), right - left, left:)
        text = columns.join("\n\n")
        Page.new(number: index + 1, columns:) if text.match?(SCHEDULE_PAGE) && text.scan(MILEAGE).size >= 1 && !warranty_page?(text)
      end
      self.class.most_schedule_like(pages)
    end

    def self.most_schedule_like(pages, max: MAX_PAGES)
      return pages if pages.size <= max
      pages.max_by(max) { |page| [ schedule_score(page.text), -page.number ] }.sort_by(&:number)
    end

    def self.schedule_score(text) = text.scan(MILEAGE).size + (text.match?(SCHEDULE_HEADING) ? 10 : 0)

    Word = Data.define(:x, :y, :text, :width, :font_size)

    # Words with their place on the page, built from single characters by the gaps between them. Some
    # guides draw no spaces (Lexus: "Rotatetires"), and some put several marks spaced with tabs in one
    # run (Subaru), so neither the PDF's spaces nor its runs can be trusted to split words.
    def self.words(chars)
      chars.sort_by { [ -_1.y.round, _1.x ] }.chunk_while { |a, b| (a.y - b.y).abs <= 1 }.flat_map do |line|
        line.sort_by(&:x).slice_when { |a, b| b.x - (a.x + a.width) > a.font_size * 0.15 || a.text.match?(/\s/) || b.text.match?(/\s/) }
            .filter_map do |chars|
              text = chars.map(&:text).join.gsub(/[[:cntrl:]\s]/, "")
              Word.new(x: chars.first.x, y: chars.first.y, text:, width: chars.last.x + chars.last.width - chars.first.x,
                       font_size: chars.first.font_size) unless text.empty?
            end
      end
    end

    # Words joined into phrases where they're only a space apart, so a heading that crosses the middle of
    # the page ("30,000 miles or 36 months") stays in one column.
    def self.phrases(words)
      words.chunk_while { |a, b| (a.y - b.y).abs <= 1 && b.x > a.x }.flat_map do |line|
        line.slice_when { |a, b| b.x - (a.x + a.width) > a.font_size * 1.2 }.map do |phrase|
          Word.new(x: phrase.first.x, y: phrase.first.y, text: phrase.map(&:text).join(" "),
                   width: phrase.last.x + phrase.last.width - phrase.first.x, font_size: phrase.first.font_size)
        end
      end
    end

    # Text runs (anything with x, y and text) as the page's left and right halves, each top to bottom.
    # Halves of the visible page: some guides crop a larger sheet, which moves the middle (left is where
    # the visible page starts).
    def self.columns(runs, width, left: 0)
      runs.partition { |run| run.x < left + width / 2.0 }.map do |column|
        column.group_by { |run| (run.y / 3.0).round }.sort_by { |y, _| -y }
              .map { |_, line| line.sort_by(&:x).map(&:text).join(" ").squish }
              .reject { |line| line.match?(/\A\d?\z/) } # stray footnote markers
              .join("\n")
      end.reject(&:blank?)
    end

    private
      # Warranty pages mention mileages too ("36,000 miles"), but they're coverage, not service.
      def warranty_page?(text) = text.match?(/\bWARRANTY\b/) && !text.match?(/maintenance (log|schedule)/i)
  end
end
