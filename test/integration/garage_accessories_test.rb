require "test_helper"

class GarageAccessoriesTest < ActionDispatch::IntegrationTest
  PNG = File.binread(Rails.root.join("test/fixtures/files/car.png"))

  setup do
    sign_in_as users(:one)
    @car = users(:one).garage_cars.create!(make: "Toyota", model: "Tacoma", model_year: 2019)
    @car.photos.attach(io: StringIO.new(PNG), filename: "front.png", content_type: "image/png")
    @resolver, SafeFetch.resolver = SafeFetch.resolver, ->(host) { host.end_with?(".test") ? [ "93.184.216.34" ] : [] }
  end

  teardown { SafeFetch.resolver = @resolver }

  def product_page(price_tags: true)
    <<~HTML
      <html><head>
        <meta property="og:title" content="TrailRack Roof Rack">
        <meta property="og:image" content="/img/rack.png">
        #{'<meta property="product:price:amount" content="249.99"><meta property="product:price:currency" content="USD">' if price_tags}
      </head></html>
    HTML
  end

  test "reads a product's name, price and picture from the link you paste" do
    stub_request(:get, "https://shop.test/rack").to_return(body: product_page, headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://shop.test/img/rack.png").to_return(body: PNG, headers: { "Content-Type" => "image/png" })

    post garage_car_accessories_path(@car), params: { garage_accessory: { url: "https://shop.test/rack" } }

    accessory = @car.accessories.last
    assert_equal [ "TrailRack Roof Rack", "$249.99", "shop.test" ], [ accessory.title, accessory.price, accessory.store ]
    assert accessory.image.attached?
    assert_match "place it", flash[:notice]
  end

  test "asks for the name when the shop won't share its page, and takes a picture you upload" do
    stub_request(:get, "https://blocked.test/item").to_return(status: 503)

    post garage_car_accessories_path(@car), params: { garage_accessory: { url: "https://blocked.test/item" } }
    assert_equal 0, @car.accessories.count
    assert_match "Type the product's name", flash[:alert]

    post garage_car_accessories_path(@car), params: { garage_accessory: { url: "https://blocked.test/item", title: "Mud flaps",
                                                                          image: fixture_file_upload("car.png", "image/png") } }
    assert_equal "Mud flaps", @car.accessories.last.title
    assert @car.accessories.last.image.attached?
  end

  test "never fetches links that point inside our own network" do
    SafeFetch.resolver = ->(_) { [ "169.254.169.254" ] } # a cloud metadata service

    post garage_car_accessories_path(@car), params: { garage_accessory: { url: "http://metadata.test/latest/meta-data" } }

    assert_not_requested :get, %r{metadata.test}
    assert_equal 0, @car.accessories.count
    [ "http://localhost/", "http://127.0.0.1/", "ftp://shop.test/x", "http://shop.test:6379/", "http://user:pw@shop.test/" ].each do |url|
      assert_raises(SafeFetch::Error, url) { SafeFetch.get(url, max_bytes: 100) }
    end
  end

  test "checks every redirect too" do
    stub_request(:get, "https://shop.test/go").to_return(status: 302, headers: { "Location" => "http://internal.test/admin" })
    SafeFetch.resolver = ->(host) { host == "internal.test" ? [ "10.0.0.5" ] : [ "93.184.216.34" ] }

    assert_raises(SafeFetch::Error) { SafeFetch.get("https://shop.test/go", max_bytes: 1_000) }
    assert_not_requested :get, %r{internal.test}
  end

  test "places an accessory on one of the car's photos, moves it, and takes it off" do
    accessory = @car.accessories.create!(url: "https://shop.test/rack", title: "Roof rack")
    photo = @car.spin_photos.first

    post garage_car_accessory_placements_path(@car, accessory), params: { photo_id: photo.id }, as: :json
    assert_response :created
    placement = accessory.placements.last
    assert_equal [ 0.5, 0.5, 0.3 ], [ placement.x, placement.y, placement.width ].map(&:to_f)

    patch garage_car_accessory_placement_path(@car, accessory, placement), params: { placement: { x: 0.25, y: 0.1, width: 0.6, rotation: -12 } }, as: :json
    assert_equal [ 0.25, 0.1, 0.6, -12.0 ], [ placement.reload.x, placement.y, placement.width, placement.rotation ].map(&:to_f)

    patch garage_car_accessory_placement_path(@car, accessory, placement), params: { placement: { x: 4 } }, as: :json
    assert_response :unprocessable_entity

    delete garage_car_accessory_placement_path(@car, accessory, placement), as: :json
    assert_equal 0, accessory.placements.count
  end

  test "only places accessories on that car's own photos, and only for its owner" do
    accessory = @car.accessories.create!(url: "https://shop.test/rack", title: "Roof rack")
    other = users(:one).garage_cars.create!(make: "Honda", model: "Civic", model_year: 2020)
    other.photos.attach(io: StringIO.new(PNG), filename: "x.png", content_type: "image/png")

    post garage_car_accessory_placements_path(@car, accessory), params: { photo_id: other.spin_photos.first.id }, as: :json
    assert_response :unprocessable_entity

    sign_in_as users(:two)
    post garage_car_accessory_placements_path(@car, accessory), params: { photo_id: @car.spin_photos.first.id }, as: :json
    assert_response :not_found
  end
end
