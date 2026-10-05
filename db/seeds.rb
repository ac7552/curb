# Reference data: categories, warranty terms, service schedule, labor rates. Safe to re-run.
Curb::ReferenceData.load!

puts "Reference data: #{DefectCategory.count} categories, #{WarrantyTerm.count} warranty terms, " \
     "#{ServiceItem.count} service items, #{LaborRate.count} labor rates, #{MaintenanceGuide.count} maintenance guides"

# Demo inspections so the app works before the real MOT files are loaded. Skip with SKIP_DEMO=1.
if Vehicle.none? && ENV["SKIP_DEMO"].blank?
  puts "Generating demo MOT files (illustrative, not real data)..."
  files = Curb::DemoMotFiles.new(Rails.root.join("tmp/demo_mot")).write
  summary = Importers::MotBulk.new(**files, source: Importers::MotBulk::DEMO_SOURCE).call
  puts "Loaded #{summary.to_h}"
  DefectCategorizer.new(use_ai: false).categorize(DefectPhrase.uncategorized.to_a)
  DefectRate.refresh_all!
  puts "Rate tables built: #{InspectionCell.count} cells, #{DefectRate.count} rate rows"
end

# Development sign-in (never created outside development).
if Rails.env.development?
  User.find_or_create_by!(email_address: "demo@curb.test") { |user| user.password = "curb-rloRAcfrjNDi" }
  puts "Development user: demo@curb.test (password in db/seeds.rb)"
end
