# A model's room in Our Garage: every discussion about one make and model. Rooms aren't stored; a room is any model
# Curb knows (the catalog, anyone's garage, or one that already has threads), so every car has one.
ForumRoom = Data.define(:make_key, :model_key) do
  def self.slug(key) = key.to_s.parameterize

  # The make for a URL slug ("mercedes-benz"), or nil.
  def self.make_key_for(slug)
    known_make_keys.find { |key| self.slug(key) == slug }
  end

  # The room for URL slugs ("toyota", "cr-v"), or nil when Curb doesn't know that model.
  def self.find(make_slug, model_slug)
    make_key = make_key_for(make_slug) or return
    model_key = model_keys(make_key).find { |key| slug(key) == model_slug } or return
    new(make_key:, model_key:)
  end

  def self.known_make_keys
    (MakeCatalog.makes("US").map { VehicleName.make_key(_1[:name]) } + GarageCar.distinct.pluck(:make) .map { VehicleName.make_key(_1) } +
      ForumThread.distinct.pluck(:make_key)).uniq
  end

  # Models of a make with a room, most talked-about and best-selling first, each name once ("C" and "C-CLASS" are both
  # the C-Class; the room holds threads under either).
  def self.listed_model_keys(make_key) = model_keys(make_key).uniq { MakeCatalog.display_model(make_key, _1) }

  def self.model_keys(make_key)
    talked = ForumThread.visible.where(make_key:).group(:model_key).order(Arel.sql("COUNT(*) DESC")).count.keys
    owned = GarageCar.distinct.pluck(:make, :model).select { |make, _| VehicleName.make_key(make) == make_key }.map { VehicleName.model_key(_2) }
    (talked + MakeCatalog.popular_models(make_key, "US") + owned).uniq.reject(&:blank?)
  end

  def self.for(car) = new(make_key: car.make_key, model_key: car.model_key)

  def make_name = VehicleName.display_make(make_key)
  def model_name = MakeCatalog.display_model(make_key, model_key)
  def title = "#{make_name} #{model_name}"
  def make_slug = self.class.slug(make_key)
  def model_slug = self.class.slug(model_key)
  def threads = ForumThread.visible.where(make_key:, model_key: same_model_keys)

  # This model's other spellings, so a room shows every thread about it.
  def same_model_keys = self.class.model_keys(make_key).select { MakeCatalog.display_model(make_key, _1) == model_name }.presence || [ model_key ]
end
