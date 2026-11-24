# frozen_string_literal: true

module R3x
  class DiscordPoller
    include R3x::Concerns::Logger

    Subscription = Struct.new(:workflow_class, :trigger, :cursor, :message_id)
    private_constant :Subscription

    def self.from_registry
      subscriptions = Workflow::Registry.all.flat_map do |workflow_class|
        workflow_class.triggers.grep(Triggers::DiscordMessage).map { |trigger| [workflow_class, trigger] }
      end
      new(subscriptions) unless subscriptions.empty?
    end

    def initialize(subscriptions)
      @subscriptions_by_channel = subscriptions.group_by { |_, trigger| trigger.channel_id }
      author_ids = R3x::Env.fetch!("R3X_DISCORD_ALLOWED_AUTHOR_IDS").split(",", -1).map(&:strip)
      unless author_ids.all? { |id| Client::Discord::Messages::SNOWFLAKE.match?(id) }
        raise ConfigurationError, "R3X_DISCORD_ALLOWED_AUTHOR_IDS must contain comma-separated Discord user IDs"
      end

      @allowed_author_ids = author_ids.to_set
      validate_enqueue_configuration!(subscriptions.map(&:first).uniq)
      @client = Client::Discord::Messages.new
    end

    def poll
      @subscriptions_by_channel.each do |channel_id, subscriptions|
        poll_channel(channel_id, subscriptions)
      rescue Client::Discord::Messages::RateLimited
        logger.debug { "Discord polling deferred channel_id=#{channel_id} until rate limit reset" }
      rescue HTTPX::HTTPError => error
        logger.error "Discord polling failed channel_id=#{channel_id} status=#{error.status}"
      rescue => error
        logger.error "Discord polling failed channel_id=#{channel_id} error_class=#{error.class} error_message=#{error.message}"
      end
    end

    private

    def poll_channel(channel_id, subscriptions)
      active = []
      uninitialized = []
      subscriptions.each do |workflow_class, trigger|
        keys = { workflow_key: workflow_class.workflow_key, trigger_key: trigger.unique_key }
        cursor = TriggerCursor.find_by(**keys)
        if cursor
          active << Subscription.new(workflow_class, trigger, cursor, cursor.message_id)
        else
          uninitialized << keys
        end
      end

      head = seed_subscriptions(channel_id, uninitialized) if uninitialized.any?
      after = active.map(&:message_id).min_by(&:to_i)

      # Discord's after pages select the next messages but return each page newest first.
      # https://github.com/Rapptz/discord.py/blob/master/discord/abc.py#L1824-L1834
      while active.any? && (!head || after.to_i < head.to_i)
        page = @client.page(channel_id, after:)
        page.reverse_each do |message|
          break if head && message.fetch("id").to_i > head.to_i

          active.select! { |subscription| admit(subscription, message) }
        end
        break if page.size < Client::Discord::Messages::PAGE_SIZE || active.empty?

        after = page.first.fetch("id")
        head ||= latest_id(channel_id)
      end
    end

    def seed_subscriptions(channel_id, subscriptions)
      head = latest_id(channel_id)
      subscriptions.each { |keys| TriggerCursor.seed!(**keys, message_id: head) }
      head
    end

    def latest_id(channel_id)
      @client.page(channel_id, limit: 1).first&.fetch("id") || "0"
    end

    def admit(subscription, message)
      message_id = message.fetch("id")
      return true if message_id.to_i <= subscription.message_id.to_i

      advanced = subscription.cursor.advance(from: subscription.message_id, to: message_id) do
        subscription.trigger.payloads(message, allowed_author_ids: @allowed_author_ids).each do |payload|
          enqueue!(subscription.workflow_class, subscription.trigger.unique_key, payload)
        end
      end
      subscription.message_id = message_id if advanced
      advanced
    rescue => error
      logger.error "Discord admission failed workflow_key=#{subscription.workflow_class.workflow_key} " \
        "trigger_key=#{subscription.trigger.unique_key} message_id=#{message_id} error_class=#{error.class} error_message=#{error.message}"
      false
    end

    def enqueue!(workflow_class, trigger_key, payload)
      job = workflow_class.new(trigger_key, trigger_payload: payload)
      return if job.enqueue && job.provider_job_id.present?

      raise job.enqueue_error || ActiveJob::EnqueueError.new("Discord workflow enqueue was aborted or discarded")
    end

    def validate_enqueue_configuration!(workflow_classes)
      unless SolidQueue::Job.connection_pool.equal?(TriggerCursor.connection_pool)
        raise ConfigurationError, "Discord cursors and Solid Queue must use the same connection pool"
      end

      workflow_classes.each do |workflow_class|
        unless workflow_class.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter) &&
            !workflow_class.enqueue_after_transaction_commit
          raise ConfigurationError, "Discord workflow #{workflow_class.name} must enqueue immediately to Solid Queue"
        end
      end
    end
  end
end
