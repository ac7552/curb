require "test_helper"

class GarageTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  def photo(name = "car.png") = fixture_file_upload(name, "image/png")

  test "adds a car to your garage, then photos for its 360° spin, in order" do
    assert_difference -> { users(:one).garage_cars.count } do
      post garage_cars_path, params: { garage_car: { make: " Toyota ", model: "Tacoma", model_year: 2019, nickname: "" } }
    end
    car = GarageCar.last
    assert_redirected_to garage_car_path(car)
    assert_equal [ "Toyota", nil, "2019 Toyota Tacoma" ], [ car.make, car.nickname, car.name ]

    post garage_car_photos_path(car), params: { photos: [ photo, photo, photo ] }
    assert_redirected_to garage_car_path(car)
    assert_equal 3, car.reload.spin_photos.size

    get garage_car_path(car)
    assert_select ".spin[data-spin-frames-value='3']"
    assert_select ".spin__frame", 3
    assert_select ".spin__frame.is-on", 1

    get garage_cars_path
    assert_select ".garage__card", text: /2019 Toyota Tacoma.*3 photos/m
  end

  test "turns away files that aren't pictures, and more photos than a spin takes" do
    car = users(:one).garage_cars.create!(make: "Honda", model: "Civic", model_year: 2020)

    post garage_car_photos_path(car), params: { photos: [ photo("fake.png") ] }
    assert_match "JPEG, PNG or WebP", flash[:alert]
    assert_equal 0, car.reload.photos.count

    post garage_car_photos_path(car), params: { photos: Array.new(GarageCar::MAX_PHOTOS + 1) { photo } }
    assert_match "at most #{GarageCar::MAX_PHOTOS}", flash[:alert]
    assert_equal 0, car.reload.photos.count, "none of a batch that breaks the rules is kept"
  end

  test "removes a photo, edits and removes a car" do
    car = users(:one).garage_cars.create!(make: "Honda", model: "Civic", model_year: 2020)
    car.photos.attach([ photo, photo ].map { { io: File.open(_1.path), filename: "car.png", content_type: "image/png" } })

    delete garage_car_photo_path(car, car.spin_photos.first)
    assert_equal 1, car.reload.photos.count

    patch garage_car_path(car), params: { garage_car: { nickname: "Weekend car" } }
    assert_equal "Weekend car", car.reload.name

    delete garage_car_path(car)
    assert_not GarageCar.exists?(car.id)
  end

  test "your garage is yours alone" do
    theirs = users(:two).garage_cars.create!(make: "BMW", model: "M3", model_year: 2022)

    get garage_car_path(theirs)
    assert_response :not_found
    post garage_car_photos_path(theirs), params: { photos: [ photo ] }
    assert_response :not_found
    delete garage_car_path(theirs)
    assert_response :not_found
    assert GarageCar.exists?(theirs.id)
  end

  test "a walk-around's frames replace the photos already there, and a bad one leaves them alone" do
    car = users(:one).garage_cars.create!(make: "Toyota", model: "Tacoma", model_year: 2019)
    post garage_car_photos_path(car), params: { photos: [ photo, photo ] }
    old_ids = car.reload.spin_photos.ids

    post garage_car_photos_path(car), params: { replace: "1", photos: [ photo("fake.png") ] }
    assert_equal old_ids, car.reload.spin_photos.ids, "a rejected walk-around keeps the old spin"

    post garage_car_photos_path(car), params: { replace: "1", photos: Array.new(GarageCar::MAX_PHOTOS) { photo } }
    assert_equal "Your 360° spin is ready.", flash[:notice]
    assert_equal GarageCar::MAX_PHOTOS, car.reload.photos.count, "36 new frames, even though 2 photos were there"
    assert_empty old_ids & car.spin_photos.ids

    get garage_car_path(car)
    assert_select "input[type=file][accept='video/*'][capture=environment]"
  end
end
