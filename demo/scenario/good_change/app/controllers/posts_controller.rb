# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    posts = Post.where("title LIKE ?", "%#{Post.sanitize_sql_like(params[:q].to_s)}%").includes(:comments)
    render plain: posts.map { |post| "#{post.title} (#{post.comments.size} comments)" }.join("\n")
  end
end
