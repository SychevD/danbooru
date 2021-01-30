module ComponentsHelper
  def post_preview(post, **options)
    render PostPreviewComponent.new(post: post, **options)
  end

  def post_previews_html(posts, **options)
    render PostPreviewComponent.with_collection(posts, **options)
  end

  def render_comment(comment, **options)
    render CommentComponent.new(comment: comment, **options)
  end

  def render_comment_section(post, **options)
    render CommentSectionComponent.new(post: post, **options)
  end

  def render_post_votes(post, **options)
    render PostVotesComponent.new(post: post, **options)
  end

  def render_post_navbar(post, **options)
    render PostNavbarComponent.new(post: post, **options)
  end

  # A simple vertical tag list with no post counts. Used in related tags.
  def render_simple_tag_list(tag_names, **options)
    tags = TagListComponent.tags_from_names(tag_names)
    render TagListComponent.new(tags: tags, **options).with_variant(:simple)
  end

  # A horizontal tag list, with tags grouped by category. Used in post
  # tooltips, on the comments index, and in the modqueue.
  def render_inline_tag_list(post, **options)
    render TagListComponent.new(tags: post.tags, **options).with_variant(:inline)
  end

  def render_inline_tag_list_from_names(tag_names, **options)
    tags = TagListComponent.tags_from_names(tag_names)
    render TagListComponent.new(tags: tags, **options).with_variant(:inline)
  end

  # A vertical tag list, with tags split into categories. Used on post show pages.
  def render_categorized_tag_list(post, **options)
    render TagListComponent.new(tags: post.tags, **options).with_variant(:categorized)
  end

  # A vertical tag list, used in the post index sidebar.
  def render_search_tag_list(tag_names, **options)
    tags = TagListComponent.tags_from_names(tag_names)
    render TagListComponent.new(tags: tags, **options).with_variant(:search)
  end
end
