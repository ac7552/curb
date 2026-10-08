# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_10_08_120201) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accessory_placements", force: :cascade do |t|
    t.bigint "garage_accessory_id", null: false
    t.bigint "photo_id", null: false
    t.decimal "x", precision: 6, scale: 5, null: false
    t.decimal "y", precision: 6, scale: 5, null: false
    t.decimal "width", precision: 6, scale: 5, null: false
    t.decimal "rotation", precision: 6, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["garage_accessory_id", "photo_id"], name: "index_accessory_placements_on_garage_accessory_id_and_photo_id", unique: true
    t.index ["garage_accessory_id"], name: "index_accessory_placements_on_garage_accessory_id"
    t.index ["photo_id"], name: "index_accessory_placements_on_photo_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "complaint_counts", force: :cascade do |t|
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "model_year", null: false
    t.string "category_slug", null: false
    t.integer "complaints", default: 0, null: false
    t.integer "towed", default: 0, null: false
    t.integer "crashes", default: 0, null: false
    t.integer "fires", default: 0, null: false
    t.integer "with_miles", default: 0, null: false
    t.bigint "miles_total", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_slug", "model_year"], name: "index_complaint_counts_on_category_slug_and_model_year"
    t.index ["make_key", "model_key", "model_year", "category_slug"], name: "index_complaint_counts_on_car_and_part", unique: true
  end

  create_table "defect_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "warranty_type", default: "none", null: false
    t.decimal "labor_hours", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "parts_cost_usd", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "wear_item", default: false, null: false
    t.string "keywords", default: [], null: false, array: true
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "blurb"
    t.index ["slug"], name: "index_defect_categories_on_slug", unique: true
  end

  create_table "defect_phrases", force: :cascade do |t|
    t.string "source", null: false
    t.string "external_id"
    t.text "text", null: false
    t.bigint "defect_category_id"
    t.string "categorized_by"
    t.datetime "categorized_at"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["categorized_at"], name: "index_defect_phrases_on_categorized_at"
    t.index ["defect_category_id"], name: "index_defect_phrases_on_defect_category_id"
    t.index ["source", "external_id"], name: "index_defect_phrases_on_source_and_external_id", unique: true
  end

  create_table "defects", force: :cascade do |t|
    t.bigint "inspection_id", null: false
    t.bigint "defect_phrase_id", null: false
    t.string "kind", null: false
    t.string "severity"
    t.index ["defect_phrase_id"], name: "index_defects_on_defect_phrase_id"
    t.index ["inspection_id"], name: "index_defects_on_inspection_id"
  end

  create_table "error_events", force: :cascade do |t|
    t.string "fingerprint", null: false
    t.string "error_class", null: false
    t.text "message"
    t.text "backtrace"
    t.string "source"
    t.string "path"
    t.string "request_id"
    t.bigint "user_id"
    t.integer "occurrences", default: 1, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_error_events_on_fingerprint", unique: true
    t.index ["last_seen_at"], name: "index_error_events_on_last_seen_at"
    t.index ["user_id"], name: "index_error_events_on_user_id"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", null: false
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
    t.index ["updated_by_id"], name: "index_feature_flags_on_updated_by_id"
  end

  create_table "forum_posts", force: :cascade do |t|
    t.bigint "forum_thread_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "hidden_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "parent_id"
    t.integer "score", default: 0, null: false
    t.index ["forum_thread_id"], name: "index_forum_posts_on_forum_thread_id"
    t.index ["parent_id"], name: "index_forum_posts_on_parent_id"
    t.index ["user_id"], name: "index_forum_posts_on_user_id"
  end

  create_table "forum_reports", force: :cascade do |t|
    t.bigint "reporter_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reportable_id", null: false
    t.string "reason", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_forum_reports_on_reportable"
    t.index ["reporter_id", "reportable_type", "reportable_id"], name: "idx_on_reporter_id_reportable_type_reportable_id_13682a59e6", unique: true
    t.index ["reporter_id"], name: "index_forum_reports_on_reporter_id"
  end

  create_table "forum_threads", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.integer "forum_posts_count", default: 0, null: false
    t.datetime "last_posted_at", null: false
    t.datetime "hidden_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "score", default: 0, null: false
    t.index ["make_key", "model_key", "last_posted_at"], name: "idx_on_make_key_model_key_last_posted_at_556abebe45"
    t.index ["make_key", "model_key", "score"], name: "index_forum_threads_on_make_key_and_model_key_and_score"
    t.index ["user_id"], name: "index_forum_threads_on_user_id"
  end

  create_table "forum_votes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "votable_type", null: false
    t.bigint "votable_id", null: false
    t.integer "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "votable_type", "votable_id"], name: "index_forum_votes_on_user_id_and_votable_type_and_votable_id", unique: true
    t.index ["user_id"], name: "index_forum_votes_on_user_id"
    t.index ["votable_type", "votable_id"], name: "index_forum_votes_on_votable"
  end

  create_table "garage_accessories", force: :cascade do |t|
    t.bigint "garage_car_id", null: false
    t.string "url", null: false
    t.string "title", null: false
    t.string "price"
    t.boolean "remove_background", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["garage_car_id"], name: "index_garage_accessories_on_garage_car_id"
  end

  create_table "garage_cars", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "make", null: false
    t.string "model", null: false
    t.integer "model_year", null: false
    t.string "nickname"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_garage_cars_on_user_id"
  end

  create_table "import_runs", force: :cascade do |t|
    t.string "source", null: false
    t.string "kind", null: false
    t.string "file_name", null: false
    t.bigint "file_size", null: false
    t.jsonb "counts", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "kind", "file_name", "file_size"], name: "idx_on_source_kind_file_name_file_size_a9cc8ad472", unique: true
  end

  create_table "inspections", force: :cascade do |t|
    t.bigint "vehicle_id", null: false
    t.string "source", null: false
    t.string "external_id", null: false
    t.date "inspected_on", null: false
    t.integer "mileage"
    t.string "result", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["source", "external_id"], name: "index_inspections_on_source_and_external_id", unique: true
    t.index ["vehicle_id"], name: "index_inspections_on_vehicle_id"
  end

  create_table "insurance_loss_indexes", force: :cascade do |t|
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "year_from", null: false
    t.integer "year_to", null: false
    t.integer "injury"
    t.integer "collision"
    t.integer "theft"
    t.integer "property_damage"
    t.string "source", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["make_key", "model_key", "year_from"], name: "idx_on_make_key_model_key_year_from_919b438e1e", unique: true
  end

  create_table "labor_rates", force: :cascade do |t|
    t.string "country", null: false
    t.string "region", null: false
    t.string "shop_type", null: false
    t.decimal "hourly_rate", precision: 8, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country", "region", "shop_type"], name: "index_labor_rates_on_country_and_region_and_shop_type", unique: true
  end

  create_table "maintenance_guides", force: :cascade do |t|
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "model_year", null: false
    t.string "make", null: false
    t.string "model", null: false
    t.string "status", null: false
    t.string "url", null: false
    t.string "title", null: false
    t.jsonb "rows", default: [], null: false
    t.jsonb "problems", default: [], null: false
    t.string "read_with"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["make_key", "model_key", "model_year"], name: "idx_on_make_key_model_key_model_year_1974b8d244", unique: true
  end

  create_table "model_sales", force: :cascade do |t|
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "year", null: false
    t.integer "units", null: false
    t.string "source", null: false
    t.string "source_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["make_key", "model_key", "year"], name: "index_model_sales_on_make_key_and_model_key_and_year", unique: true
  end

  create_table "recalls", force: :cascade do |t|
    t.string "campaign_number", null: false
    t.string "country", default: "US", null: false
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "year_from", null: false
    t.integer "year_to", null: false
    t.string "component"
    t.text "summary"
    t.text "remedy"
    t.date "reported_on"
    t.bigint "defect_category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_number"], name: "index_recalls_on_campaign_number", unique: true
    t.index ["defect_category_id"], name: "index_recalls_on_defect_category_id"
    t.index ["make_key", "model_key"], name: "index_recalls_on_make_key_and_model_key"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "share_token", null: false
    t.string "lookup_mode", default: "model", null: false
    t.string "country", null: false
    t.string "vin"
    t.string "plate"
    t.string "make", null: false
    t.string "model", null: false
    t.integer "model_year", null: false
    t.string "engine"
    t.string "fuel_type"
    t.date "first_used_on"
    t.integer "current_mileage", null: false
    t.decimal "asking_price", precision: 12, scale: 2, null: false
    t.integer "ownership_years", default: 3, null: false
    t.integer "miles_per_year", null: false
    t.string "addon_warranty", default: "none", null: false
    t.integer "addon_years"
    t.integer "addon_miles"
    t.string "addon_coverage"
    t.decimal "monthly_budget", precision: 10, scale: 2
    t.decimal "emergency_savings", precision: 12, scale: 2
    t.string "region", null: false
    t.string "shop_type", default: "independent", null: false
    t.jsonb "live_data", default: {}, null: false
    t.jsonb "results", default: {}, null: false
    t.datetime "calculated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["share_token"], name: "index_reports_on_share_token", unique: true
    t.index ["user_id", "created_at"], name: "index_reports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "service_bulletins", force: :cascade do |t|
    t.string "document_id", null: false
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.integer "model_year", null: false
    t.string "title", null: false
    t.string "category_slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "themes", default: [], null: false, array: true
    t.string "program_kind"
    t.index ["make_key", "model_key", "model_year", "document_id"], name: "index_service_bulletins_on_car_and_document", unique: true
    t.index ["make_key", "model_key", "model_year", "program_kind"], name: "index_service_bulletins_on_car_and_program", where: "(program_kind IS NOT NULL)"
    t.index ["model_year", "category_slug", "make_key", "model_key"], name: "idx_on_model_year_category_slug_make_key_model_key_42b73551c8"
    t.index ["themes"], name: "index_service_bulletins_on_themes", using: :gin
  end

  create_table "service_items", force: :cascade do |t|
    t.string "make_key"
    t.string "model_key"
    t.string "name", null: false
    t.integer "interval_miles"
    t.integer "interval_months"
    t.decimal "labor_hours", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "parts_cost_usd", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "wear_item", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["make_key", "model_key"], name: "index_service_items_on_make_key_and_model_key"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.bigint "report_id"
    t.datetime "created_at", null: false
    t.index ["report_id"], name: "index_usage_events_on_report_id"
    t.index ["user_id", "kind", "created_at"], name: "index_usage_events_on_user_id_and_kind_and_created_at"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "country"
    t.string "postal_code"
    t.string "car_types", default: [], null: false, array: true
    t.string "plan", default: "free", null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "subscription_status"
    t.datetime "plan_renews_at"
    t.boolean "admin", default: false, null: false
    t.datetime "banned_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true
  end

  create_table "vehicles", force: :cascade do |t|
    t.string "source", null: false
    t.string "external_id", null: false
    t.string "country", null: false
    t.string "make", null: false
    t.string "model", null: false
    t.string "make_key", null: false
    t.string "model_key", null: false
    t.string "engine_key"
    t.string "fuel_type"
    t.integer "engine_cc"
    t.integer "model_year"
    t.date "first_used_on"
    t.string "vin"
    t.string "plate"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["make_key", "model_key", "engine_key"], name: "index_vehicles_on_make_key_and_model_key_and_engine_key"
    t.index ["source", "external_id"], name: "index_vehicles_on_source_and_external_id", unique: true
  end

  create_table "warranty_terms", force: :cascade do |t|
    t.string "country", null: false
    t.string "make_key", null: false
    t.string "coverage_type", null: false
    t.integer "years", null: false
    t.integer "miles"
    t.boolean "transferable", default: true, null: false
    t.integer "model_year_from"
    t.integer "model_year_to"
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country", "make_key", "coverage_type"], name: "index_warranty_terms_on_country_and_make_key_and_coverage_type"
  end

  add_foreign_key "accessory_placements", "active_storage_attachments", column: "photo_id", on_delete: :cascade
  add_foreign_key "accessory_placements", "garage_accessories"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "defect_phrases", "defect_categories"
  add_foreign_key "defects", "defect_phrases"
  add_foreign_key "defects", "inspections"
  add_foreign_key "error_events", "users", on_delete: :nullify
  add_foreign_key "feature_flags", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "forum_posts", "forum_posts", column: "parent_id", on_delete: :cascade
  add_foreign_key "forum_posts", "forum_threads"
  add_foreign_key "forum_posts", "users"
  add_foreign_key "forum_reports", "users", column: "reporter_id"
  add_foreign_key "forum_threads", "users"
  add_foreign_key "forum_votes", "users"
  add_foreign_key "garage_accessories", "garage_cars"
  add_foreign_key "garage_cars", "users"
  add_foreign_key "inspections", "vehicles"
  add_foreign_key "recalls", "defect_categories"
  add_foreign_key "reports", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "usage_events", "reports", on_delete: :nullify
  add_foreign_key "usage_events", "users"

  create_view "inspection_cells", materialized: true, sql_definition: <<-SQL
      SELECT v.make_key,
      v.model_key,
      COALESCE(v.engine_key, ''::character varying) AS engine_key,
      (LEAST(GREATEST(floor((((i.inspected_on - COALESCE(v.first_used_on, make_date(v.model_year, 7, 1))))::numeric / 365.25)), (0)::numeric), (25)::numeric))::integer AS age_years,
      (LEAST(i.mileage, 299999) / 20000) AS mileage_band,
      (count(*))::integer AS tests
     FROM (inspections i
       JOIN vehicles v ON ((v.id = i.vehicle_id)))
    WHERE ((i.mileage IS NOT NULL) AND ((v.first_used_on IS NOT NULL) OR (v.model_year IS NOT NULL)))
    GROUP BY v.make_key, v.model_key, COALESCE(v.engine_key, ''::character varying), ((LEAST(GREATEST(floor((((i.inspected_on - COALESCE(v.first_used_on, make_date(v.model_year, 7, 1))))::numeric / 365.25)), (0)::numeric), (25)::numeric))::integer), (LEAST(i.mileage, 299999) / 20000);
  SQL
  add_index "inspection_cells", ["make_key", "model_key", "engine_key", "age_years", "mileage_band"], name: "index_inspection_cells_on_cell", unique: true

  create_view "defect_rates", materialized: true, sql_definition: <<-SQL
      WITH tested AS (
           SELECT i.id AS inspection_id,
              v.make_key,
              v.model_key,
              COALESCE(v.engine_key, ''::character varying) AS engine_key,
              (LEAST(GREATEST(floor((((i.inspected_on - COALESCE(v.first_used_on, make_date(v.model_year, 7, 1))))::numeric / 365.25)), (0)::numeric), (25)::numeric))::integer AS age_years,
              (LEAST(i.mileage, 299999) / 20000) AS mileage_band
             FROM (inspections i
               JOIN vehicles v ON ((v.id = i.vehicle_id)))
            WHERE ((i.mileage IS NOT NULL) AND ((v.first_used_on IS NOT NULL) OR (v.model_year IS NOT NULL)))
          ), failed AS (
           SELECT t.make_key,
              t.model_key,
              t.engine_key,
              t.age_years,
              t.mileage_band,
              p.defect_category_id,
              (count(DISTINCT t.inspection_id))::integer AS failures
             FROM ((tested t
               JOIN defects d ON (((d.inspection_id = t.inspection_id) AND ((d.kind)::text = 'fail'::text))))
               JOIN defect_phrases p ON ((p.id = d.defect_phrase_id)))
            WHERE (p.defect_category_id IS NOT NULL)
            GROUP BY t.make_key, t.model_key, t.engine_key, t.age_years, t.mileage_band, p.defect_category_id
          )
   SELECT f.make_key,
      f.model_key,
      f.engine_key,
      f.age_years,
      f.mileage_band,
      f.defect_category_id,
      f.failures,
      c.tests
     FROM (failed f
       JOIN inspection_cells c ON ((((c.make_key)::text = (f.make_key)::text) AND ((c.model_key)::text = (f.model_key)::text) AND ((c.engine_key)::text = (f.engine_key)::text) AND (c.age_years = f.age_years) AND (c.mileage_band = f.mileage_band))));
  SQL
  add_index "defect_rates", ["make_key", "model_key", "engine_key", "age_years", "mileage_band", "defect_category_id"], name: "index_defect_rates_on_cell_and_category", unique: true

  create_view "defect_baselines", materialized: true, sql_definition: <<-SQL
      WITH totals AS (
           SELECT inspection_cells.age_years,
              inspection_cells.mileage_band,
              (sum(inspection_cells.tests))::integer AS tests
             FROM inspection_cells
            GROUP BY inspection_cells.age_years, inspection_cells.mileage_band
          ), failures AS (
           SELECT defect_rates.defect_category_id,
              defect_rates.age_years,
              defect_rates.mileage_band,
              (sum(defect_rates.failures))::integer AS failures
             FROM defect_rates
            GROUP BY defect_rates.defect_category_id, defect_rates.age_years, defect_rates.mileage_band
          )
   SELECT f.defect_category_id,
      f.age_years,
      f.mileage_band,
      f.failures,
      t.tests
     FROM (failures f
       JOIN totals t USING (age_years, mileage_band));
  SQL
  add_index "defect_baselines", ["defect_category_id", "age_years", "mileage_band"], name: "index_defect_baselines_on_category_and_band", unique: true

  create_view "model_part_profiles", materialized: true, sql_definition: <<-SQL
      WITH tested AS (
           SELECT i.id AS inspection_id,
              v.make_key,
              v.model_key,
              COALESCE(v.engine_key, ''::character varying) AS engine_key,
              (EXTRACT(year FROM v.first_used_on))::integer AS build_year,
              (LEAST(GREATEST(floor((((i.inspected_on - v.first_used_on))::numeric / 365.25)), (0)::numeric), (25)::numeric))::integer AS age
             FROM (inspections i
               JOIN vehicles v ON ((v.id = i.vehicle_id)))
            WHERE (v.first_used_on >= '1995-01-01'::date)
          ), parts AS (
           SELECT d.inspection_id,
              p.defect_category_id,
              bool_or(((d.kind)::text = 'fail'::text)) AS failed
             FROM (defects d
               JOIN defect_phrases p ON ((p.id = d.defect_phrase_id)))
            WHERE (p.defect_category_id IS NOT NULL)
            GROUP BY d.inspection_id, p.defect_category_id
          ), age_tests AS (
           SELECT tested.age,
              (count(*))::double precision AS tests
             FROM tested
            GROUP BY tested.age
          ), age_rates AS (
           SELECT t_1.age,
              pa.defect_category_id,
              ((count(*))::double precision / max(a.tests)) AS hit_rate,
              ((count(*) FILTER (WHERE pa.failed))::double precision / max(a.tests)) AS fail_rate
             FROM ((tested t_1
               JOIN parts pa USING (inspection_id))
               JOIN age_tests a USING (age))
            GROUP BY t_1.age, pa.defect_category_id
          ), group_ages AS (
           SELECT tested.make_key,
              tested.model_key,
              COALESCE(tested.engine_key, '*'::character varying) AS engine_key,
              tested.build_year,
              tested.age,
              count(*) AS tests
             FROM tested
            GROUP BY GROUPING SETS ((tested.make_key, tested.model_key, tested.engine_key, tested.build_year, tested.age), (tested.make_key, tested.model_key, tested.build_year, tested.age))
          ), group_hits AS (
           SELECT t_1.make_key,
              t_1.model_key,
              COALESCE(t_1.engine_key, '*'::character varying) AS engine_key,
              t_1.build_year,
              pa.defect_category_id,
              (count(*))::integer AS hits,
              (count(*) FILTER (WHERE pa.failed))::integer AS fails
             FROM (tested t_1
               JOIN parts pa USING (inspection_id))
            GROUP BY GROUPING SETS ((t_1.make_key, t_1.model_key, t_1.engine_key, t_1.build_year, pa.defect_category_id), (t_1.make_key, t_1.model_key, t_1.build_year, pa.defect_category_id))
          ), expected AS (
           SELECT h_1.make_key,
              h_1.model_key,
              h_1.engine_key,
              h_1.build_year,
              h_1.defect_category_id,
              sum(((g.tests)::double precision * r.hit_rate)) AS expected_hits,
              sum(((g.tests)::double precision * r.fail_rate)) AS expected_fails
             FROM ((group_hits h_1
               JOIN group_ages g ON ((((g.make_key)::text = (h_1.make_key)::text) AND ((g.model_key)::text = (h_1.model_key)::text) AND ((g.engine_key)::text = (h_1.engine_key)::text) AND (g.build_year = h_1.build_year))))
               JOIN age_rates r ON (((r.defect_category_id = h_1.defect_category_id) AND (r.age = g.age))))
            GROUP BY h_1.make_key, h_1.model_key, h_1.engine_key, h_1.build_year, h_1.defect_category_id
          ), totals AS (
           SELECT group_ages.make_key,
              group_ages.model_key,
              group_ages.engine_key,
              group_ages.build_year,
              (sum(group_ages.tests))::integer AS tests
             FROM group_ages
            GROUP BY group_ages.make_key, group_ages.model_key, group_ages.engine_key, group_ages.build_year
          )
   SELECT h.make_key,
      h.model_key,
      h.engine_key,
      h.build_year,
      h.defect_category_id,
      t.tests,
      h.hits,
      h.fails,
      e.expected_hits,
      e.expected_fails
     FROM ((group_hits h
       JOIN totals t USING (make_key, model_key, engine_key, build_year))
       JOIN expected e USING (make_key, model_key, engine_key, build_year, defect_category_id));
  SQL
  add_index "model_part_profiles", ["make_key", "model_key", "engine_key", "build_year", "defect_category_id"], name: "index_model_part_profiles_on_group_and_part", unique: true

end
