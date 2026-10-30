# frozen_string_literal: true

RSpec.describe "dummy app" do
  let(:env) { {"RAILS_ENV" => "test"} }

  it "boots with the Railtie registered" do
    with_dummy_app_copy do |app_root|
      script = "puts Rails.application.railties.map(&:class).include?(RailsAgentHarness::Railtie)"
      output, status = run_in(app_root, "bin/rails runner '#{script}'", env: env)

      expect(status).to be_success, output
      expect(output.lines.last.strip).to eq("true")
    end
  end

  it "loads the committed schema and exposes Post/Comment" do
    with_dummy_app_copy do |app_root|
      output, status = run_in(app_root, "bin/rails db:schema:load", env: env)
      expect(status).to be_success, output

      script = 'post = Post.create!(title: "t", body: "b"); post.comments.create!(body: "c"); puts Comment.first.post == post'
      output, status = run_in(app_root, "bin/rails runner '#{script}'", env: env)
      expect(status).to be_success, output
      expect(output.lines.last.strip).to eq("true")
    end
  end

  it "has generator-created migrations matching db/schema.rb" do
    dummy = DummyAppHelper::DUMMY_APP
    migrations = Dir[File.join(dummy, "db/migrate/*.rb")].map { |path| File.basename(path) }.sort
    schema = File.read(File.join(dummy, "db/schema.rb"))
    latest = migrations.last[/\A\d{14}/]

    expect(migrations.map { |name| name.sub(/\A\d{14}_/, "") }).to eq(%w[create_posts.rb create_comments.rb])
    expect(schema).to include("version: #{latest.sub(/(\d{4})(\d{2})(\d{2})(\d{6})/, '\1_\2_\3_\4')}")
    expect(schema).to include('create_table "posts"', 'create_table "comments"')
  end
end
