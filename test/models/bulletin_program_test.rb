require "test_helper"

class BulletinProgramTest < ActiveSupport::TestCase
  test "recognises the ways a maker says it will pay for a repair" do
    assert_equal "warranty-extension",
                 BulletinProgram.match("American Honda is announcing a warranty extension for the infotainment unit")
    assert_equal "customer-satisfaction",
                 BulletinProgram.match("18309 - Customer Satisfaction Program. Certain 2019 Silverado vehicles")
    assert_equal "special-policy",
                 BulletinProgram.match("Special Policy Adjustment: cracked exhaust manifold")
    assert_equal "goodwill",
                 BulletinProgram.match("Goodwill repair policy for early water pump failure")
  end

  test "an ordinary repair instruction is not a programme" do
    assert_nil BulletinProgram.match("N20 timing chain guide noise at cold start")
    assert_nil BulletinProgram.match("Paint touch-up procedure")
  end

  # Manufacturers file a cover sheet quoting the regulation that requires the filing. It lists every
  # document type, customer satisfaction campaigns among them, while promising nothing. Matching it
  # would tell owners of 148 vehicles they are owed a free repair that does not exist.
  test "the regulatory cover sheet is not a promise of anything" do
    boilerplate = "Code of Federal Regulations Title 49 part 579.5 Notices,Bulletins, customer satisfaction campaigns."

    assert_nil BulletinProgram.match(boilerplate)
  end

  test "every programme kind has a label for the report" do
    BulletinProgram::KINDS.each do |kind|
      assert BulletinProgram.label(kind.slug).present?, "#{kind.slug} has no label"
    end
  end
end
