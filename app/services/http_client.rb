# Shared Faraday setup for the public vehicle APIs: JSON in and out, short timeouts (the buyer is
# standing on a dealer lot), and a couple of retries on flaky connections.
module HttpClient
  class Error < StandardError; end

  module_function

  def build(url, headers: {})
    Faraday.new(url:, headers: { "User-Agent" => "Curb/1.0" }.merge(headers)) do |f|
      f.request :retry, max: 2, interval: 0.3, exceptions: [ Faraday::ConnectionFailed, Faraday::TimeoutError ]
      f.response :json, content_type: /\bjson$/
      f.response :raise_error
      f.options.open_timeout = 3
      f.options.timeout = 8
    end
  end

  def get(connection, path, params = {}, headers: {})
    connection.get(path, params, headers).body
  rescue Faraday::Error => e
    raise Error, "#{connection.url_prefix.host}: #{e.message}"
  end
end
