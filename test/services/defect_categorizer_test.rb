require "test_helper"

class DefectCategorizerTest < ActiveSupport::TestCase
  FakeBlock = Struct.new(:type, :text)
  FakeMessage = Struct.new(:stop_reason, :content)

  # Stands in for Anthropic::Client, answering with a fixed { phrase_id => slug } map.
  class FakeClient
    attr_reader :requests

    def initialize(answers, stop_reason: :end_turn)
      @answers = answers
      @stop_reason = stop_reason
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      results = @answers.map { |id, slug| { id:, category: slug } }
      FakeMessage.new(@stop_reason, [ FakeBlock.new(:text, { results: }.to_json) ])
    end
  end

  setup do
    load_reference_data
    @spring = DefectPhrase.create!(source: "mot", external_id: "1", text: "Coil spring fractured")
    @odd = DefectPhrase.create!(source: "mot", external_id: "2", text: "Remmen ongelijk werkend")
    @unknown = DefectPhrase.create!(source: "mot", external_id: "3", text: "Something unusual")
  end

  test "keyword matching picks the longest matching keyword" do
    DefectCategorizer.new(use_ai: false).categorize([ @spring, @unknown ])

    assert_equal "springs", @spring.reload.defect_category.slug
    assert_equal "keyword", @spring.categorized_by
    assert_equal "other", @unknown.reload.defect_category.slug
  end

  test "uses Claude's answers and asks for the category list as a JSON schema" do
    client = FakeClient.new({ @spring.id => "springs", @odd.id => "brake-hydraulics", @unknown.id => "other" })
    DefectCategorizer.new(client:, use_ai: true).categorize([ @spring, @odd, @unknown ])

    assert_equal "brake-hydraulics", @odd.reload.defect_category.slug
    assert_equal "ai", @odd.categorized_by
    schema = client.requests.first.dig(:output_config, :format_, :schema)
    assert_includes schema.dig(:properties, :results, :items, :properties, :category, :enum), "springs"
  end

  test "falls back to keywords for anything Claude leaves out" do
    client = FakeClient.new({ @odd.id => "brake-hydraulics" })
    DefectCategorizer.new(client:, use_ai: true).categorize([ @spring, @odd ])

    assert_equal "springs", @spring.reload.defect_category.slug
    assert_equal "keyword", @spring.categorized_by
  end

  test "falls back to keywords when Claude declines the batch" do
    client = FakeClient.new({ @spring.id => "engine" }, stop_reason: :refusal)
    DefectCategorizer.new(client:, use_ai: true).categorize([ @spring ])

    assert_equal "springs", @spring.reload.defect_category.slug
  end
end

class CategorizeDefectPhrasesJobTest < ActiveJob::TestCase
  test "leaves codes with no wording for later" do
    Curb::ReferenceData.load!
    code = DefectPhrase.create!(source: "mot", external_id: "31361", text: "MOT item 31361")
    named = DefectPhrase.create!(source: "mot", external_id: "1", text: "Coil spring fractured")

    CategorizeDefectPhrasesJob.perform_now(refresh: false)

    assert_nil code.reload.categorized_at
    assert_equal "springs", named.reload.defect_category.slug
  end
end
