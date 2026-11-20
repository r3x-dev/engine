---
title: Use Data.define for Immutable Value Objects
tags: data, data-define, immutable, ruby3
---

## Use Data.define for Immutable Value Objects

Use Data.define (Ruby 3.2+) for a fixed value schema only after checking constructor, equality, hashing, serialization, and mutation contracts. Data freezes the outer object but does not deep-freeze its members. Use immutable member values or copy/freeze nested data deliberately. Do not infer a performance multiplier from the class choice.

**Before (manual boilerplate for immutability and equality):**

```ruby
class Coordinate
  attr_reader :latitude, :longitude

  def initialize(latitude:, longitude:)
    raise ArgumentError, "invalid latitude" unless (-90..90).cover?(latitude)
    raise ArgumentError, "invalid longitude" unless (-180..180).cover?(longitude)

    @latitude = latitude
    @longitude = longitude
    freeze # easy to forget, breaks immutability guarantee
  end

  def ==(other)
    other.instance_of?(self.class) &&
      latitude == other.latitude && longitude == other.longitude
  end

  def eql?(other)
    other.instance_of?(self.class) &&
      latitude.eql?(other.latitude) && longitude.eql?(other.longitude)
  end

  def hash = [self.class, latitude, longitude].hash

  def deconstruct_keys(keys)
    { latitude: latitude, longitude: longitude }
  end
end
```

**Alternative (Data.define — immutable, equatable, pattern-matchable):**

```ruby
Coordinate = Data.define(:latitude, :longitude) do
  def initialize(latitude:, longitude:)
    raise ArgumentError, "invalid latitude" unless (-90..90).cover?(latitude)
    raise ArgumentError, "invalid longitude" unless (-180..180).cover?(longitude)

    super # frozen, ==, eql?, hash, and deconstruct_keys provided automatically
  end

end

# Pattern matching works out of the box
coordinate = Coordinate.new(latitude: 51.5074, longitude: -0.1278)

case coordinate
in Coordinate[latitude: (50..55) => lat, longitude:]
  puts "UK region: #{lat}, #{longitude}"
end
```

Note: `Data.define` requires Ruby 3.2+. For earlier versions, use `Struct` with `keyword_init: true` and manual `freeze`.

Check value equality separately from hash-key equality: numeric `1` and `1.0`
compare with `==` but not `eql?`. Treat added Data constructors/methods and
changed inspection output as API differences to review, not invisible changes.
Reference: [Ruby Data](https://docs.ruby-lang.org/en/3.4/Data.html).
