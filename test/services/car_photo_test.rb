require "test_helper"

class CarPhotoTest < ActiveSupport::TestCase
  def page(index, title, license: "CC BY-SA 4.0", width: 4000)
    { index:, title: "File:#{title}.jpg", imageinfo: [ { mime: "image/jpeg", width:, thumburl: "https://upload.wikimedia.org/#{index}.jpg",
      descriptionurl: "https://commons.wikimedia.org/wiki/#{index}", extmetadata: { LicenseShortName: { value: license }, Artist: { value: "<b>Someone</b>" } } } ] }
  end

  def stub_search(*pages)
    body = { query: { pages: pages.each_with_index.to_h { |p, i| [ i.to_s, p ] } } }
    stub_request(:get, %r{commons.wikimedia.org/w/api.php}).to_return(headers: { "Content-Type" => "application/json" }, body: body.to_json)
  end

  test "picks a front view of the right model year" do
    stub_search(page(1, "Second Gen Toyota Tacoma on Snowy Mountain - 2019"),
                page(2, "2019 Toyota Tacoma SR5, rear right"),
                page(3, "2020 Toyota Tacoma TRD Pro front"),
                page(4, "2019 Toyota Tacoma SR5 4WD Access Cab, front right"))

    photo = Wikimedia::CarPhoto.new.find(make: "Toyota", model: "Tacoma", model_year: 2019)

    assert_equal "https://upload.wikimedia.org/4.jpg", photo[:url]
    assert_equal "Someone", photo[:artist]
  end

  test "skips photos it can't freely use, small ones and close-ups" do
    stub_search(page(1, "2019 Toyota Tacoma front", license: "All rights reserved"),
                page(2, "2019 Toyota Tacoma front", width: 400),
                page(3, "2019 Toyota Tacoma interior"))

    assert_nil Wikimedia::CarPhoto.new.find(make: "Toyota", model: "Tacoma", model_year: 2019)
  end
end
