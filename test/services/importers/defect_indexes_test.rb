require "test_helper"

class Importers::DefectIndexesTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "drops the indexes and keys for the load and puts them back, even if the load fails" do
    connection = ActiveRecord::Base.connection

    assert_raises(RuntimeError) do
      Importers::DefectIndexes.without_indexes do
        assert_not connection.index_exists?(:defects, :inspection_id)
        assert_not connection.foreign_key_exists?(:defects, :inspections)
        raise "load failed"
      end
    end

    assert connection.index_exists?(:defects, :inspection_id, name: "index_defects_on_inspection_id")
    assert connection.index_exists?(:defects, :defect_phrase_id)
    assert connection.foreign_key_exists?(:defects, :inspections, column: :inspection_id)
    assert connection.foreign_key_exists?(:defects, :defect_phrases, column: :defect_phrase_id)
  end
end
