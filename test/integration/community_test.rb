require "test_helper"

class CommunityTest < ActionDispatch::IntegrationTest
  setup do
    @sam = users(:one)
    @sam.update!(first_name: "Sam", last_name: "Rivera")
    @ana = users(:two)
    @ana.update!(first_name: "Ana", last_name: "Lopez")
    @sam.garage_cars.create!(make: "Toyota", model: "Tacoma", model_year: 2019)
  end

  def start_thread(title: "Best tires for trails?", body: "Running 265/70R17s now.")
    post community_room_threads_path("toyota", "tacoma"), params: { forum_thread: { title:, body: } }
    ForumThread.last
  end

  test "goes from your garage straight to your model's room, and posts a thread and a reply" do
    sign_in_as @sam
    get community_path
    assert_select "a[href=?]", community_room_path("toyota", "tacoma"), text: "Toyota Tacoma"

    get community_room_path("toyota", "tacoma")
    assert_response :success
    thread = start_thread
    assert_redirected_to forum_thread_path(thread)
    assert_equal [ "TOYOTA", "TACOMA", @sam ], [ thread.make_key, thread.model_key, thread.user ]

    sign_in_as @ana
    post forum_thread_posts_path(thread), params: { forum_post: { body: "BFG KO2s, no question." } }
    assert_equal 1, thread.reload.forum_posts_count

    get forum_thread_path(thread)
    assert_select ".forum__post", text: /Sam R\..*Running 265/m
    assert_select ".forum__post", text: /Ana L\..*BFG KO2s/m
    assert_no_match "rivera", response.body.downcase.sub(/\A.*<main/m, ""), "only a last initial is shown"

    get community_make_path("toyota")
    assert_select ".forum__thread", text: /Best tires for trails/
  end

  test "shows what people write as plain text" do
    sign_in_as @sam
    thread = start_thread(body: %(<script>alert(1)</script><a href="javascript:x">click</a>))

    get forum_thread_path(thread)
    assert_select ".forum__body script", 0
    assert_select ".forum__body a", 0
    assert_match "&lt;script&gt;", response.body
  end

  test "asks for a name before posting, and keeps banned people from posting" do
    @sam.update_columns(last_name: "")
    sign_in_as @sam
    start_thread
    assert_redirected_to account_path
    assert_equal 0, ForumThread.count

    @sam.update_columns(last_name: "Rivera", banned_at: Time.current)
    start_thread
    assert_equal 0, ForumThread.count
  end

  test "only rooms for models Curb knows" do
    sign_in_as @sam
    get community_room_path("toyota", "no-such-model")
    assert_response :not_found
    get community_make_path("not-a-maker")
    assert_response :not_found
  end

  test "people report posts; an admin hides them, or bans the author and hides all they wrote" do
    sign_in_as @ana
    thread = start_thread(title: "Cheap parts!!!", body: "Visit my shop")
    reply = thread.posts.create!(user: @ana, body: "More spam")

    sign_in_as @sam
    post forum_reports_path, params: { reportable_type: "ForumThread", reportable_id: thread.id, reason: "spam" }
    post forum_reports_path, params: { reportable_type: "ForumThread", reportable_id: thread.id, reason: "spam" }
    assert_equal 1, ForumReport.count, "one report per person per post"

    admin = users(:one)
    admin.update!(admin: true)
    get admin_reports_path
    assert_select ".admin__report", text: /Spam or advertising.*Cheap parts/m

    patch admin_report_path(ForumReport.last, decision: "ban")
    assert @ana.reload.banned?
    assert thread.reload.hidden?
    assert reply.reload.hidden?
    assert_empty ForumReport.open

    admin.update!(admin: false)
    get forum_thread_path(thread)
    assert_response :not_found
  end
end
