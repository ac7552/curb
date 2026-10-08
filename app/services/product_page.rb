# Reads a product page someone pasted a link to: its name, price and picture, from the tags shops add for link
# previews (Open Graph, schema.org). The link comes from a user, so every request goes through SafeFetch, which only
# talks to public addresses. Shops that turn away automated visits just give no details; the owner types them in.
class ProductPage
  Details = Data.define(:title, :price, :image_url)

  MAX_PAGE_BYTES = 1.megabyte

  def self.read(url) = new(url).read

  def initialize(url)
    @url = url
  end

  # Details, or nil when the page can't be read.
  def read
    response = SafeFetch.get(@url, max_bytes: MAX_PAGE_BYTES, accept: "text/html")
    return unless response.content_type.to_s.include?("html")

    doc = Nokogiri::HTML(response.body)
    Details.new(title: title(doc), price: price(doc), image_url: image_url(doc, response.url))
  rescue SafeFetch::Error
    nil
  end

  # The product picture, downloaded (only a real JPEG, PNG or WebP under the size limit), or nil.
  def self.download_image(image_url)
    response = SafeFetch.get(image_url, max_bytes: GarageAccessory::MAX_IMAGE_BYTES, accept: "image/*")
    io = StringIO.new(response.body)
    return unless GarageCar.picture?(io)
    { io:, filename: File.basename(URI.parse(response.url).path).presence || "product", content_type: response.content_type.to_s.split(";").first }
  rescue SafeFetch::Error, URI::InvalidURIError
    nil
  end

  private
    def meta(doc, *names)
      names.each do |name|
        node = doc.at_css(%(meta[property="#{name}"], meta[name="#{name}"], meta[itemprop="#{name}"]))
        value = node&.[]("content").to_s.squish
        return value if value.present?
      end
      nil
    end

    def title(doc)
      (meta(doc, "og:title", "twitter:title") || doc.at_css("title")&.text.to_s.squish.presence)&.truncate(200)
    end

    def price(doc)
      amount = meta(doc, "product:price:amount", "og:price:amount", "price") || json_ld_price(doc)
      return unless amount
      currency = meta(doc, "product:price:currency", "og:price:currency", "priceCurrency")
      (currency.nil? || currency == "USD" ? "$#{amount}" : "#{amount} #{currency}").truncate(40)
    end

    # Shops that only describe the product in schema.org JSON: { "@type": "Product", "offers": { "price": … } }.
    def json_ld_price(doc)
      doc.css('script[type="application/ld+json"]').each do |script|
        Array.wrap(JSON.parse(script.text)).each do |item|
          offers = item.is_a?(Hash) && item["@type"].to_s.include?("Product") && Array.wrap(item["offers"]).first
          return offers["price"].to_s if offers.is_a?(Hash) && offers["price"].present?
        end
      rescue JSON::ParserError
        next
      end
      nil
    end

    def image_url(doc, page_url)
      found = meta(doc, "og:image", "og:image:url", "twitter:image") || doc.at_css('link[rel="image_src"]')&.[]("href")
      URI.join(page_url, found).to_s if found.present?
    rescue URI::Error
      nil
    end
end
