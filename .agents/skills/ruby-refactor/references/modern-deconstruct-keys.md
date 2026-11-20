---
title: Implement deconstruct_keys for Custom Pattern Matching
tags: modern, deconstruct-keys, pattern-matching, protocol
---

## Implement deconstruct_keys for Custom Pattern Matching

Implement `deconstruct_keys` only when callers need hash-pattern matching on a domain object. Return the requested public fields, or all supported fields when keys is nil. Preserve the original numeric conditions: a threshold comparison is not equivalent to an integer range for zero, negative, or fractional altitudes. Use Ruby 3.0+ for the case/in examples.

**Before (manual attribute checks on domain objects):**

```ruby
class Coordinate
  attr_reader :latitude, :longitude, :altitude

  def initialize(latitude:, longitude:, altitude: nil)
    @latitude = latitude
    @longitude = longitude
    @altitude = altitude
  end
end

class FlightTracker
  def classify_position(coordinate)
    if coordinate.latitude.between?(-90, 90) && coordinate.longitude.between?(-180, 180)
      if coordinate.altitude && coordinate.altitude > 10_000  # manual accessor checks, no structural matching
        :high_altitude
      elsif coordinate.altitude
        :low_altitude
      else
        :ground_level
      end
    else
      :invalid
    end
  end
end
```

**Alternative (deconstruct_keys enables case/in on domain objects):**

```ruby
class Coordinate
  attr_reader :latitude, :longitude, :altitude

  def initialize(latitude:, longitude:, altitude: nil)
    @latitude = latitude
    @longitude = longitude
    @altitude = altitude
  end

  def deconstruct_keys(keys)  # enables pattern matching protocol for this class
    h = {}
    h[:latitude] = latitude if keys.nil? || keys.include?(:latitude)
    h[:longitude] = longitude if keys.nil? || keys.include?(:longitude)
    h[:altitude] = altitude if keys.nil? || keys.include?(:altitude)
    h
  end
end

class FlightTracker
  def classify_position(coordinate)
    case coordinate
    in { latitude:, longitude:, altitude: } if latitude.between?(-90, 90) && longitude.between?(-180, 180)
      if altitude && altitude > 10_000
        :high_altitude
      elsif altitude
        :low_altitude
      else
        :ground_level
      end
    else
      :invalid
    end
  end
end
```
