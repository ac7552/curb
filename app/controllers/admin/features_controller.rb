class Admin::FeaturesController < Admin::BaseController
  def index
    @features = Feature.all
  end

  def update
    feature = Feature.find(params[:key])
    Feature.set!(feature.key, params[:enabled] == "1", by: Current.user)
    redirect_to admin_features_path, notice: "#{feature.name} is now #{Feature.enabled?(feature.key) ? "on" : "off"}."
  rescue KeyError
    head :not_found
  end
end
