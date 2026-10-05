# Rebuilds the defect-rate materialized views after new inspections or categories land.
class RefreshDefectRatesJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "refresh_defect_rates"

  def perform
    DefectRate.refresh_all!
  end
end
