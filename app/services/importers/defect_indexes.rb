module Importers
  # Loading tens of millions of defects is several times faster without the table's secondary
  # indexes and foreign keys, which are then rebuilt in one pass each.
  module DefectIndexes
    INDEXES = {
      "index_defects_on_inspection_id" => "inspection_id",
      "index_defects_on_defect_phrase_id" => "defect_phrase_id"
    }.freeze
    FOREIGN_KEYS = { inspection_id: :inspections, defect_phrase_id: :defect_phrases }.freeze

    module_function

    def without_indexes(connection: ActiveRecord::Base.connection)
      drop(connection)
      yield
    ensure
      restore(connection)
    end

    def drop(connection)
      INDEXES.each_key { |name| connection.execute("DROP INDEX IF EXISTS #{name}") }
      FOREIGN_KEYS.each do |column, table|
        connection.remove_foreign_key(:defects, table, column:) if connection.foreign_key_exists?(:defects, table, column:)
      end
    end

    def restore(connection)
      connection.execute("SET maintenance_work_mem = #{connection.quote("1GB")}")
      INDEXES.each { |name, column| connection.execute("CREATE INDEX IF NOT EXISTS #{name} ON defects (#{column})") }
      FOREIGN_KEYS.each do |column, table|
        next if connection.foreign_key_exists?(:defects, table, column:)
        connection.add_foreign_key(:defects, table, column:, validate: false)
        connection.validate_foreign_key(:defects, table, column:)
      end
      connection.execute("ANALYZE defects")
    end
  end
end
