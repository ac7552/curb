source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Reads makers' maintenance guides for curb:guides:extract, which runs on a developer's machine.
  gem "pdf-reader", "~> 2.12", require: false
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

# Materialized views for the defect-rate tables
gem "scenic", "~> 1.8"
# Small-batch inserts (recalls, reference data)
gem "activerecord-import", "~> 2.1"
# HTTP clients for NHTSA, RDW and the MOT History API
gem "faraday", "~> 2.12"
gem "faraday-retry", "~> 2.2"
# Sorting defect phrases into categories, and reading maintenance guides the rules can't
gem "anthropic", "~> 1.80"
# Plus subscriptions: checkout, the billing portal and webhooks [https://docs.stripe.com/api?lang=ruby]
gem "stripe", "~> 15.0"

group :test do
  gem "webmock", "~> 3.24"
end

# json 3.x drops the quirks_mode option that ActiveSupport 8.0 still passes
gem "json", "~> 2.10"

# Reading and writing MOT files; not a default gem from Ruby 3.4
gem "csv", "~> 3.3"

# Deploys the app to a server as a Docker container [https://kamal-deploy.org]
gem "kamal", "~> 2.12", require: false
# Serves assets with compression and caching in front of Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false
