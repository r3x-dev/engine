---
title: Consolidate Duplicate Conditional Fragments
tags: cond, consolidate, duplication, dry
---

## Consolidate Duplicate Conditional Fragments

Extract genuinely shared setup/teardown while preserving branch coverage, evaluation order, return values, and exception behavior. Keep the original fallback: this example chooses JSON for every format other than :csv. Adding validation for unknown formats is a separate contract change.

**Before (duplicated setup and teardown in each branch):**

```ruby
class ReportExporter
  def export(records, format:)
    if format == :csv
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "report_#{timestamp}"
      log_export_started(filename, format)

      content = generate_csv_content(records)

      write_to_storage(filename, content, extension: "csv")
      log_export_completed(filename, format)  # duplicated in both branches
      notify_requester(filename)               # duplicated in both branches
    else
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "report_#{timestamp}"
      log_export_started(filename, format)

      content = generate_json_content(records)

      write_to_storage(filename, content, extension: "json")
      log_export_completed(filename, format)  # same as above
      notify_requester(filename)               # same as above
    end
  end
end
```

**Alternative (shared code extracted, only the difference remains in the conditional):**

```ruby
class ReportExporter
  def export(records, format:)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "report_#{timestamp}"
    log_export_started(filename, format)

    content, extension = if format == :csv
      [generate_csv_content(records), "csv"]
    else
      [generate_json_content(records), "json"]
    end

    write_to_storage(filename, content, extension: extension)
    log_export_completed(filename, format)
    notify_requester(filename)
  end
end
```
