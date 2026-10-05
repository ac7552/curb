require "test_helper"
require "csv"

class Importers::MotBulkTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    write "test_result.csv", Importers::MotBulk::COLUMNS[:results], [
      [ 1, 10, "2023-03-01", 4, "NT", "F", 61_000, "SW", "VOLKSWAGEN", "GOLF GTI", "RED", "PE", 1395, "2015-02-01" ],
      [ 2, 10, "2024-03-01", 4, "NT", "P", 70_500, "SW", "VOLKSWAGEN", "GOLF GTI", "RED", "PE", 1395, "2015-02-01" ],
      [ 3, 20, "2024-05-01", 4, "NT", "PRS", 40_000, "M", "BMW", "3 SERIES 320D", "BLUE", "DI", 1995, "2017-06-01" ],
      [ 4, 30, "2024-05-01", 7, "NT", "P", 40_000, "M", "FORD", "TRANSIT", "WHITE", "DI", 2198, "2017-06-01" ],
      [ 5, 20, "2024-05-02", 4, "RT", "P", 40_010, "M", "BMW", "3 SERIES 320D", "BLUE", "DI", 1995, "2017-06-01" ]
    ]
    write "test_item.csv", Importers::MotBulk::COLUMNS[:items], [
      [ 1, 501, "F", nil, "D" ], [ 1, 502, "A", nil, nil ], [ 3, 501, "P", nil, nil ], [ 4, 502, "F", nil, nil ]
    ]
    write "item_detail.csv", Importers::MotBulk::COLUMNS[:details], [
      [ 501, 4, nil, "N", "Coil spring fractured", nil, nil, nil, nil ],
      [ 502, 4, nil, "N", nil, nil, nil, "Tyre worn close to legal limit", nil ]
    ]
  end

  teardown { FileUtils.rm_rf(@dir) }

  def write(name, header, rows, col_sep: "|")
    CSV.open(@dir.join(name), "w", col_sep:) { |csv| ([ header ] + rows).each { |row| csv << row } }
  end

  def import
    Importers::MotBulk.new(results: @dir.join("test_result.csv").to_s, items: @dir.join("test_item.csv").to_s,
                           details: @dir.join("item_detail.csv").to_s).call
  end

  test "loads car tests and skips other vehicle classes and retests" do
    summary = import

    assert_equal 3, summary.files
    assert_equal 2, summary.vehicles
    assert_equal 3, summary.inspections
    assert_equal 3, summary.defects
    assert_equal %w[fail pass pass_after_repair], Inspection.order(:external_id).pluck(:result)
  end

  test "normalizes names in SQL the same way VehicleName does in Ruby" do
    import
    golf = Vehicle.find_by!(external_id: "10")
    bmw = Vehicle.find_by!(external_id: "20")

    assert_equal [ VehicleName.make_key("VOLKSWAGEN"), VehicleName.model_key("GOLF GTI"), VehicleName.engine_key(cc: 1395, fuel: "PE") ],
                 [ golf.make_key, golf.model_key, golf.engine_key ]
    assert_equal [ "BMW", "3 SERIES", "2.0-D" ], [ bmw.make_key, bmw.model_key, bmw.engine_key ]
  end

  test "names phrases from the detail file and records fail or advisory" do
    import

    assert_equal [ "Coil spring fractured", "Tyre worn close to legal limit" ], DefectPhrase.order(:external_id).pluck(:text)
    assert_equal({ "fail" => 2, "advisory" => 1 }, Defect.group(:kind).count)
    assert_equal 1, Defect.where(severity: "dangerous").count
  end

  test "re-running the same files skips them" do
    import
    summary = import

    assert_equal 3, summary.skipped
    assert_equal 0, summary.files
    assert_equal 3, Defect.count
  end

  test "reads the 2023+ comma layout, with completed_date, extra columns and repeated headers" do
    write "results_2024.csv", %w[test_id vehicle_id test_class_id test_type test_result test_mileage postcode_area make model colour fuel_type cylinder_capacity first_use_date completed_date], [
      [ 1479190053, 77, 4, "NT", "F", 88_120, "B", "FORD", "FOCUS", "BLUE", "PE", 998, "2016-05-20", "2024-01-01T11:59:33.000Z" ]
    ], col_sep: ","
    write "items_2024.csv", %w[test_id rfr_id rfr_type_code mot_test_rfr_location_type_id dangerous_mark completed_date], [
      [ 1479190053, 31361, "A", 9, nil, "2024-01-01T11:59:33.000Z" ],
      %w[test_id rfr_id rfr_type_code mot_test_rfr_location_type_id dangerous_mark completed_date],
      [ 1479190053, 32017, "P", 25, nil, "2024-01-01T11:59:33.000Z" ]
    ], col_sep: ","

    summary = Importers::MotBulk.new(results: @dir.join("results_2024.csv").to_s, items: @dir.join("items_2024.csv").to_s).call

    assert_equal [ 1, 1, 2 ], [ summary.vehicles, summary.inspections, summary.defects ]
    inspection = Inspection.last
    assert_equal [ Date.new(2024, 1, 1), 88_120 ], [ inspection.inspected_on, inspection.mileage ]
    assert_equal "1.0-P", inspection.vehicle.engine_key
  end

  test "names defects with the part from item_group and the inspector's full sentence" do
    write "item_detail_2024.csv", %w[rfr_id test_class_id test_item_id minor_item rfr_deficiency_category rfr_desc rfr_loc_marker rfr_insp_manual_desc rfr_advisory_text test_item_set_section_id], [
      [ 31361, 4, 20269, "N", "Major", "corroded and seriously weakened", "Y", "A suspension component excessively damaged or corroded", "corroded but not seriously weakened", 20218 ],
      [ 31361, 7, 20269, "N", "Major", "corroded and seriously weakened", "Y", "Something for vans", nil, 20218 ]
    ]
    write "item_group.csv", %w[test_item_id test_class_id parent_id test_item_set_section_id item_name], [
      [ 20269, 4, 20218, 20218, "Suspension component" ], [ 20269, 7, 20218, 20218, "Van suspension" ]
    ]
    Importers::MotBulk.new(details: @dir.join("item_detail_2024.csv").to_s, groups: @dir.join("item_group.csv").to_s).call

    phrase = DefectPhrase.find_by!(external_id: "31361")
    assert_equal "Suspension component: A suspension component excessively damaged or corroded", phrase.text
    load_reference_data
    DefectCategorizer.new(use_ai: false).categorize([ phrase ])
    assert_equal "suspension", phrase.reload.defect_category.slug
  end

  test "handles DVSA's backslash-escaped quotes and bare quotes in pipe files" do
    File.write(@dir.join("results_quotes.csv"), <<~'CSV')
      test_id,vehicle_id,test_date,test_class_id,test_type,test_result,test_mileage,postcode_area,make,model,colour,fuel_type,cylinder_capacity,first_use_date,completed_date
      1531202977,415105519,2024-01-20,4,NT,F,2914.0,B,PEUGEOT,"STREETZONE 50 2T 12\"",GREEN,PE,49,2021-07-01,2024-01-20T10:00:00.000Z
    CSV
    File.write(@dir.join("item_detail_quotes.csv"), <<~'CSV')
      rfr_id|test_class_id|test_item_id|rfr_desc|rfr_insp_manual_desc
      10108|4|5073|so that beam "kick up" is not visible|The beam image contains a "Kick up" that is not visible on the screen.
    CSV

    Importers::MotBulk.new(results: @dir.join("results_quotes.csv").to_s, details: @dir.join("item_detail_quotes.csv").to_s).call

    assert_equal 'STREETZONE 50 2T 12"', Vehicle.last.model
    assert_equal 'The beam image contains a "Kick up" that is not visible on the screen.', DefectPhrase.last.text
  end

  test "an items file with no loaded tests is left to load again later" do
    write "items_only.csv", Importers::MotBulk::COLUMNS[:items], [ [ 999, 501, "F", nil, nil ] ]
    path = @dir.join("items_only.csv").to_s

    assert_equal 0, Importers::MotBulk.new(items: path).call.defects
    assert_not ImportRun.loaded?(source: "mot", kind: :items, path:)
  end

  test "says which columns a file is missing" do
    write "bad.csv", %w[test_id make], [ [ 1, "FORD" ] ]
    error = assert_raises(Importers::MotBulk::FormatError) { Importers::MotBulk.new(results: @dir.join("bad.csv").to_s).call }
    assert_match "vehicle_id", error.message
  end

  test "demo files run through the whole pipeline" do
    load_reference_data
    files = Curb::DemoMotFiles.new(@dir.join("demo"), vehicles_per_model: 2).write
    summary = Importers::MotBulk.new(**files, source: Importers::MotBulk::DEMO_SOURCE).call
    DefectCategorizer.new(use_ai: false).categorize(DefectPhrase.uncategorized.to_a)
    DefectRate.refresh_all!(concurrently: false)

    assert_equal Curb::DemoMotFiles::MODELS.size * 2, summary.vehicles
    assert DefectPhrase.where(categorized_at: nil).none?
    assert InspectionCell.any?
  end
end

class ImportMotFilesJobTest < ActiveJob::TestCase
  test "rebuilds the rates after every import, even when every defect wording was seen before" do
    dir = Pathname(Dir.mktmpdir)
    CSV.open(dir.join("test_result.csv"), "w", col_sep: "|") do |csv|
      csv << Importers::MotBulk::COLUMNS[:results]
      csv << [ 1, 10, "2024-03-01", 4, "NT", "P", 70_500, "SW", "VOLKSWAGEN", "GOLF GTI", "RED", "PE", 1395, "2015-02-01" ]
    end
    CSV.open(dir.join("test_item.csv"), "w", col_sep: "|") { |csv| csv << Importers::MotBulk::COLUMNS[:items] }

    assert_enqueued_with(job: RefreshDefectRatesJob) do
      ImportMotFilesJob.perform_now(results: dir.join("test_result.csv").to_s, items: dir.join("test_item.csv").to_s)
    end
  ensure
    FileUtils.rm_rf(dir)
  end
end
