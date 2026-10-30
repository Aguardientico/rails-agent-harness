# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    # sanitize_sql_like escapes % and _ with a backslash; SQLite needs ESCAPE to honor it.
    posts = Post.where("title LIKE ? ESCAPE '\\'", "%#{Post.sanitize_sql_like(params[:q].to_s)}%").includes(:comments)
    render plain: posts.map { |post| "#{post.title} (#{post.comments.size} comments)" }.join("\n")
  end
end
