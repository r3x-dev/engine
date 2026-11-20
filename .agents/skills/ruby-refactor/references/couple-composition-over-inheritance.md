---
title: Replace Mixin with Composed Object
tags: couple, composition, mixin, module, inheritance
---

## Replace Mixin with Composed Object

Consider composition for an actual method collision or unclear state ownership. Ruby lookup order is deterministic; inspect ancestors and super before changing it. Preserve the existing public method and winning behavior, and add new capabilities only within the requested scope. Do not replace every mixin with a collaborator.

**Before (multiple includes with hidden conflict):**

```ruby
module Searchable
  def search(query)
    # Full-text search across all fields
    records.select { |r| r.values.any? { |v| v.to_s.include?(query) } }
  end
end

module Filterable
  def search(query)
    # Filters by exact match — silently overrides Searchable#search
    records.select { |r| r[:name] == query }
  end
end

class ProductCatalog
  include Searchable
  include Filterable  # ancestors: Filterable wins — Searchable#search is dead code

  attr_reader :records

  def initialize(records)
    @records = records
  end
end
```

**Alternative (composed objects with explicit interfaces):**

```ruby
class SearchEngine
  def initialize(records)
    @records = records
  end

  def search(query)
    @records.select { |r| r.values.any? { |v| v.to_s.include?(query) } }
  end
end

class Filter
  def initialize(records)
    @records = records
  end

  def search(query)
    @records.select { |r| r[:name] == query }
  end
end

class ProductCatalog
  attr_reader :records

  def initialize(records, search_engine: SearchEngine.new(records), filter: Filter.new(records))
    @records = records
    @search_engine = search_engine
    @filter = filter
  end

  # No conflict — each collaborator has its own object and name
  def search(query) = @filter.search(query)  # Preserve the existing exact-match API.
  def full_text_search(query) = @search_engine.search(query)  # Optional new capability.
end
```
