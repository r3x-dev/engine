# frozen_string_literal: true

return unless defined?(Flightdeck)

Flightdeck.configure do |config|
  if Rails.env.development? || Rails.env.test?
    config.skip_authentication = true
  else
    auth_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("FLIGHTDECK_AUTH_ENABLED", true))
    username = R3x::Env.fetch("FLIGHTDECK_USERNAME")
    password = R3x::Env.fetch("FLIGHTDECK_PASSWORD")

    if !auth_enabled
      config.skip_authentication = true
    elsif username.present? && password.present?
      config.http_basic = { username:, password: }
    end
  end
end

Rails.application.config.to_prepare do
  unless Flightdeck::ApplicationHelper.method_defined?(:flightdeck_brand_svg)
    raise "Flightdeck::ApplicationHelper#flightdeck_brand_svg is not defined. Upstream gem may have changed its brand helper."
  end

  Flightdeck::ApplicationHelper.module_eval do
    def flightdeck_brand_svg(size: 26)
      link_style = "display: inline-flex; align-items: center; gap: 6px; color: inherit; text-decoration: none;"
      link_to main_app.root_path, title: "Back to R3x Dashboard", style: link_style do
        safe_join([
          tag.svg(
            width: 20,
            height: 20,
            viewBox: "0 0 20 20",
            fill: "none",
            stroke: "currentColor",
            "stroke-width": 2.5,
            "stroke-linecap": "round",
            "stroke-linejoin": "round",
            style: "margin-right: 2px;",
          ) do
            tag.path(d: "M16 10H4M9 15l-5-5 5-5")
          end,
          tag.svg(width: size, height: size, viewBox: "0 0 26 26", fill: "none", "aria-hidden": true) do
            safe_join([
              tag.circle(cx: 13, cy: 13, r: 11.5, stroke: "var(--accent-ink)", "stroke-width": 1.6),
              tag.path(d: "M3 15 C 8 10.5, 18 10.5, 23 15", stroke: "var(--accent-ink)", "stroke-width": 1.6, fill: "none"),
              tag.path(d: "M9.5 13.2 h7 M13 11.4 v1.8", stroke: "var(--ink)", "stroke-width": 1.6, "stroke-linecap": "round"),
            ])
          end,
        ])
      end
    end
  end
end
