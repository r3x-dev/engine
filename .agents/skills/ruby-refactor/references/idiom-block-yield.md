---
title: Use yield Over block.call for Simple Blocks
tags: idiom, yield, blocks, performance
---

## Use yield Over block.call for Simple Blocks

Prefer yield for directly invoking a required block when it improves clarity. Keep &block when storing or inspecting a block, and follow project conventions for forwarding. Do not assume Proc allocation or a fixed speedup across Ruby versions. Both examples explicitly require a block; without that precondition, block.call and yield raise different errors.

**Before (unnecessary Proc allocation via &block):**

```ruby
class EventProcessor
  def process(events, &block)
    raise ArgumentError, "block required" unless block
    events.each do |event|
      result = block.call(event)  # Call the captured block
      log_result(event, result)
    end
  end

  def with_retry(max_attempts:, &block)
    raise ArgumentError, "block required" unless block
    attempts = 0
    begin
      attempts += 1
      block.call  # Invoke the captured block
    rescue TransientError => e
      retry if attempts < max_attempts
      raise
    end
  end
end
```

**Alternative (yield avoids Proc allocation):**

```ruby
class EventProcessor
  def process(events)
    raise ArgumentError, "block required" unless block_given?
    events.each do |event|
      result = yield event  # Invoke the required block directly
      log_result(event, result)
    end
  end

  def with_retry(max_attempts:)
    raise ArgumentError, "block required" unless block_given?
    attempts = 0
    begin
      attempts += 1
      yield  # Invoke the required block
    rescue TransientError => e
      retry if attempts < max_attempts
      raise
    end
  end

  def on_complete(&block)  # &block is correct here — storing for later
    @on_complete = block
  end
end
```
