# Runs a report end to end: the live lookup for this one car (recalls, inspection history), then the
# calculator. A failed lookup is recorded as a note rather than stopping the report.
class ReportBuilder
  def initialize(report) = @report = report

  def call
    @report.live_data = live_data
    @report.save!
    @report.calculate!
    @report
  end

  # A credited Commons photo of the car, or nil. A missing photo never stops a report, so failures are
  # only logged. Cached by car, since every check of the same model year wants the same picture.
  def self.photo_for(report)
    Rails.cache.fetch([ "car_photo/v1", report.make_key, report.model_key, report.model_year ], expires_in: 30.days, skip_nil: true) do
      Wikimedia::CarPhoto.new.find(make: report.make, model: report.model, model_year: report.model_year)
    end
  rescue HttpClient::Error => e
    Rails.logger.warn("[ReportBuilder] photo: #{e.message}")
    nil
  end

  private
    def live_data
      data = { recalls: [], notes: [] }
      fetch(data, "recalls") { data[:recalls] = recalls } if @report.country == "US"
      data[:programs] = programs if @report.country == "US"
      data[:owner_reports] = OwnerReports.for(make: @report.make, model: @report.model, model_year: @report.model_year) if @report.country == "US"
      data[:profile] = ModelProfile.for(make: @report.make, model: @report.model, model_year: @report.model_year, engine_key: @report.engine_key)
      fetch(data, "inspection history") { data[:history] = history } if @report.plate.present? && @report.country.in?(%w[GB NL])
      data[:photo] = self.class.photo_for(@report)
      data
    end


    def recalls
      found = Nhtsa::Recalls.new.for_vehicle(make: @report.make, model: @report.model, model_year: @report.model_year)
      Nhtsa::Recalls.store(found, make_key: @report.make_key, model_key: @report.model_key, model_year: @report.model_year)
      found
    rescue HttpClient::Error
      stored = Recall.for_vehicle(make_key: @report.make_key, model_key: @report.model_key, model_year: @report.model_year)
      raise if stored.none?
      stored.map do |recall|
        { campaign: recall.campaign_number, component: recall.component, summary: recall.summary,
          remedy: recall.remedy, reported_on: recall.reported_on&.iso8601, category: recall.defect_category&.slug }
      end
    end

    # Read straight from the stored bulletin feed, so unlike recalls this needs no network call and
    # cannot fail the report.
    def programs
      ServiceBulletin.programs_for(make_key: @report.make_key, model_key: @report.model_key,
                                   model_year: @report.model_year).map do |bulletin|
        { kind: bulletin.program_kind, label: bulletin.program_label,
          document: bulletin.document_id, title: bulletin.title }
      end
    end

    def history
      VehicleLookup.by_plate(@report.plate, country: @report.country)&.history
    end

    def fetch(data, what)
      yield
    rescue HttpClient::Error, VehicleLookup::Unavailable => e
      Rails.logger.warn("[ReportBuilder] #{what}: #{e.message}")
      data[:notes] << "Couldn't load #{what} right now, so it isn't included."
    end
end
