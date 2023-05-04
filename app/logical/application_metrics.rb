# frozen_string_literal: true

# Calculates metrics for the /metrics and /metrics/instance endpoints.
#
# @see app/logical/danbooru/metric.rb
# @see app/controllers/metrics_controller.rb
class ApplicationMetrics
  extend Memoist

  delegate :[], to: :process_metrics

  # The Puma worker ID identifies the current Puma process. Each worker gets an ID from 0 to num_workers-1. Every time a
  # worker is killed, a new worker is started with a new PID but the same worker ID.
  #
  # Set in config/puma.rb.
  attr_accessor :puma_worker_id

  # @param [ApplicationMetrics] The singleton instance. Class methods are delegated to this.
  def self.instance
    @instance ||= new
  end

  # Returns metrics related to the site as a whole. This mostly consists of the sizes of various database tables.
  #
  # @return [Danbooru::Metric::Set] The set of application metrics.
  def application_metrics
    metrics = Danbooru::Metric::Set.new({
      danbooru_info:                                [:counter, "Information about the current application build."],
      danbooru_artists_total:                       [:gauge,   "The total number of artists."],
      danbooru_artist_urls_total:                   [:gauge,   "The total number of artist URLs."],
      danbooru_artist_versions_total:               [:counter, "The total number of artist versions."],
      danbooru_background_jobs_total:               [:gauge,   "The total number of background jobs."],
      danbooru_bans_total:                          [:gauge,   "The total number of user bans."],
      danbooru_bulk_update_requests_total:          [:gauge,   "The total number of bulk update requests."],
      danbooru_comments_total:                      [:gauge,   "The total number of comments."],
      danbooru_comment_votes_total:                 [:gauge,   "The total number of comment votes."],
      danbooru_favorites_total:                     [:gauge,   "The total number of favorites."],
      danbooru_favorite_groups_total:               [:gauge,   "The total number of favorite groups."],
      danbooru_forum_posts_total:                   [:gauge,   "The total number of forum posts."],
      danbooru_forum_topics_total:                  [:gauge,   "The total number of forum topics."],
      danbooru_media_assets_total:                  [:gauge,   "The total number of media assets. Excludes processing or failed assets."],
      danbooru_media_assets_file_size_bytes_total:  [:gauge,   "The total file size of all active media assets. Does not include thumbnails."],
      danbooru_media_assets_pixels_total:           [:gauge,   "The total number of pixels in all active media assets (that is, the sum of width * height for all images). Does not account for animated images."],
      danbooru_media_assets_duration_seconds_total: [:gauge,   "The total runtime of all active media assets. Includes videos, animated GIFs and PNGs, and ugoiras."],
      danbooru_post_votes_total:                    [:gauge,   "The total number of post votes."],
      danbooru_posts_total:                         [:gauge,   "The total number of posts."],
      danbooru_post_appeals_total:                  [:gauge,   "The total number of post appeals."],
      danbooru_post_flags_total:                    [:gauge,   "The total number of post flags."],
      danbooru_notes_total:                         [:gauge,   "The total number of notes."],
      danbooru_note_versions_total:                 [:counter, "The total number of note versions."],
      danbooru_pools_total:                         [:gauge,   "The total number of pools."],
      danbooru_pools_post_count_total:              [:gauge,   "The total number of posts in pools."],
      danbooru_tags_total:                          [:gauge,   "The total number of tags (excluding empty tags)."],
      danbooru_tags_post_count_total:               [:gauge,   "The total number of tags on posts."],
      danbooru_uploads_total:                       [:gauge,   "The total number of uploads."],
      danbooru_users_total:                         [:counter, "The total number of users."],
      danbooru_user_feedbacks_total:                [:gauge,   "The total number of user feedbacks (excluding deleted feedbacks)."],
      danbooru_wiki_pages_total:                    [:gauge,   "The total number of wiki pages."],
      danbooru_wiki_page_versions_total:            [:counter, "The total number of wiki page versions."],
    })

    status = ServerStatus.new
    versions = {
      danbooru_version: status.danbooru_version,
      ruby_version: status.ruby_version,
      rails_version: status.rails_version,
      puma_version: status.puma_version,
      distro_version: status.distro_version,
      libvips_version: status.libvips_version,
      ffmpeg_version: status.ffmpeg_version,
      exiftool_version: status.exiftool_version,
    }
    metrics[:danbooru_info][versions].set(1)

    Artist.group(:is_deleted).pluck(Arel.sql("is_deleted, COUNT(*)")).each do |deleted, count|
      metrics[:danbooru_artists_total][deleted: deleted].set(count)
    end

    ArtistURL.group(:is_active).pluck(Arel.sql("is_active, COUNT(*)")).each do |active, count|
      metrics[:danbooru_artist_urls_total][active: active].set(count)
    end

    ArtistVersion.pluck(Arel.sql("COUNT(*)")).each do |count|
      metrics[:danbooru_artist_versions_total].set(count)
    end

    metrics[:danbooru_background_jobs_total][status: "queued"].set(BackgroundJob.queued.count)
    metrics[:danbooru_background_jobs_total][status: "running"].set(BackgroundJob.running.count)
    metrics[:danbooru_background_jobs_total][status: "finished"].set(BackgroundJob.finished.count)
    metrics[:danbooru_background_jobs_total][status: "discarded"].set(BackgroundJob.discarded.count)

    Ban.pluck(Arel.sql("COUNT(*)")).each do |count|
      metrics[:danbooru_bans_total].set(count)
    end

    BulkUpdateRequest.group(:status).pluck(Arel.sql("status, COUNT(*)")).each do |status, count|
      metrics[:danbooru_bulk_update_requests_total][status: status].set(count)
    end

    Comment.group(:is_deleted).pluck(Arel.sql("is_deleted, COUNT(*)")).each do |deleted, count|
      metrics[:danbooru_comments_total][deleted: deleted].set(count)
    end

    CommentVote.group(:score).active.pluck(Arel.sql("score, COUNT(*)")).each do |score, count, score_sum|
      metrics[:danbooru_comment_votes_total][type: score > 0 ? "up" : "down"].set(count)
    end

    FavoriteGroup.group(:is_public).pluck(Arel.sql("is_public, COUNT(*)")).each do |is_public, count|
      metrics[:danbooru_favorite_groups_total][public: is_public].set(count)
    end

    ForumPost.group(:is_deleted).pluck(Arel.sql("is_deleted, COUNT(*)")).each do |deleted, count|
      metrics[:danbooru_forum_posts_total][deleted: deleted].set(count)
    end

    ForumTopic.group(:is_deleted).pluck(Arel.sql("is_deleted, COUNT(*)")).each do |deleted, count|
      metrics[:danbooru_forum_topics_total][deleted: deleted].set(count)
    end

    MediaAsset.active.group(:file_ext).pluck(Arel.sql("file_ext, COUNT(*), SUM(file_size), SUM(image_width*image_height), COALESCE(SUM(duration), 0)")).each do |file_ext, count, file_size, pixels, duration|
      metrics[:danbooru_media_assets_total][file_ext: file_ext].set(count)
      metrics[:danbooru_media_assets_file_size_bytes_total][file_ext: file_ext].set(file_size)
      metrics[:danbooru_media_assets_pixels_total][file_ext: file_ext].set(pixels)
      metrics[:danbooru_media_assets_duration_seconds_total][file_ext: file_ext].set(duration.round(4))
    end

    Post.pluck(Arel.sql("SUM(up_score), ABS(SUM(down_score)), SUM(fav_count), COUNT(*) FILTER (WHERE is_pending), COUNT(*) FILTER (WHERE is_flagged), COUNT(*) FILTER (WHERE is_deleted), COUNT(*)")).each do |upvote_count, downvote_count, favorite_count, pending_count, flagged_count, deleted_count, total_count|
      metrics[:danbooru_post_votes_total][type: "up"].set(upvote_count)
      metrics[:danbooru_post_votes_total][type: "down"].set(downvote_count)
      metrics[:danbooru_favorites_total].set(favorite_count)

      metrics[:danbooru_posts_total][status: "pending"].set(pending_count)
      metrics[:danbooru_posts_total][status: "flagged"].set(flagged_count)
      metrics[:danbooru_posts_total][status: "deleted"].set(deleted_count)
      metrics[:danbooru_posts_total][status: "active"].set(total_count - pending_count - deleted_count - flagged_count)
    end

    PostAppeal.group(:status).pluck(Arel.sql("status, COUNT(*)")).each do |status, count|
      metrics[:danbooru_post_appeals_total][status: status].set(count)
      metrics[:danbooru_posts_total][status: "appealed"].set(count) if status == "pending"
    end

    PostFlag.group(:status).pluck(Arel.sql("status, COUNT(*)")).each do |status, count|
      metrics[:danbooru_post_flags_total][status: status].set(count)
    end

    Note.group(:is_active).pluck(Arel.sql("is_active, COUNT(*)")).each do |active, count|
      metrics[:danbooru_notes_total][deleted: !active].set(count)
    end

    NoteVersion.pluck(Arel.sql("COUNT(*)")).each do |count|
      metrics[:danbooru_note_versions_total].set(count)
    end

    Pool.group(:category).pluck(Arel.sql("category, COUNT(*), SUM(cardinality(post_ids))")).each do |category, count, post_count|
      metrics[:danbooru_pools_total][category: category].set(count)
      metrics[:danbooru_pools_post_count_total][category: category].set(post_count)
    end

    Tag.nonempty.group(:category).pluck(Arel.sql("category, COUNT(*), SUM(post_count)")).each do |category, count, post_count|
      metrics[:danbooru_tags_total][category: TagCategory.reverse_mapping[category]].set(count)
      metrics[:danbooru_tags_post_count_total][category: TagCategory.reverse_mapping[category]].set(post_count)
    end

    Upload.group(:status).pluck(Arel.sql("status, COUNT(*)")).each do |status, count|
      metrics[:danbooru_uploads_total][status: status].set(count)
    end

    User.pluck(Arel.sql("COUNT(*)")).each do |count|
      metrics[:danbooru_users_total].set(count)
    end

    UserFeedback.active.group(:category).pluck(Arel.sql("category, COUNT(*)")).each do |category, count|
      metrics[:danbooru_user_feedbacks_total][category: category].set(count)
    end

    WikiPage.group(:is_deleted).pluck(Arel.sql("is_deleted, COUNT(*)")).each do |deleted, count|
      metrics[:danbooru_wiki_pages_total][deleted: deleted].set(count)
    end

    WikiPageVersion.pluck(Arel.sql("COUNT(*)")).each do |count|
      metrics[:danbooru_wiki_page_versions_total].set(count)
    end

    metrics
  end

  # Returns metrics related to the current Ruby process. A Danbooru instance normally consists of a Puma server running
  # several worker processes. Metrics from each process are combined together below in `#instance_metrics`.
  #
  # @return [Danbooru::Metric::Set] The set of metrics for this process.
  memoize def process_metrics
    metrics = Danbooru::Metric::Set.new({
      target_info:     [:gauge, "Information about the current application instance."],
    })

    status = ServerStatus.new
    metrics[:target_info][{
      pod_name:         status.container_name,
      node_name:        status.node_name,
      ruby_version:     status.ruby_version,
      rails_version:    status.rails_version,
      puma_version:     status.puma_version,
      danbooru_version: status.danbooru_version,
    }].set(1)

    if puma_running?
      metrics.register({
        # Global Puma metrics (not tied to the current process)
        puma_started_at: [:counter, "When the master process started."],
        puma_workers:    [:gauge,   "Number of configured worker processes."],

        # Worker-specific Puma metrics (tied to a single Puma worker process)
        puma_worker_started_at:     [:counter, "When the worker last restarted. Workers are periodically restarted to prevent memory bloat."],
        puma_worker_last_checkin:   [:counter, "When the worker last checked in with the master process."],
        puma_worker_restart_count:  [:counter, "Total number of times this worker has restarted (including initial start)."],
        puma_worker_max_threads:    [:gauge,   "Number of configured worker threads."],
        puma_worker_running:        [:gauge,   "Current number of worker threads."],
        puma_worker_pool_capacity:  [:gauge,   "Current number of idle worker threads."],
        puma_worker_backlog:        [:gauge,   "Current number of accepted connections waiting for an idle worker thread."],
        puma_worker_socket_backlog: [:gauge,   "Current number of unaccepted connections."],
        puma_worker_requests_count: [:counter, "Total number of requests served since the worker started."],
      })
    end

    metrics.register({
      rack_exceptions_total:                           [:counter, "Total number of exceptions not caught by Rails."],
      rails_exceptions_total:                          [:counter, "Total number of exceptions caught by Rails."],

      rails_jobs_enqueued_total:                       [:counter, "Total number of background jobs successfully enqueued. Does not include foreground jobs."],
      rails_jobs_attempts_total:                       [:counter, "Total number of jobs attempted to be worked. Includes successful jobs, failed jobs, and retried jobs."],
      rails_jobs_worked_total:                         [:counter, "Total number of jobs successfully worked."],
      rails_jobs_retries_total:                        [:counter, "Total number of jobs retried after a failure."],
      rails_jobs_exceptions_total:                     [:counter, "Total number of jobs failed due to an exception."],
      rails_jobs_duration_seconds:                     [:counter, "Time spent working jobs. Does not include time spent enqueuing jobs, or waiting for queued jobs to be worked."],
      rails_jobs_queue_duration_seconds:               [:counter, "Time spent waiting on jobs to be worked. Does not include time spent enqueuing jobs."],
      rails_jobs_enqueue_duration_seconds:             [:counter, "Time spent adding jobs to the queue."],

      rails_connection_pool_size:                      [:gauge, "Maximum number of database connections in the pool."],
      rails_connection_pool_connections:               [:gauge, "Current number of database connections by state."],
      rails_connection_pool_waiting:                   [:gauge, "Current number of threads blocked waiting to checkout a database connection."],
      rails_connection_pool_checkout_timeout:          [:gauge, "Maxmimum amount of time to wait on checking out a database connection."],

      ruby_pid:                                        [:gauge,   "Current process ID."],
      ruby_thread_count:                               [:gauge,   "Current number of threads."],
      ruby_vm_constant_cache_invalidations:            [:counter, "Total number of constant cache invalidations."],
      ruby_vm_constant_cache_misses:                   [:counter, "Total number of constant cache misses."],
      ruby_objects_count:                              [:gauge,   "Current number of Ruby objects by type."],

      ruby_gc_count:                                   [:counter, "Total number of garbage collections since process start (includes both major and minor collections)."],
      ruby_gc_major_gc_count:                          [:counter, "Total number of major garbage collections."],
      ruby_gc_minor_gc_count:                          [:counter, "Total number of minor garbage collections."],
      ruby_gc_duration_seconds:                        [:counter, "Time spent in garbage collection since process start."],
      ruby_gc_heap_allocated_pages:                    [:gauge,   "Current number of allocated heap pages (eden pages + tomb pages)."],
      ruby_gc_heap_eden_pages:                         [:gauge,   "Current number of unfreeable heap pages (pages that contain at least one live object)."],
      ruby_gc_heap_tomb_pages:                         [:gauge,   "Current number of freeable heap pages (pages that don't contain any live objects)."],
      ruby_gc_heap_sorted_length:                      [:gauge,   "Current number of pages that can fit into the buffer that holds references to all pages."],
      ruby_gc_heap_allocatable_pages:                  [:gauge,   "Current number of pages the application could allocate without additional GC."],
      ruby_gc_heap_available_slots:                    [:gauge,   "Current number of object slots in all heap_allocated_pages."],
      ruby_gc_heap_live_slots:                         [:gauge,   "Current number of object slots which contain live objects."],
      ruby_gc_heap_free_slots:                         [:gauge,   "Current number of object slots which do not contain live objects."],
      ruby_gc_heap_final_slots:                        [:gauge,   "Current number of object slots with finalizers attached to them."],
      ruby_gc_heap_marked_slots:                       [:gauge,   "Number of objects marked in the last GC."],
      ruby_gc_total_allocated_pages:                   [:counter, "Total number of pages allocated since process start."],
      ruby_gc_total_freed_pages:                       [:counter, "Total number of pages freed since process start."],
      ruby_gc_total_allocated_objects:                 [:counter, "Total number of objects allocated since process start."],
      ruby_gc_total_freed_objects:                     [:counter, "Total number of objects freed since process start."],
      ruby_gc_malloc_increase_bytes:                   [:gauge,   "Current amount of memory allocated on the heap for objects. Decreased by major or minor GC."],
      ruby_gc_malloc_increase_bytes_limit:             [:gauge,   "When malloc_increase_bytes crosses this limit, GC is triggered."],
      ruby_gc_compact_count:                           [:counter, "Total number of heap compactions."],
      ruby_gc_read_barrier_faults:                     [:counter, "Total number of times the read barrier was triggered during compaction."],
      ruby_gc_total_moved_objects:                     [:counter, "Total number of objects heap compaction has moved."],
      ruby_gc_remembered_wb_unprotected_objects:       [:gauge,   "Current number of objects without write barriers in the remembered set."],
      ruby_gc_remembered_wb_unprotected_objects_limit: [:gauge,   "When remembered_wb_unprotected_objects crosses this limit, major GC is triggered."],
      ruby_gc_old_objects:                             [:gauge,   "Number of live, old objects which survived at least 3 garbage collections."],
      ruby_gc_old_objects_limit:                       [:gauge,   "When old_objects crosses this limit, major GC is triggered."],
      ruby_gc_oldmalloc_increase_bytes:                [:gauge,   "Current amount of memory allocated on the heap for old objects. Decreased by major GC."],
      ruby_gc_oldmalloc_increase_bytes_limit:          [:gauge,   "When old_malloc_increase_bytes crosses this limit, major GC is triggered."],

      ruby_gc_pool_heap_allocatable_pages:             [:gauge,   "Current number of pages the application could allocate without additional GC."],
      ruby_gc_pool_heap_eden_pages:                    [:gauge,   "Current number of unfreeable heap pages (pages that contain at least one live object)."],
      ruby_gc_pool_heap_eden_slots:                    [:gauge,   "Current number of object slots in eden pages."],
      ruby_gc_pool_heap_tomb_pages:                    [:gauge,   "Current number of freeable heap pages (pages that don't contain any live objects)."],
      ruby_gc_pool_heap_tomb_slots:                    [:gauge,   "Current number of object slots in tomb pages."],
      ruby_gc_pool_total_allocated_pages:              [:counter, "Total number of pages allocated since process start."],
      ruby_gc_pool_total_freed_pages:                  [:counter, "Total number of pages freed since process start."],
      ruby_gc_pool_force_major_gc_count:               [:counter, "Total number of times a major GC was caused by running out of free slots."],

      ruby_yjit_enabled:                               [:gauge,   "Whether YJIT is enabled."],
      ruby_yjit_inline_code_size:                      [:gauge,   "Inlined code size."],
      ruby_yjit_outlined_code_size:                    [:gauge,   "Outlined code size."],
      ruby_yjit_freed_page_count:                      [:counter, "Total number of garbage collected pages."],
      ruby_yjit_freed_code_size:                       [:gauge,   "Total size of garbage collected code"],
      ruby_yjit_live_page_count:                       [:counter, "Current number of live pages."],
      ruby_yjit_code_gc_count:                         [:counter, "Total number of code garbage collections."],
      ruby_yjit_code_region_size:                      [:gauge,   "Size in bytes of memory region allocated for JIT code."],
      ruby_yjit_object_shape_count:                    [:gauge,   "Current number of object shapes."],
    }, { worker: puma_worker_id })

    metrics
  end

  # Updates metrics related to the current running Ruby process.
  #
  # @return [Danbooru::Metric::Set] The set of metrics for this process.
  def update_process_metrics
    metrics = process_metrics

    conn_pool_stats = ApplicationRecord.connection_pool.stat
    metrics[:rails_connection_pool_size][{}].set(conn_pool_stats[:size])
    metrics[:rails_connection_pool_connections][state: "busy"].set(conn_pool_stats[:busy])
    metrics[:rails_connection_pool_connections][state: "idle"].set(conn_pool_stats[:idle])
    metrics[:rails_connection_pool_connections][state: "dead"].set(conn_pool_stats[:dead])
    metrics[:rails_connection_pool_waiting][{}].set(conn_pool_stats[:waiting])
    metrics[:rails_connection_pool_checkout_timeout][{}].set(conn_pool_stats[:checkout_timeout])

    if puma_running?
      resp = Danbooru::Http.internal.timeout(1).get("http://localhost:9293/stats")
      puma_stats = resp.code == 200 ? resp.parse.with_indifferent_access : {}

      metrics.set({
        puma_started_at: puma_stats[:started_at].to_s.to_time.to_i,
        puma_workers:    puma_stats[:workers],
      })

      puma_stats[:worker_status].to_a.each do |worker|
        metrics.set({
          puma_worker_started_at:     Time.parse(worker[:started_at]).to_i,
          puma_worker_last_checkin:   Time.parse(worker[:last_checkin]).to_i,
          puma_worker_running:        worker.dig(:last_status, :running),
          puma_worker_backlog:        worker.dig(:last_status, :backlog),
          puma_worker_pool_capacity:  worker.dig(:last_status, :pool_capacity),
          puma_worker_max_threads:    worker.dig(:last_status, :max_threads),
          puma_worker_requests_count: worker.dig(:last_status, :requests_count),
        }, { worker: worker[:index] })
      end

      # XXX The Puma server object is in a thread local variable, which may be in another thread, so we have to search for it.
      puma_socket = Thread.list.filter_map { |thread| thread[:puma_server] }.first&.binder&.ios&.first
      puma_socket_backlog = puma_socket&.getsockopt(Socket::SOL_TCP, Socket::TCP_INFO)&.inspect.to_s[/unacked=(\d+)/, 1].to_i
      metrics[:puma_worker_socket_backlog][worker: puma_worker_id].set(puma_socket_backlog)
    end

    ruby_stats = RubyVM.stat
    metrics.set({
      ruby_vm_constant_cache_invalidations: ruby_stats[:constant_cache_invalidations],
      ruby_vm_constant_cache_misses:        ruby_stats[:constant_cache_misses],
      ruby_thread_count:                    Thread.list.count,
      ruby_pid:                             Process.pid,
    })

    object_stats = ObjectSpace.count_objects
    metrics[:ruby_objects_count][type: "free"    ].set(object_stats[:FREE])
    metrics[:ruby_objects_count][type: "object"  ].set(object_stats[:T_OBJECT])
    metrics[:ruby_objects_count][type: "class"   ].set(object_stats[:T_CLASS])
    metrics[:ruby_objects_count][type: "module"  ].set(object_stats[:T_MODULE])
    metrics[:ruby_objects_count][type: "float"   ].set(object_stats[:T_FLOAT])
    metrics[:ruby_objects_count][type: "string"  ].set(object_stats[:T_STRING])
    metrics[:ruby_objects_count][type: "regexp"  ].set(object_stats[:T_REGEXP])
    metrics[:ruby_objects_count][type: "array"   ].set(object_stats[:T_ARRAY])
    metrics[:ruby_objects_count][type: "hash"    ].set(object_stats[:T_HASH])
    metrics[:ruby_objects_count][type: "struct"  ].set(object_stats[:T_STRUCT])
    metrics[:ruby_objects_count][type: "bignum"  ].set(object_stats[:T_BIGNUM])
    metrics[:ruby_objects_count][type: "file"    ].set(object_stats[:T_FILE])
    metrics[:ruby_objects_count][type: "data"    ].set(object_stats[:T_DATA])
    metrics[:ruby_objects_count][type: "match"   ].set(object_stats[:T_MATCH])
    metrics[:ruby_objects_count][type: "complex" ].set(object_stats[:T_COMPLEX])
    metrics[:ruby_objects_count][type: "rational"].set(object_stats[:T_RATIONAL])
    metrics[:ruby_objects_count][type: "symbol"  ].set(object_stats[:T_SYMBOL])
    metrics[:ruby_objects_count][type: "imemo"   ].set(object_stats[:T_IMEMO])
    metrics[:ruby_objects_count][type: "iclass"  ].set(object_stats[:T_ICLASS])

    ruby_yjit_stats = defined?(RubyVM::YJIT) ? RubyVM::YJIT.runtime_stats : Hash.new { 0 }
    metrics.set({
      ruby_yjit_enabled:            ruby_yjit_stats.present?,
      ruby_yjit_inline_code_size:   ruby_yjit_stats[:inline_code_size],
      ruby_yjit_outlined_code_size: ruby_yjit_stats[:outlined_code_size],
      ruby_yjit_freed_page_count:   ruby_yjit_stats[:freed_page_count],
      ruby_yjit_freed_code_size:    ruby_yjit_stats[:freed_code_size],
      ruby_yjit_live_page_count:    ruby_yjit_stats[:live_page_count],
      ruby_yjit_code_gc_count:      ruby_yjit_stats[:code_gc_count],
      ruby_yjit_code_region_size:   ruby_yjit_stats[:code_region_size],
      ruby_yjit_object_shape_count: ruby_yjit_stats[:object_shape_count],
    })

    gc_stats = GC.stat
    metrics.set({
      ruby_gc_count:                                   gc_stats[:count],
      ruby_gc_duration_seconds:                        gc_stats[:time] / 1000.0,
      ruby_gc_heap_allocated_pages:                    gc_stats[:heap_allocated_pages],
      ruby_gc_heap_sorted_length:                      gc_stats[:heap_sorted_length],
      ruby_gc_heap_allocatable_pages:                  gc_stats[:heap_allocatable_pages],
      ruby_gc_heap_available_slots:                    gc_stats[:heap_available_slots],
      ruby_gc_heap_live_slots:                         gc_stats[:heap_live_slots],
      ruby_gc_heap_free_slots:                         gc_stats[:heap_free_slots],
      ruby_gc_heap_final_slots:                        gc_stats[:heap_final_slots],
      ruby_gc_heap_marked_slots:                       gc_stats[:heap_marked_slots],
      ruby_gc_heap_eden_pages:                         gc_stats[:heap_eden_pages],
      ruby_gc_heap_tomb_pages:                         gc_stats[:heap_tomb_pages],
      ruby_gc_total_allocated_pages:                   gc_stats[:total_allocated_pages],
      ruby_gc_total_freed_pages:                       gc_stats[:total_freed_pages],
      ruby_gc_total_allocated_objects:                 gc_stats[:total_allocated_objects],
      ruby_gc_total_freed_objects:                     gc_stats[:total_freed_objects],
      ruby_gc_malloc_increase_bytes:                   gc_stats[:malloc_increase_bytes],
      ruby_gc_malloc_increase_bytes_limit:             gc_stats[:malloc_increase_bytes_limit],
      ruby_gc_minor_gc_count:                          gc_stats[:minor_gc_count],
      ruby_gc_major_gc_count:                          gc_stats[:major_gc_count],
      ruby_gc_compact_count:                           gc_stats[:compact_count],
      ruby_gc_read_barrier_faults:                     gc_stats[:read_barrier_faults],
      ruby_gc_total_moved_objects:                     gc_stats[:total_moved_objects],
      ruby_gc_remembered_wb_unprotected_objects:       gc_stats[:remembered_wb_unprotected_objects],
      ruby_gc_remembered_wb_unprotected_objects_limit: gc_stats[:remembered_wb_unprotected_objects_limit],
      ruby_gc_old_objects:                             gc_stats[:old_objects],
      ruby_gc_old_objects_limit:                       gc_stats[:old_objects_limit],
      ruby_gc_oldmalloc_increase_bytes:                gc_stats[:oldmalloc_increase_bytes],
      ruby_gc_oldmalloc_increase_bytes_limit:          gc_stats[:oldmalloc_increase_bytes_limit],
    })

    gc_object_pool_stats = GC.stat_heap
    gc_object_pool_stats.each do |pool_id, pool_stats|
      metrics.set({
        ruby_gc_pool_heap_allocatable_pages: pool_stats[:heap_allocatable_pages],
        ruby_gc_pool_heap_eden_pages:        pool_stats[:heap_eden_pages],
        ruby_gc_pool_heap_eden_slots:        pool_stats[:heap_eden_slots],
        ruby_gc_pool_heap_tomb_pages:        pool_stats[:heap_tomb_pages],
        ruby_gc_pool_heap_tomb_slots:        pool_stats[:heap_tomb_slots],
        ruby_gc_pool_total_allocated_pages:  pool_stats[:heap_total_allocated_pages],
        ruby_gc_pool_total_freed_pages:      pool_stats[:heap_total_freed_pages],
        ruby_gc_pool_force_major_gc_count:   pool_stats[:heap_force_major_gc_count],
      }, { slot_size: pool_stats[:slot_size] })
    end

    metrics
  end

  def puma_running?
    puma_worker_id.present?
  end

  # Resets the process metrics (by flushing the memoize cache).
  def reset_metrics
    flush_cache
    self
  end

  # Collects metrics from each Puma worker process and combines them into a single set of metrics for /metrics/instance.
  #
  # @return [Danbooru::Metric::Set] The combined set of metrics from each Puma worker process.
  def instance_metrics
    metrics = Dir.glob("tmp/drb-process-metrics-*.sock").map do |filename|
      application_metrics = DRbObject.new_with_uri("drbunix:#{filename}")
      application_metrics.update_process_metrics
    rescue IOError, DRb::DRbConnError
      # XXX Ignore any errors we may receive when fetching metrics from a remote process that has shut down (usually by the Puma worker killer)
      Danbooru::Metric::Set.new
    end

    metrics.reduce(&:merge) || Danbooru::Metric::Set.new
  end

  # Makes metrics for the current process available to other Puma worker processes. Starts a background thread serving process
  # metrics on a Unix domain socket under tmp/. Called by each process on startup in config/puma.rb.
  def serve_process_metrics
    filename = "tmp/drb-process-metrics-#{puma_worker_id}.sock"
    FileUtils.rm_f(filename)
    DRb.start_service("drbunix:#{filename}", ApplicationMetrics.instance)
  end

  class << self
    # For each instance method, define a class method that delegates to the singleton instance.
    delegate *ApplicationMetrics.instance_methods(false), to: :instance
  end
end
