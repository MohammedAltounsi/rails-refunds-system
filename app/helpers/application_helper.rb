module ApplicationHelper
  def money(cents, currency: "SAR")
    "#{currency} #{'%.2f' % (cents / 100.0)}"
  end

  STATUS_CLASSES = {
    "requested"  => "bg-slate-100 text-slate-700",
    "processing" => "bg-amber-100 text-amber-800",
    "settled"    => "bg-emerald-100 text-emerald-800",
    "failed"     => "bg-rose-100 text-rose-800"
  }.freeze

  def status_badge(status)
    classes = STATUS_CLASSES.fetch(status, "bg-slate-100 text-slate-700")
    tag.span(status, class: "inline-block rounded-full px-2.5 py-0.5 text-xs font-medium #{classes}")
  end
end
