require "resolv"

# Fetches a web address a user gave us, without letting it reach anything but the public internet. A pasted link
# could point at this server itself (localhost), our database, the cloud provider's metadata service or a home
# network; SafeFetch looks the name up first, refuses any address that isn't public, then connects to exactly the
# address it checked (so a second, different DNS answer can't swap it), and checks again on every redirect.
# Responses are capped in time and size.
module SafeFetch
  class Error < StandardError; end

  Response = Data.define(:url, :body, :content_type)

  TIMEOUT = 5
  MAX_REDIRECTS = 3
  USER_AGENT = "Curb/1.0 (+https://checkcurb.com; link previews)".freeze

  # Ranges that aren't the public internet, beyond what IPAddr's private?/loopback?/link_local? cover.
  BLOCKED = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
               224.0.0.0/4 240.0.0.0/4 ::/128 64:ff9b::/96 100::/64 2001:db8::/32 ff00::/8].map { IPAddr.new(_1) }.freeze

  # Looks a name up in DNS; tests swap in their own answers.
  mattr_accessor :resolver, default: ->(host) { Resolv.getaddresses(host) }

  module_function

  def get(url, max_bytes:, accept: "*/*", redirects: MAX_REDIRECTS)
    uri = parse(url)
    address = public_address(uri.host)

    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = http.read_timeout = http.ssl_timeout = TIMEOUT

    request = Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => accept)
    http.start do
      http.request(request) do |response|
        case response
        when Net::HTTPRedirection
          raise Error, "Too many redirects" if redirects.zero?
          return get(URI.join(uri, response["location"].to_s).to_s, max_bytes:, accept:, redirects: redirects - 1)
        when Net::HTTPSuccess
          return Response.new(url: uri.to_s, body: read_capped(response, max_bytes), content_type: response["content-type"])
        else
          raise Error, "The site answered #{response.code}"
        end
      end
    end
  rescue Error
    raise
  rescue StandardError => e # timeouts, refused connections, TLS problems, bad addresses
    raise Error, "Couldn't fetch the page: #{e.class}"
  end

  def parse(url)
    uri = URI.parse(url.to_s.strip)
    raise Error, "Only web links work" unless %w[http https].include?(uri.scheme) && uri.host.present?
    raise Error, "Links with passwords aren't allowed" if uri.userinfo
    raise Error, "That port isn't allowed" unless [ 80, 443 ].include?(uri.port)
    uri
  rescue URI::InvalidURIError
    raise Error, "That isn't a web link"
  end

  # The first public IP the name resolves to; refuses names that resolve to anything private.
  def public_address(host)
    addresses = SafeFetch.resolver.call(host)
    raise Error, "That address can't be found" if addresses.empty?
    addresses.each { |address| raise Error, "That address isn't on the public internet" unless public?(address) }
    addresses.first
  end

  def public?(address)
    ip = IPAddr.new(address)
    ip = ip.native if ip.ipv4_mapped?
    !(ip.private? || ip.loopback? || ip.link_local? || BLOCKED.any? { _1.include?(ip) })
  rescue IPAddr::InvalidAddressError
    false
  end

  def read_capped(response, max_bytes)
    raise Error, "Too big" if response["content-length"].to_i > max_bytes
    body = +""
    response.read_body do |chunk|
      body << chunk
      raise Error, "Too big" if body.bytesize > max_bytes
    end
    body
  end
end
