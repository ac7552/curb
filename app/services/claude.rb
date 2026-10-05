# The Claude API key and client, shared by everything that calls Claude (sorting inspection notes, reading
# maintenance guides the rules can't). The key comes from ANTHROPIC_API_KEY or credentials.anthropic_api_key.
module Claude
  module_function

  def api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.anthropic_api_key
  def available? = api_key.present?
  def client = Anthropic::Client.new(api_key:)
end
