module ApplicationHelper
  def money(amount, market)
    return "–" if amount.nil?
    "#{market.symbol}#{number_with_delimiter(amount.round)}"
  end

  def compact_money(amount, market)
    return money(amount, market) if amount.abs < 10_000
    "#{market.symbol}#{number_to_human(amount, precision: 3, significant: true, format: "%n%u", units: { thousand: "k", million: "M" })}"
  end

  def percent(probability, precision: 0)
    return "–" if probability.nil?
    value = probability * 100
    return "<1%" if value.positive? && value < 1 && precision.zero?
    "#{number_with_precision(value, precision:, strip_insignificant_zeros: true)}%"
  end

  def distance(miles, market)
    "#{number_with_delimiter(Market.from_miles(miles, market.code))} #{market.distance_unit}"
  end

  def nav_link(label, path, dot:)
    active = current_page?(path)
    link_to path, class: [ "nav__link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) } do
      tag.span(class: "dot", style: "--dot: var(--#{dot})") + tag.span(label)
    end
  end
end
