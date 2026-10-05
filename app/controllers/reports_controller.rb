class ReportsController < ApplicationController
  before_action :set_report, only: %i[show destroy photo]

  PER_PAGE = 24
  SORTS = %w[recent cost].freeze

  # Sorting by cost reads the figure out of the stored results rather than recomputing it, so the
  # whole list never has to be loaded to order twelve rows.
  COST_SQL = Arel.sql("(results #>> '{summary,true_cost}')::numeric")

  def index
    scope = Current.user.reports
    @total = scope.count
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "recent"
    @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @pages)

    ordered = @sort == "cost" ? scope.order(COST_SQL.desc.nulls_last) : scope.recent
    @reports = ordered.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # The widest bar is the priciest car this person has checked, not the priciest on this page, so a
    # bar means the same thing from one page to the next.
    @max_cost = scope.maximum(COST_SQL).to_f
  end

  def new
    # Where they live comes from their account when they've told us; otherwise the US and its average rate.
    country = Current.user.country || "US"
    @report = Current.user.reports.new(country:, lookup_mode: "model", ownership_years: 3, shop_type: "independent")
    @report.region = (Current.user.region if Current.user.country == country) || LaborRate.regions_for(country).first
  end

  def create
    unless Current.user.can_use?(:check)
      return redirect_to plans_path, alert: "You've used your #{Current.user.plan_details.limit(:check)} free checks this month. " \
                                            "Plus gives you unlimited checks."
    end

    @report = Current.user.reports.new(report_params)
    if @report.valid?
      ReportBuilder.new(@report).call
      Current.user.record_use!(:check, report: @report)
      redirect_to @report
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  # Checks made before photos existed fetch theirs once, the first time they're opened. Only the photo
  # is written, without validations: an old check may not pass today's rules (a made-up model saved
  # before cars were checked against NHTSA), and adding a picture shouldn't re-judge it.
  def photo
    photo = @report.live.fetch(:photo) do
      ReportBuilder.photo_for(@report).tap { |found| @report.update_column(:live_data, @report.live_data.merge("photo" => found)) }
    end
    if params[:card]
      render partial: "reports/card_photo", locals: { report: @report, photo: }
    else
      render partial: "reports/photo", locals: { photo:, name: @report.model }
    end
  end

  def destroy
    @report.destroy
    redirect_to reports_path, notice: "Check deleted."
  end

  private
    def set_report
      @report = Current.user.reports.find(params[:id])
    end

    def report_params
      params.expect(report: %i[
        lookup_mode country vin plate make model model_year engine fuel_type first_used_on
        odometer asking_price ownership_years yearly_distance
        addon_warranty addon_years addon_miles addon_coverage
        monthly_budget emergency_savings region shop_type
      ]).tap do |permitted|
        %i[monthly_budget emergency_savings addon_miles yearly_distance].each { |key| permitted[key] = permitted[key].presence }
      end
    end
end
