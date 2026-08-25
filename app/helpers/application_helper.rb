module ApplicationHelper
  def money(cents, currency: "SAR")
    "#{currency} #{'%.2f' % (cents / 100.0)}"
  end

  # Money as a tabular monospace figure, colored by sign: credits (positive)
  # emerald, debits/reversals (negative) oxblood. Zero stays ink.
  def amount(cents, currency: "SAR")
    color =
      if cents.positive? then "text-credit"
      elsif cents.negative? then "text-debit"
      else "text-ink"
      end
    tag.span(money(cents, currency: currency), class: "font-mono text-sm #{color}")
  end

  CHIP_CLASSES = {
    "requested"  => "chip-requested",
    "processing" => "chip-processing",
    "settled"    => "chip-settled",
    "paid"       => "chip-settled",
    "failed"     => "chip-failed"
  }.freeze

  def status_badge(status)
    tag.span(status, class: "chip #{CHIP_CLASSES.fetch(status, 'chip-requested')}")
  end
end
