---
title: Wrap Objects with Decorator for Added Behavior
tags: pattern, decorator, wrapper, composition
---

## Wrap Objects with Decorator for Added Behavior

Use decorators for independently needed behavior, keeping the original wrapper order. Reordering caching, logging, and retries changes visible effects. Require the delegator and network libraries explicitly. Treat retries as an intentional policy change with bounded attempts and an idempotent operation, not an automatic addition during extraction.

**Before (subclass explosion for every combination of concerns):**

```ruby
require "net/http"

class HttpClient
  def fetch(url)
    Net::HTTP.get(URI(url))
  end
end

class LoggingHttpClient < HttpClient
  def fetch(url)
    Rails.logger.info("HTTP GET #{url}")
    result = super
    Rails.logger.info("HTTP response #{url} (#{result.bytesize} bytes)")
    result
  end
end

# CachingLoggingHttpClient, RetryLoggingHttpClient, RetryLoggingCachingHttpClient…
# each combination requires a new subclass
class CachingLoggingHttpClient < LoggingHttpClient
  def fetch(url)
    @cache ||= {}
    @cache[url] ||= super
  end
end
```

**Alternative (stacked decorators using SimpleDelegator):**

```ruby
require "net/http"
require "delegate"

class HttpClient
  def fetch(url)
    Net::HTTP.get(URI(url))
  end
end

class LoggingDecorator < SimpleDelegator
  def fetch(url)
    Rails.logger.info("HTTP GET #{url}")
    result = super  # delegates to wrapped object
    Rails.logger.info("HTTP response #{url} (#{result.bytesize} bytes)")
    result
  end
end

class CachingDecorator < SimpleDelegator
  def initialize(client)
    super
    @cache = {}
  end

  def fetch(url)
    @cache[url] ||= super
  end
end

class RetryDecorator < SimpleDelegator
  def fetch(url, retries: 3)
    raise ArgumentError, "retries must be a positive Integer" unless retries.is_a?(Integer) && retries.positive?
    attempts = 0
    begin
      attempts += 1
      super(url)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise e if attempts >= retries
      retry  # each decorator handles one concern independently
    end
  end
end

# Stack any combination without new classes
client = HttpClient.new
client = LoggingDecorator.new(client)
client = CachingDecorator.new(client)
# Add RetryDecorator only when retries are explicitly part of the contract.
client.fetch("https://api.example.com/data")
```
