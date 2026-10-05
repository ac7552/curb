module ReadOnlyView
  extend ActiveSupport::Concern

  included do
    self.primary_key = nil
  end

  def readonly? = true
end
