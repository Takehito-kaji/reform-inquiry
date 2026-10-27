module ApplicationHelper
  def fmt_time(time)
    time ? time.in_time_zone.strftime("%Y/%m/%d %H:%M") : ""
  end

  def fmt_size(bytes)
    bytes.to_i >= 1024 * 1024 ? format("%.1fMB", bytes / 1024.0 / 1024) : "#{(bytes.to_i / 1024.0).ceil}KB"
  end

  def nav_link(label, path)
    link_to label, path, class: (current_page?(path) ? "on" : nil)
  end
end
