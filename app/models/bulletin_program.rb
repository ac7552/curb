# Free repairs the maker has already agreed to pay for, hidden inside the service-bulletin feed.
#
# When a part fails often enough to embarrass a manufacturer but not often enough to force a recall,
# the maker quietly extends the warranty on it: a Customer Satisfaction Program, a Special Policy
# Adjustment, a warranty extension. The repair is free to anyone who asks, and nothing obliges a
# dealer to mention it. Owners routinely pay for a repair the maker would have covered.
#
# These arrive as ordinary bulletins in NHTSA's manufacturer-communications file, distinguishable
# only by their wording, so this is a matcher over the summary rather than a separate feed.
module BulletinProgram
  Kind = Data.define(:slug, :label, :pattern)

  # Order matters: the first match wins, so the most specific promise is listed first.
  KINDS = [
    [ "warranty-extension", "Extended warranty",
      /warranty (extension|enhancement)|extend\w* (the )?(new vehicle |powertrain |limited )?warranty|warranty (coverage )?(has been|is being|will be) extended|coverage (has been )?extended to/i ],
    [ "special-policy", "Special policy adjustment",
      /special (policy|coverage|service) (adjustment|program|campaign)|special policy\b/i ],
    [ "customer-satisfaction", "Customer satisfaction program",
      /customer satisfaction (program|campaign|initiative)|service (program|action) to (replace|repair|inspect)|in the interest of customer satisfaction/i ],
    [ "goodwill", "Goodwill repair policy",
      /goodwill (repair|policy|coverage|assistance)/i ]
  ].map { |slug, label, pattern| Kind.new(slug, label, pattern) }.freeze

  BY_SLUG = KINDS.index_by(&:slug).freeze

  # Manufacturers file a cover sheet quoting the regulation that requires the filing. It names every
  # document type including customer satisfaction campaigns, so it matches every pattern above while
  # promising nothing. Excluded before matching.
  BOILERPLATE = /579\.5|code of federal regulations/i

  module_function

  def find(slug) = BY_SLUG[slug.to_s]

  def label(slug) = find(slug)&.label

  # The kind of promise a bulletin makes, or nil when it is an ordinary repair instruction.
  def match(title)
    text = title.to_s
    return nil if text.match?(BOILERPLATE)

    KINDS.find { |kind| text.match?(kind.pattern) }&.slug
  end

  # Tags every bulletin with the kind of programme its title describes. Titles repeat across cars and
  # years, so each distinct title is matched once. Returns the number of rows updated.
  def tag_all!
    ServiceBulletin.distinct.pluck(:title).group_by { |title| match(title) }.sum do |kind, titles|
      titles.each_slice(1_000).sum do |slice|
        # IS DISTINCT FROM, not where.not: program_kind is nullable, and `!= 'x'` evaluates to NULL
        # for an untagged row, which silently excludes every row this is meant to update.
        ServiceBulletin.where(title: slice)
                       .where("program_kind IS DISTINCT FROM ?", kind)
                       .update_all(program_kind: kind)
      end
    end
  end
end
