require "test_helper"

class BulletinThemeTest < ActiveSupport::TestCase
  test "finds known failure themes in bulletin titles" do
    assert_equal %w[timing-chain], BulletinTheme.match("N20 timing chain guide noise at cold start")
    assert_includes BulletinTheme.match("Coolant pump inoperative, engine overheating"), "water-pump"
    assert_includes BulletinTheme.match("Coolant pump inoperative, engine overheating"), "overheating"
    assert_equal %w[shifting], BulletinTheme.match("DPS6 transmission shudder on acceleration")
    assert_empty BulletinTheme.match("Paint touch-up procedure")
  end

  test "every theme belongs to a real part category" do
    Curb::ReferenceData.load!
    assert_empty BulletinTheme::THEMES.map(&:category).uniq - DefectCategory.pluck(:slug)
  end
end
