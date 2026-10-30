# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    posts = Post.where("title LIKE '%#{params[:q]}%'")
    render plain: posts.map { |post| "#{post.title} (#{post.comments.count} comments)" }.join("\n")
  end
end
