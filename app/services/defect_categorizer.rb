# Sorts defect phrases ("Nearside front coil spring fractured", "Remmen ongelijk") into DefectCategory
# slugs. Each unique phrase is sent once; the answer is saved on the phrase and reused for every
# defect that shares its wording.
#
# Uses Claude when ANTHROPIC_API_KEY is set, and keyword matching otherwise. A batch Claude declines
# to answer falls back to keywords too.
class DefectCategorizer
  BATCH_SIZE = 100
  MODEL = ENV.fetch("CURB_CATEGORIZER_MODEL", "claude-sonnet-5-5")
  FALLBACK_SLUG = "other"

  def self.ai_available? = Claude.available?

  def initialize(categories: DefectCategory.order(:name).to_a, client: nil, use_ai: self.class.ai_available?)
    @categories = categories
    @by_slug = categories.index_by(&:slug)
    @client = client
    @use_ai = use_ai
  end

  # Categorizes the phrases in place and returns how many were saved.
  def categorize(phrases)
    phrases.each_slice(BATCH_SIZE).sum do |batch|
      slugs, method = @use_ai ? [ ask_claude(batch), "ai" ] : [ {}, "keyword" ]
      save(batch, slugs, method)
    end
  end

  private
    def save(batch, slugs, method)
      now = Time.current
      batch.each do |phrase|
        category = @by_slug[slugs[phrase.id]]
        by = category ? method : "keyword"
        category ||= DefectCategory.match(phrase.text, @categories) || @by_slug[FALLBACK_SLUG]
        phrase.update_columns(defect_category_id: category&.id, categorized_by: by, categorized_at: now, updated_at: now)
      end
      batch.size
    end

    # { phrase_id => slug }. Empty when Claude declines, so the batch falls back to keywords.
    def ask_claude(batch)
      message = client.messages.create(
        model: MODEL,
        max_tokens: 16_000,
        output_config: { effort: :low, format_: { type: :json_schema, schema: } },
        system_: instructions,
        messages: [ { role: "user", content: batch.map { |phrase| { id: phrase.id, text: phrase.text } }.to_json } ]
      )
      return {} unless message.stop_reason == :end_turn

      text = message.content.find { |block| block.type == :text }&.text
      JSON.parse(text.to_s).fetch("results", []).to_h { |row| [ row["id"], row["category"] ] }
    rescue JSON::ParserError
      {}
    end

    def client
      @client ||= Claude.client
    end

    def instructions
      @instructions ||= <<~TEXT
        You sort car inspection defect descriptions into component categories. The descriptions come from
        UK MOT tests (English) and Dutch APK inspections (Dutch). The categories feed a used-car repair cost
        estimate, so pick the component that would need repairing or replacing, not where it was noticed.

        Categories (slug: name - what belongs there):
        #{@categories.map { |category| "- #{category.slug}: #{category.name} - #{category.description}" }.join("\n")}

        The user sends a JSON array of {id, text}. Return one result per id with the best category slug.
        Use "#{FALLBACK_SLUG}" only when no other category fits.
      TEXT
    end

    def schema
      {
        type: "object",
        properties: {
          results: {
            type: "array",
            items: {
              type: "object",
              properties: { id: { type: "integer" }, category: { type: "string", enum: @categories.map(&:slug) } },
              required: %w[id category],
              additionalProperties: false
            }
          }
        },
        required: %w[results],
        additionalProperties: false
      }
    end
end
