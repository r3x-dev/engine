---
title: Use Factory Method to Abstract Object Creation
tags: pattern, factory, creation, registry
---

## Use Factory Method to Abstract Object Creation

Introduce a creation boundary when several callers share selection logic or the application genuinely needs registration. Keep one short case or a fixed mapping for a closed set. In the registry example, load and register all parsers during startup before concurrent use; preserve unknown-format errors and do not infer plugin support from the existence of a factory.

**Before (case/when tightly coupling creation to every type):**

```ruby
class DocumentProcessor
  def process(file_path)
    ext = File.extname(file_path).delete(".")

    parser = case ext
    when "json"
      JSONParser.new(file_path)
    when "xml"
      XMLParser.new(file_path)
    when "csv"
      CSVParser.new(file_path)  # every new format forces a change here
    else
      raise ArgumentError, "Unsupported format: #{ext}"
    end

    parser.parse
  end
end
```

**Alternative (registry-based factory with `.register` and `.build`):**

```ruby
class ParserFactory
  @registry = {}

  class << self
    def register(format, klass)
      @registry[format.to_s] = klass  # each parser registers itself once
    end

    def build(file_path)
      ext = File.extname(file_path).delete(".")
      klass = @registry.fetch(ext) do
        raise ArgumentError, "Unsupported format: #{ext}"
      end
      klass.new(file_path)
    end
  end
end

# Self-registration — adding a new format never touches the factory
ParserFactory.register("json", JSONParser)
ParserFactory.register("xml",  XMLParser)
ParserFactory.register("csv",  CSVParser)

class DocumentProcessor
  def process(file_path)
    parser = ParserFactory.build(file_path)
    parser.parse
  end
end
```
