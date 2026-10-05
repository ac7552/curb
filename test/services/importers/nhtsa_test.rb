require "test_helper"

class Importers::NhtsaTest < ActiveSupport::TestCase
  setup do
    Curb::ReferenceData.load!
    @dir = Pathname(Dir.mktmpdir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  # A FLAT_CMPL line: 51 tab-separated fields, with personal details in the fields we skip.
  def complaint(odino:, make: "FORD", model: "FOCUS", year: 2014, component: "POWER TRAIN:AUTOMATIC TRANSMISSION", miles: 50_000, towed: "N", product: "V")
    fields = Array.new(51, "")
    fields[0], fields[1], fields[3], fields[4], fields[5] = "C#{odino}", odino.to_s, make, model, year.to_s
    fields[6], fields[8], fields[11], fields[12], fields[17] = "N", "N", component, "SPRINGFIELD", miles.to_s
    fields[19], fields[45], fields[48], fields[50] = "Story that names people", product, towed, "JANE DOE"
    fields.join("\t")
  end

  test "counts complaints per car and part and keeps no personal details" do
    File.write(@dir.join("FLAT_CMPL.txt"), [
      complaint(odino: 1, towed: "Y", miles: 40_000),
      complaint(odino: 1, component: "POWER TRAIN:AUTOMATIC TRANSMISSION:CONTROL MODULE"), # same complaint, same part
      complaint(odino: 2, miles: 0),
      complaint(odino: 3, component: "ENGINE"),
      complaint(odino: 4, component: "UNKNOWN OR OTHER"),
      complaint(odino: 5, product: "T"),
      complaint(odino: 6, year: 1990)
    ].join("\n"))

    Importers::NhtsaComplaints.new(@dir.join("FLAT_CMPL.txt").to_s).call

    transmission = ComplaintCount.find_by!(make_key: "FORD", model_key: "FOCUS", model_year: 2014, category_slug: "transmission")
    assert_equal [ 2, 1, 1 ], [ transmission.complaints, transmission.towed, transmission.with_miles ]
    assert_equal 40_000, transmission.average_miles
    assert_equal %w[engine transmission], ComplaintCount.order(:category_slug).pluck(:category_slug)
    assert_not ComplaintCount.column_names.any? { |name| name.match?(/name|city|descr|dealer|vin/) }
  end

  test "stores one bulletin row per model year with a category from its summary" do
    CSV.open(@dir.join("MFR_COMMS_RECEIVED_2020-2024.csv"), "w") do |csv|
      csv << [ "TSB/Document ID", "Make", "Model", "Model Year", "Concise Summary" ]
      csv << [ "123", "FORD", "FOCUS", "2014,2015", "DPS6 transmission shudder on acceleration. Reprogram the transmission control module." ]
      csv << [ "124", "FORD", "FOCUS", "2014", "Radio presets lost after battery disconnect" ]
    end

    Importers::NhtsaBulletins.new(@dir.join("MFR_COMMS_RECEIVED_2020-2024.csv").to_s).call

    assert_equal [ 2014, 2015 ], ServiceBulletin.where(document_id: "123").order(:model_year).pluck(:model_year)
    assert_equal "transmission", ServiceBulletin.find_by!(document_id: "123", model_year: 2014).category_slug
  end
end
