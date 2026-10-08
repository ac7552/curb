require "test_helper"
require "rake"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @admin.update!(admin: true, first_name: "Ada", last_name: "Admin")
  end

  def crash(message = "boom", path: "/reports")
    error = RuntimeError.new(message)
    error.set_backtrace([ Rails.root.join("app/services/report_builder.rb:39:in 'ReportBuilder#recalls'").to_s ])
    Rails.error.set_context(path:)
    Rails.error.report(error, handled: false, source: "application.action_dispatch")
  end

  test "the admin panel is invisible to everyone but admins" do
    sign_in_as users(:one)

    [ admin_root_path, admin_users_path, admin_errors_path, admin_features_path ].each do |path|
      get path
      assert_response :not_found, path
    end
    patch admin_feature_path("billing", enabled: "1")
    assert_response :not_found
    assert_not Billing.enabled?
  end

  test "lists users with their checks, and finds them by name or email" do
    users(:one).update!(first_name: "Sam", last_name: "Rivera")
    2.times { users(:one).record_use!(:check) }
    sign_in_as @admin

    get admin_users_path
    assert_response :success
    assert_select "tbody tr", 2
    assert_select "tr", text: /Sam Rivera.*one@example.com.*\b2\b/m

    get admin_users_path(q: "rivera")
    assert_select "tbody tr", 1
    assert_select "td", "one@example.com"
  end

  test "flipping a feature takes effect at once, and records who flipped it" do
    sign_in_as @admin
    get plans_path
    assert_response :not_found

    patch admin_feature_path("billing", enabled: "1")
    assert_redirected_to admin_features_path
    assert_equal [ true, @admin ], FeatureFlag.find_by!(key: "billing").then { [ _1.enabled, _1.updated_by ] }

    get plans_path
    assert_response :success
  end

  test "keeps crashes, one row per kind with a count, and reopens a resolved one when it happens again" do
    2.times { crash("Unknown primary key for table defect_categories") }
    crash("Something else entirely")
    assert_equal 1, ErrorEvent.count, "same error class and same place in our code"
    error = ErrorEvent.last
    assert_equal [ 3, "/reports", "Something else entirely" ], [ error.occurrences, error.path, error.message ]

    sign_in_as @admin
    get admin_errors_path
    assert_select "td a[href=?]", admin_error_path(error), text: "RuntimeError"

    patch admin_error_path(error, resolved: "1")
    assert error.reload.resolved?
    crash
    assert_not error.reload.resolved?, "happening again reopens it"
    assert_equal 4, error.occurrences
  end

  test "doesn't count visitors' mistakes, like a page that doesn't exist" do
    Rails.error.report(ActiveRecord::RecordNotFound.new("no such report"), handled: false)
    Rails.error.report(ActionController::BadRequest.new, handled: false)

    assert_equal 0, ErrorEvent.count
  end

  test "an admin can make another admin from the command line" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("curb:admin:grant")
    Rake::Task["curb:admin:grant"].execute(Rake::TaskArguments.new([ :email ], [ "ONE@example.com " ]))

    assert users(:one).reload.admin?
  end
end
