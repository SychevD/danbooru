# frozen_string_literal: true

# Handle finding related tags by the {RelatedTagsController}. Used for finding
# related tags when tagging a post.
class RelatedTagQuery
  extend Memoist
  include ActiveModel::Serializers::JSON
  include ActiveModel::Serializers::Xml

  attr_reader :query, :post_query, :media_asset, :category, :type, :user, :limit

  def initialize(query:, media_asset: nil, user: User.anonymous, category: nil, type: nil, limit: nil)
    @user = user
    @post_query = PostQuery.normalize(query, current_user: user) # XXX This query does not include implicit metatags (rating:s, -status:deleted)
    @query = @post_query.to_s
    @media_asset = media_asset
    @category = category
    @type = type
    @limit = (limit =~ /^\d+/ ? limit.to_i : 25)
  end

  def pretty_name
    query.tr("_", " ")
  end

  def tags
    if type == "frequent"
      frequent_tags
    elsif type == "similar"
      similar_tags
    elsif type == "like"
      pattern_matching_tags("*#{query}*")
    elsif query =~ /\*/
      pattern_matching_tags(query)
    elsif category.present?
      frequent_tags
    elsif query.present?
      similar_tags
    else
      Tag.none
    end
  end

  def tags_overlap
    if type == "like" || query =~ /\*/
      {}
    else
      tags.map { |v| [v.name, v.overlap_count] }.to_h
    end
  end

  memoize def frequent_tags(category = nil)
    tags = RelatedTagCalculator.frequent_tags_for_search(post_query, category: category).take(limit)
    tags = tags.select { |t| t.category.in?(TagCategory.related_tag_categories[tag.category]) } if category.nil?
    sort_by_category(tags, category)
  end

  memoize def similar_tags(category = nil, category_top_n: 4)
    tags = RelatedTagCalculator.similar_tags_for_search(post_query, category: category)
    tags = tags.select { |t| t.category.in?(TagCategory.related_tag_categories[tag.category]) } if category.nil?
    tags = sort_by_category(tags, category)

    if category.nil?
      category_counts = Hash.new { 0 }

      tags = tags.select do |t|
        category_counts[t.category] += 1
        t.general? || category_counts[t.category] <= category_top_n
      end
    end

    tags.take(limit)
  end

  def ai_tags
    return AITag.none if media_asset.nil?

    tags = media_asset.ai_tags.includes(:tag, :aliased_tag)
    tags = tags.reject(&:is_deprecated?).reject { |t| t.empty? && !t.metatag? }
    tags = tags.sort_by { |t| [TagCategory.canonical_mapping.keys.index(t.category_name), -t.score, t.name] }
    tags.take(limit)
  end

  # Returns the top 20 most frequently added tags within the last 20 edits made by the user in the last hour.
  def recent_tags(since: 1.hour.ago, max_edits: 20, max_tags: 20)
    return [] unless user.present? && PostVersion.enabled?

    versions = PostVersion.where(updater_id: user.id).where("updated_at > ?", since).order(id: :desc).limit(max_edits)
    tags = versions.flat_map(&:added_tags)
    tags = tags.reject { |tag| tag.match?(/\A(source:|parent:|rating:)/) }
    tags = tags.group_by(&:itself).transform_values(&:size).sort_by { |tag, count| [-count, tag] }.map(&:first)
    tags = tags.take(max_tags)
    tags
  end

  def favorite_tags
    user&.favorite_tags.to_s.split
  end

  def wiki_page_tags
    wiki_page.try(:tags) || []
  end

  def serializable_hash(options = {})
    {
      query: query,
      category: category,
      tags: tags_with_categories(tags.map(&:name)),
      tags_overlap: tags_overlap,
      wiki_page_tags: tags_with_categories(wiki_page_tags),
    }
  end

  memoize def tag
    post_query.tag
  end

  def related_categories
    TagCategory.related_tag_categories[tag.category]
  end

  protected

  def sort_by_category(tags, category)
    tags.sort_by.with_index { |tag, i| [related_categories.index(tag.category), i] }
  end

  def tags_with_categories(list_of_tag_names)
    Tag.categories_for(list_of_tag_names).to_a
  end

  def category_of
    (category.present? ? Tag.categories.value_for(category) : nil)
  end

  def pattern_matching_tags(tag_query)
    tags = Tag.nonempty.name_matches(tag_query)
    tags = tags.where(category: Tag.categories.value_for(category)) if category.present?
    tags = tags.order("post_count desc, name asc").limit(limit)
    tags
  end

  def wiki_page
    WikiPage.titled(query).first
  end
end
