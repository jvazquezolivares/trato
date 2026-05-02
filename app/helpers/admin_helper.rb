# frozen_string_literal: true

# View helpers for the admin panel.
# Provides navigation link rendering, formatting, and stage badge helpers.
module AdminHelper
  # Renders a sidebar navigation link with active state detection.
  def admin_nav_link(label, icon, path)
    is_active = request.path == path || (path != admin_path && request.path.start_with?(path))

    active_classes = "bg-slate-800 text-teal-400 translate-x-1"
    inactive_classes = "text-slate-400 hover:text-white hover:bg-slate-800/50"
    base_classes = "flex items-center gap-3 px-4 py-3 mx-2 rounded-xl font-medium transition-all duration-300"

    link_to path, class: "#{base_classes} #{is_active ? active_classes : inactive_classes}" do
      content_tag(:span, icon, class: "material-symbols-outlined", data: { icon: icon }) +
        content_tag(:span, label, class: "font-[Manrope]")
    end
  end

  # Renders a colored stage badge for conversations.
  def stage_badge(stage)
    colors = {
      "active" => "bg-teal-100 text-teal-800",
      "new" => "bg-blue-100 text-blue-800",
      "onboarding" => "bg-purple-100 text-purple-800",
      "collecting_info" => "bg-indigo-100 text-indigo-800",
      "scheduling" => "bg-amber-100 text-amber-800",
      "awaiting_provider" => "bg-orange-100 text-orange-800",
      "awaiting_client" => "bg-yellow-100 text-yellow-800",
      "escalated" => "bg-red-100 text-red-800",
      "closed" => "bg-gray-100 text-gray-600"
    }

    css = colors[stage] || "bg-gray-100 text-gray-600"
    content_tag(:span, stage&.humanize || "—", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold #{css}")
  end

  # Renders a job status badge.
  def job_status_badge(status)
    colors = {
      "paid" => "bg-green-100 text-green-800",
      "partial" => "bg-blue-100 text-blue-800",
      "pending" => "bg-amber-100 text-amber-800"
    }

    labels = {
      "paid" => "Pagado",
      "partial" => "Parcial",
      "pending" => "Pendiente"
    }

    css = colors[status] || "bg-gray-100 text-gray-600"
    label = labels[status] || status&.humanize || "—"
    content_tag(:span, label, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold #{css}")
  end

  # Formats a currency amount in MXN.
  def format_mxn(amount)
    "$#{number_with_delimiter(amount.to_i, delimiter: ',')} MXN"
  end

  # Masks a phone number for privacy display.
  def mask_phone(phone)
    return "—" if phone.blank?
    return phone if phone.length < 6

    "+52 #{phone[2..4]} ***#{phone[-4..]}"
  end

  # Returns a relative time description in Spanish.
  def time_ago_spanish(time)
    return "—" unless time

    time_ago_in_words(time) + " atrás"
  rescue StandardError
    "—"
  end
end
