require "test_helper"

class MaintenanceGuideSourcesTest < ActiveSupport::TestCase
  PDF = { status: 206, headers: { "Content-Type" => "application/pdf" } }.freeze

  def find(make, model, year) = MaintenanceGuides::Finder.new.find(make:, model:, model_year: year)

  test "builds Toyota's guide address from the year and model" do
    stub_request(:get, %r{T-MMS-19Tacoma}).to_return(PDF)

    guide = find("Toyota", "Tacoma", 2019)

    assert_equal "https://assets.sia.toyota.com/publications/en/omms-s/T-MMS-19Tacoma/pdf/T-MMS-19Tacoma.pdf", guide.url
    assert_equal :maintenance_guide, guide.kind
  end

  test "finds nothing when the maker has no guide there, or no source covers the maker" do
    stub_request(:get, %r{assets.sia.toyota.com}).to_return(status: 404)
    stub_request(:get, %r{assets.sia.toyota.com/.*T-MMS-19Corolla}).to_return(status: 200, headers: { "Content-Type" => "text/html" })

    assert_nil find("Toyota", "Tacoma", 1990)
    assert_nil find("Toyota", "Corolla", 2019), "a page that isn't a PDF doesn't count"
    assert_nil find("Ford", "F-150", 2019)
    refute MaintenanceGuides::Finder.new.supports?("Ford")
  end

  test "tries each spelling a maker uses until one is a PDF" do
    stub_request(:get, %r{L-MMS-}).to_return(status: 404)
    stub_request(:get, %r{L-MMS-20RX450h/}).to_return(PDF)
    stub_request(:get, %r{owners.honda.com}).to_return(status: 404)
    stub_request(:get, "https://owners.honda.com/utility/download?path=#{ERB::Util.url_encode("/static/pdfs/2018/Civic Sedan/2018_Civic_4D_Maintenance_Minder.pdf")}").to_return(PDF)

    assert_match "L-MMS-20RX450h", find("Lexus", "RX", 2020).url
    assert_match "Civic%20Sedan", find("Honda", "Civic", 2018).url
  end

  test "follows a redirect to the PDF" do
    stub_request(:get, %r{nissanusa.com/content/dam/.*/rogue/2020/}).to_return(status: 302, headers: { "Location" => "https://cdn.example.test/rogue.pdf" })
    stub_request(:get, "https://cdn.example.test/rogue.pdf").to_return(PDF)

    guide = find("Nissan", "Rogue", 2020)

    assert_equal :owner_manual, guide.kind
    assert_match "2020-nissan-rogue-owner-manual.pdf", guide.url
  end

  test "searches GM's manual index for the owner manual, not another version's" do
    docs = [
      { title_ordered: [ "2019 Chevrolet Silverado 2500 HD Owner's Manual" ], path: "https://gm.example.test/hd.pdf" },
      { title_ordered: [ "2019 Chevrolet Silverado Warranty" ], path: "https://gm.example.test/warranty.pdf" },
      { title_ordered: [ "2019 Chevrolet Silverado Owner's Manual" ], path: "https://gm.example.test/silverado.pdf" }
    ]
    stub = stub_request(:get, %r{contentdelivery.ext.gm.com}).to_return(body: { response: { docs: } }.to_json)

    guide = find("Chevrolet", "Silverado", 2019)

    assert_equal "https://gm.example.test/silverado.pdf", guide.url
    assert_equal "2019 Chevrolet Silverado Owner's Manual", guide.title
    assert_requested stub
  end

  test "looks Hyundai's owner manual up by tag within a browsing session" do
    stub_request(:get, MaintenanceGuides::Sources::HyundaiLookup::PAGE).to_return(headers: { "Set-Cookie" => "session=abc; Path=/" })
    lookup = stub_request(:post, MaintenanceGuides::Sources::HyundaiLookup::LOOKUP)
      .with(headers: { "Cookie" => "session=abc" }, body: hash_including("tags" => "2019 HYUNDAI SANTA FE"))
      .to_return(body: [
        { pageText: "2019 Warranty & Consumer Information Manual", href: "/content/dam/warranty.pdf", modelYear: "2019" },
        { pageText: "2019 Santa Fe Owner's Manual", href: "/content/dam/santa-fe.pdf", modelYear: "2019" }
      ].to_json)

    guide = find("Hyundai", "Santa Fe", 2019)

    assert_equal "https://owners.hyundaiusa.com/content/dam/santa-fe.pdf", guide.url
    assert_requested lookup
  end

  test "uses the hand-listed booklet for makers that print one a year" do
    file = Tempfile.new([ "addresses", ".yml" ])
    file.write({ "Subaru" => [ { "years" => "2019-2020", "url" => "https://subaru.example.test/book.pdf", "title" => "Subaru booklet" } ] }.to_yaml)
    file.close
    original, MaintenanceGuides::Sources::AddressFile.path = MaintenanceGuides::Sources::AddressFile.path, file.path
    stub_request(:get, "https://subaru.example.test/book.pdf").to_return(PDF)

    guide = find("Subaru", "Outback", 2020)

    assert_equal :all_models_booklet, guide.kind
    assert_equal "Outback", guide.model
    assert_nil find("Subaru", "Outback", 2021)
  ensure
    MaintenanceGuides::Sources::AddressFile.path = original
    file&.unlink
  end

  test "uses a hand-listed booklet for the models it names before one for every model" do
    file = Tempfile.new([ "addresses", ".yml" ])
    file.write({ "Mitsubishi" => [ { "years" => 2022, "url" => "https://mitsu.example.test/all.pdf", "title" => "All models" },
                                   { "years" => 2022, "models" => [ "Outlander" ], "url" => "https://mitsu.example.test/outlander.pdf", "title" => "Outlander" } ] }.to_yaml)
    file.close
    original, MaintenanceGuides::Sources::AddressFile.path = MaintenanceGuides::Sources::AddressFile.path, file.path
    stub_request(:get, %r{mitsu.example.test}).to_return(PDF)

    assert_equal "https://mitsu.example.test/outlander.pdf", find("Mitsubishi", "Outlander", 2022).url
    assert_equal "https://mitsu.example.test/all.pdf", find("Mitsubishi", "Mirage", 2022).url
  ensure
    MaintenanceGuides::Sources::AddressFile.path = original
    file&.unlink
  end

  test "uses a booklet imported from a browser when the maker's site refuses downloads" do
    file = Tempfile.new([ "addresses", ".yml" ])
    file.write({ "BMW" => [ { "years" => 2019, "url" => "https://bmw.example.test/2019-maintenance.pdf", "title" => "BMW 2019 Maintenance" } ] }.to_yaml)
    file.close
    original, MaintenanceGuides::Sources::AddressFile.path = MaintenanceGuides::Sources::AddressFile.path, file.path
    stub_request(:get, %r{bmw.example.test}).to_raise(Faraday::ConnectionFailed.new("refused"))
    assert_nil find("BMW", "X3", 2019)

    cached = MaintenanceGuides::Reader.pdf_path(MaintenanceGuides::Guide.new(make: "", model: "", model_year: 0, url: "https://bmw.example.test/2019-maintenance.pdf", title: ""))
    FileUtils.mkdir_p(cached.dirname)
    File.binwrite(cached, "%PDF-1.4")
    assert_equal "BMW 2019 Maintenance", find("BMW", "X3", 2019).title
  ensure
    MaintenanceGuides::Sources::AddressFile.path = original
    file&.unlink
    FileUtils.rm_f(cached) if cached
  end

  test "finds VW's schedule among its NHTSA filings" do
    ServiceBulletin.create!(document_id: "10171234", make_key: "VOLKSWAGEN", model_key: "JETTA", model_year: 2019,
                            title: "2019 Volkswagen Jetta Maintenance Schedule For USA 1.4T Engine")
    ServiceBulletin.create!(document_id: "10179999", make_key: "VOLKSWAGEN", model_key: "JETTA", model_year: 2019,
                            title: "Maintenance Schedule Incorrect In Owner Literature")
    stub_request(:get, %r{static.nhtsa.gov}).to_return(status: 404)
    stub_request(:get, "https://static.nhtsa.gov/odi/tsbs/2018/MC-10171234-0001.pdf").to_return(PDF)

    guide = find("Volkswagen", "Jetta", 2019)

    assert_equal "https://static.nhtsa.gov/odi/tsbs/2018/MC-10171234-0001.pdf", guide.url
    assert_equal :nhtsa_filing, guide.kind
    assert_not_requested :get, %r{MC-10179999}
  end

  test "finds Tesla's owner's manual among its NHTSA filings, sent as a plain file" do
    ServiceBulletin.create!(document_id: "11008831", make_key: "TESLA", model_key: "MODEL 3", model_year: 2021,
                            title: "Tesla does not provide physical owner's manual copies. Owner's Manual.")
    stub_request(:get, %r{static.nhtsa.gov}).to_return(status: 404)
    stub_request(:get, "https://static.nhtsa.gov/odi/tsbs/2024/MC-11008831-0001.pdf")
      .to_return(status: 206, headers: { "Content-Type" => "application/octet-stream" }, body: "%PDF-1.7 …")

    guide = find("Tesla", "Model 3", 2021)

    assert_equal "https://static.nhtsa.gov/odi/tsbs/2024/MC-11008831-0001.pdf", guide.url
  end

  test "covers every maker with an automated source" do
    expected = %w[TOYOTA LEXUS NISSAN INFINITI HONDA ACURA MAZDA CHEVROLET GMC BUICK CADILLAC HYUNDAI SUBARU VOLKSWAGEN AUDI TESLA GENESIS MITSUBISHI JEEP BMW]

    assert_equal expected.sort, MaintenanceGuides::Finder.supported_makes.sort
  end
end
