class ImportRun < ApplicationRecord
  def self.loaded?(source:, kind:, path:)
    exists?(source:, kind: kind.to_s, file_name: File.basename(path), file_size: File.size(path))
  end

  def self.record!(source:, kind:, path:, counts:)
    create!(source:, kind: kind.to_s, file_name: File.basename(path), file_size: File.size(path), counts:)
  end
end
