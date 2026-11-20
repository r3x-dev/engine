---
title: Define Algorithm Skeleton with Template Method
tags: pattern, template-method, inheritance, hooks
---

## Define Algorithm Skeleton with Template Method

Extract an existing shared algorithm only when its sequence is a stable contract. Preserve file contents, paths, notification text, and the return value. Do not add unused extension hooks. Assume the listed exporter dependencies are supplied by the application; the CSV-like join is limited to fields without quoting or delimiter requirements.

**Before (duplicated pipeline structure across export classes):**

```ruby
class CSVExport
  def run(dataset)
    records = dataset.select(&:active?)
    records = records.sort_by(&:created_at)

    rows = records.map { |r| [r.id, r.name, r.value].join(",") }
    output = (["id,name,value"] + rows).join("\n")

    File.write("/tmp/export_#{Time.now.to_i}.csv", output)
    Notifier.send("CSV export complete")  # same structure repeated in every exporter
  end
end

class JSONExport
  def run(dataset)
    records = dataset.select(&:active?)
    records = records.sort_by(&:created_at)

    output = JSON.pretty_generate(records.map { |r| { id: r.id, name: r.name, value: r.value } })

    File.write("/tmp/export_#{Time.now.to_i}.json", output)
    Notifier.send("JSON export complete")
  end
end
```

**Alternative (base class defines skeleton, subclasses override hooks):**

```ruby
class Exporter
  def run(dataset)
    records = prepare(dataset)
    output  = format(records)
    deliver(output)  # skeleton is defined once; steps vary by subclass
  end

  private

  def prepare(dataset)
    dataset.select(&:active?).sort_by(&:created_at)
  end

  def format(records)
    raise NotImplementedError, "#{self.class}#format must be implemented"
  end

  def deliver(output)
    File.write("/tmp/export_#{Time.now.to_i}.#{file_extension}", output)
    Notifier.send("#{file_extension.upcase} export complete")
  end

  def file_extension
    raise NotImplementedError, "#{self.class}#file_extension must be implemented"
  end
end

class CSVExport < Exporter
  private

  def format(records)
    rows = records.map { |r| [r.id, r.name, r.value].join(",") }
    (["id,name,value"] + rows).join("\n")
  end

  def file_extension
    "csv"
  end
end

class JSONExport < Exporter
  private

  def format(records)
    JSON.pretty_generate(records.map { |r| { id: r.id, name: r.name, value: r.value } })
  end

  def file_extension
    "json"
  end
end
```
