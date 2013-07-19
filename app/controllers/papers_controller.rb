class PapersController < ApplicationController
  include PapersHelper

  def show
    @paper = Paper.find_by_identifier!(params[:id])

    @scited_papers = Set.new(current_user.scited_papers) if signed_in?

    # Less naive statistical comment sorting as per
    # http://www.evanmiller.org/how-not-to-sort-by-average-rating.html
    @toplevel_comments = Comment.find_by_sql([
      "SELECT *, COALESCE(((cached_votes_up + 1.9208) / NULLIF(cached_votes_up + cached_votes_down, 0) - 1.96 * SQRT((cached_votes_up * cached_votes_down) / NULLIF(cached_votes_up + cached_votes_down, 0) + 0.9604) / NULLIF(cached_votes_up + cached_votes_down, 0)) / (1 + 3.8416 / NULLIF(cached_votes_up + cached_votes_down, 0)), 0) AS ci_lower_bound FROM comments WHERE paper_id = ? AND ancestor_id IS NULL AND (hidden = FALSE OR user_id = ?) ORDER BY ci_lower_bound DESC;",
      @paper.id,
      current_user ? current_user.id : nil
    ])

    @comment_tree = {}
    @paper.comments.where("ancestor_id IS NOT NULL").order("created_at DESC").each do |c|
      @comment_tree[c.ancestor_id] ||= []
      @comment_tree[c.ancestor_id] << c
    end

    @comments = []
    @toplevel_comments.each do |c|
      @comments << c
      @comments += @comment_tree[c.id]||[]
    end

    @categories = @paper.cross_listed_feeds.order("name").select("name").where("name != ?", @paper.feed.name)
  end

  def search
    @query = params[:q] || ''

    params.each do |key, val|
      next if val.empty?

      case key
      when 'authors'
        authors = val.split(/,\s+/)
        @query += authors.map { |au| "au:#{au}" }.join(' ')
      when 'title'
        @query += " ti:#{val}"
      when 'abstract'
        @query += " abs:#{val}"
      when 'feed'
        @query += " feed:#{val}"
      when 'general'
        @query += " #{val}"
      end
    end

    @query = @query.strip
    @search = Paper::Search.new(@query)

    # Determine which folder we should have selected
    @folder_id = @search.feed && (@search.feed.parent_id || @search.feed.id)

    @papers = @search.results.paginate(page: params[:page])
    @scited_papers = Set.new(current_user.scited_papers)
    render :search
  end

  def next
    date = parse_date params
    feed = parse_feed params

    if feed.nil? && signed_in? && current_user.has_subscriptions?
       date ||= current_user.feed_last_paper_date

      papers = current_user.feed
    else
      feed ||= Feed.default
      date ||= feed.last_paper_date

      papers = feed.cross_listed_papers
    end

    ndate = next_date(papers, date)

    if ndate.nil?
      flash[:error] = "No future papers found!"
      ndate = date
    end

    redirect_to papers_path(params.merge(date: ndate, action: nil))
  end

  def prev
    date = parse_date params
    feed = parse_feed params

    if feed.nil? && signed_in? && current_user.has_subscriptions?
      date ||= current_user.feed_last_paper_date
      papers = current_user.feed
    else
      feed ||= Feed.default
      date ||= feed.last_paper_date

      papers = feed.cross_listed_papers
    end

    pdate = prev_date(papers, date)

    if pdate.nil?
      flash[:error] = "No past papers found!"
      pdate = date
    end

    redirect_to papers_path(params.merge(date: pdate, action: nil))
  end
end
