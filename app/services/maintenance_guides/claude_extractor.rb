module MaintenanceGuides
  # Reads a guide's schedule pages with Claude, for the guides the plain rules (RuleExtractor) can't. One
  # request carries every schedule page (about 10,000 tokens for a typical guide, a few cents), and Claude
  # names the page each item is on, so Intervals.from_pages merges them the same way as any page-by-page
  # reading. The Validator then checks the result like every other reading.
  class ClaudeExtractor
    class Error < StandardError; end
    # No key, or Claude can't be reached: every guide would fail the same way, so batches stop.
    class Unavailable < Error; end

    MODEL = ENV.fetch("CURB_GUIDE_MODEL", "claude-sonnet-5-5")
    MAX_TOKENS = 16_000

    INTERVAL = { type: [ "integer", "null" ] }.freeze

    SCHEMA = {
      type: "object", additionalProperties: false, required: %w[items],
      properties: {
        items: {
          type: "array",
          items: {
            type: "object", additionalProperties: false,
            required: %w[page name action interval_miles interval_months first_due_miles conditions applies_to],
            properties: {
              page: { type: "integer" }, name: { type: "string" },
              action: { type: "string", enum: %w[replace rotate inspect other] },
              interval_miles: INTERVAL, interval_months: INTERVAL, first_due_miles: INTERVAL,
              conditions: { type: "string", enum: %w[normal special] }, applies_to: { type: [ "string", "null" ] }
            }
          }
        }
      }
    }.freeze

    INSTRUCTIONS = <<~PROMPT.freeze
      You read car makers' maintenance schedules. The user sends the schedule pages of one maker's guide,
      each starting with "=== Page N ===". List each maintenance item that has a stated interval, once per
      page it appears on:

      - page: the N of the page it's on.
      - name: the item's own name as written in its row or sentence, for example "Engine oil & oil filter".
        Never use a note, footnote or heading as a name.
      - action: replace, rotate, inspect, or other. In tables, "R" means replace and "I" means inspect.
      - interval_miles / interval_months: how often it is done, as stated ("every 30,000 miles or 24 months").
        For a table of mileages with marks, it is the gap between the marked mileages. Take months only from
        months the guide states; numbers in brackets beside miles are usually kilometers, not months.
      - first_due_miles: the first time it is due, if different from the interval. Otherwise null.
      - conditions: "normal" for the regular schedule; "special" for severe or special operating conditions
        (towing, dusty roads, short trips, extreme temperatures).
      - applies_to: any limit written with it, such as "AWD", "2.5L engine" or "if equipped". Otherwise null.

      Use only what the pages say; if an interval isn't stated, use null. If there's no schedule, return an
      empty list.
    PROMPT

    def initialize(client: nil)
      @client = client
    end

    # pages: [PdfText::Page]; guide: which car, so a booklet covering every model is read for the right one.
    # Returns { "items" => [...] } in the shape the Validator checks, with what each page was read as, and
    # timing and token counts.
    def extract(pages, guide: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      message = ask(pages, guide)
      found = parse(message).group_by { _1.delete("page") }
      readings = pages.map { |page| [ page, found.fetch(page.number, []) ] }

      {
        "items" => Intervals.from_pages(readings), "layout" => "page_items", "model" => MODEL,
        "checklists" => readings.map { |page, items| { "page" => page.number, "items" => items } },
        "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round,
        "prompt_tokens" => message.usage.input_tokens, "output_tokens" => message.usage.output_tokens
      }
    end

    private
      def ask(pages, guide)
        client.messages.create(
          model: MODEL, max_tokens: MAX_TOKENS,
          output_config: { effort: :medium, format_: { type: :json_schema, schema: SCHEMA } },
          system_: INSTRUCTIONS,
          messages: [ { role: "user", content: car_line(guide) + pages.map { "=== Page #{_1.number} ===\n#{_1.text}" }.join("\n\n") } ]
        )
      rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError, Anthropic::Errors::APIConnectionError => e
        raise Unavailable, "Claude isn't reachable with this key: #{e.message}"
      rescue Anthropic::Errors::APIError => e
        raise Error, "Claude couldn't read the guide: #{e.message}"
      end

      def parse(message)
        raise Error, "Claude stopped early (#{message.stop_reason})" unless message.stop_reason == :end_turn
        text = message.content.find { _1.type == :text }&.text
        JSON.parse(text.to_s).fetch("items")
      rescue JSON::ParserError, KeyError => e
        raise Error, "Claude's answer wasn't a schedule: #{e.message}"
      end

      def car_line(guide)
        return "" unless guide
        line = "These pages are from the guide for the #{guide.model_year} #{guide.make} #{guide.model}."
        line += " The booklet covers several models: only list items for the #{guide.model}, or for all models." if guide.kind == :all_models_booklet
        "#{line}\n\n"
      end

      def client
        raise Unavailable, "No Claude API key set (ANTHROPIC_API_KEY or credentials.anthropic_api_key)" unless @client || Claude.available?
        @client ||= Claude.client
      end
  end
end
