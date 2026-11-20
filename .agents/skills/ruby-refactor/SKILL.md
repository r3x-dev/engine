---
name: ruby-refactor
description: Review and refactor Ruby code while preserving behavior and keeping the design simple. Use for requested Ruby design or maintainability reviews, method or class restructuring, conditional simplification, coupling reduction, or idiom adoption. Use performance-focused guidance separately when runtime optimization is the goal.
---

# Ruby Refactoring

## Workflow

1. Read the project instructions, requested scope, callers, and relevant tests.
   Check the supported Ruby and framework versions before selecting syntax.
2. Identify a concrete maintenance problem. Prefer a local simplification over
   adding a class, protocol, helper, or compatibility layer without a current need.
3. Read only the references that address that problem. Treat their examples as
   conditional alternatives, not rules that make the original code incorrect.
4. Preserve public APIs, return values, exceptions, mutation and aliasing,
   evaluation order, side effects, and nil/false distinctions. State any intended
   contract change explicitly and keep it within the user's authorized scope.
5. Apply the smallest coherent change when implementation is requested. Keep
   reviews read-only; do not turn an audit into an unrequested rewrite.
6. Run the relevant existing checks. Add regression cases for changed behavior
   boundaries; use empty, nil, false, invalid, and repeated-call inputs where
   they distinguish the implementations. Recheck only affected behavior after edits.
7. Report the concrete improvement and validation limits. Do not claim a runtime
   speedup from a design change without measurement.

Keep established project conventions unless the requested change requires an
update. Reuse decisions and authorization already present in the conversation;
ask only about unresolved choices that materially affect the result.

## Hash access contracts

- Use `fetch(key)` for required keys in structured data, such as API responses,
  configuration and serialized job state. Let a missing key raise `KeyError`.
- For a schema field whose absence intentionally means `nil`, prefer
  `fetch(key, nil)` to make that choice explicit. Ordinary optional lookups may
  use `[]` or `dig`; do not use them to hide missing required data. Explain the
  meaning of `nil` in the owning contract or a short comment when it is unclear.
- `fetch` checks key presence, not value validity: a present `nil` or `false`
  remains unchanged. Validate values at the owning boundary only when the
  contract forbids them; reuse existing validation.
- Express defaults with `fetch(key, default)` rather than `||` when `nil` or
  `false` is meaningful. Use a block for an expensive or side-effecting default.

```ruby
data.fetch("id")             # Required key; missing is an error.
data.fetch("archived_at")    # Required key; nil means not archived.
data.fetch("next_page", nil) # Optional key; absent means no next page.
```

See the [Ruby Style Guide](https://rubystyle.guide/#hash-fetch) and
[Hash#fetch documentation](https://docs.ruby-lang.org/en/4.0/Hash.html#method-i-fetch).

## Reference categories

Use the categories below for navigation, not as a severity or implementation
order. Preserve a straightforward conditional or method when it expresses the
current domain more clearly than an additional abstraction.

### 1. Structure & Decomposition

- [`struct-extract-method`](references/struct-extract-method.md) - Extract Long Methods into Focused Units
- [`struct-extract-class`](references/struct-extract-class.md) - Extract Class for Single Responsibility
- [`struct-parameter-object`](references/struct-parameter-object.md) - Introduce Parameter Object for Long Signatures
- [`struct-compose-method`](references/struct-compose-method.md) - Compose Methods at Single Abstraction Level
- [`struct-replace-method-with-object`](references/struct-replace-method-with-object.md) - Replace Complex Method with Method Object
- [`struct-single-responsibility`](references/struct-single-responsibility.md) - One Reason to Change per Class
- [`struct-flatten-deep-nesting`](references/struct-flatten-deep-nesting.md) - Flatten Deep Nesting with Early Extraction

### 2. Conditional Simplification

- [`cond-guard-clauses`](references/cond-guard-clauses.md) - Replace Nested Conditionals with Guard Clauses
- [`cond-decompose-conditional`](references/cond-decompose-conditional.md) - Extract Complex Booleans into Named Predicates
- [`cond-replace-with-polymorphism`](references/cond-replace-with-polymorphism.md) - Consider Polymorphism for Existing Variants
- [`cond-null-object`](references/cond-null-object.md) - Replace nil Checks with Null Object
- [`cond-pattern-matching`](references/cond-pattern-matching.md) - Use Pattern Matching for Structural Conditions
- [`cond-consolidate-duplicates`](references/cond-consolidate-duplicates.md) - Consolidate Duplicate Conditional Fragments

### 3. Coupling & Dependencies

- [`couple-law-of-demeter`](references/couple-law-of-demeter.md) - Enforce Law of Demeter with Delegation
- [`couple-feature-envy`](references/couple-feature-envy.md) - Move Method to Resolve Feature Envy
- [`couple-dependency-injection`](references/couple-dependency-injection.md) - Inject Dependencies via Constructor Defaults
- [`couple-composition-over-inheritance`](references/couple-composition-over-inheritance.md) - Replace Mixin with Composed Object
- [`couple-tell-dont-ask`](references/couple-tell-dont-ask.md) - Tell Objects What to Do, Don't Query Their State
- [`couple-avoid-class-methods-domain`](references/couple-avoid-class-methods-domain.md) - Avoid Class Methods in Domain Logic

### 4. Ruby Idioms

- [`idiom-prefer-enumerable`](references/idiom-prefer-enumerable.md) - Use map/select/reject Over each with Accumulator
- [`idiom-keyword-arguments`](references/idiom-keyword-arguments.md) - Use Keyword Arguments for Clarity
- [`idiom-duck-typing`](references/idiom-duck-typing.md) - Use respond_to? Over is_a? for Type Checking
- [`idiom-predicate-methods`](references/idiom-predicate-methods.md) - Name Boolean Methods with ? Suffix
- [`idiom-respond-to-missing`](references/idiom-respond-to-missing.md) - Always Pair method_missing with respond_to_missing?
- [`idiom-block-yield`](references/idiom-block-yield.md) - Use yield Over block.call for Simple Blocks
- [`idiom-implicit-return`](references/idiom-implicit-return.md) - Omit Explicit return for Last Expression

### 5. Data & Value Objects

- [`data-value-object`](references/data-value-object.md) - Replace Primitive Obsession with Value Objects
- [`data-define-immutable`](references/data-define-immutable.md) - Use Data.define for Immutable Value Objects
- [`data-encapsulate-collection`](references/data-encapsulate-collection.md) - Encapsulate Collections Behind Domain Methods
- [`data-replace-data-clump`](references/data-replace-data-clump.md) - Replace Data Clumps with Grouped Objects
- [`data-separate-query-command`](references/data-separate-query-command.md) - Separate Query Methods from Command Methods

### 6. Design Patterns

- [`pattern-strategy`](references/pattern-strategy.md) - Extract Algorithm Variations into Strategy Objects
- [`pattern-factory`](references/pattern-factory.md) - Use Factory Method to Abstract Object Creation
- [`pattern-template-method`](references/pattern-template-method.md) - Define Algorithm Skeleton with Template Method
- [`pattern-decorator`](references/pattern-decorator.md) - Wrap Objects with Decorator for Added Behavior
- [`pattern-null-object-protocol`](references/pattern-null-object-protocol.md) - Implement Null Object with Full Protocol

### 7. Modern Ruby 3.x

- [`modern-pattern-matching`](references/modern-pattern-matching.md) - Use case/in for Structural Pattern Matching
- [`modern-deconstruct-keys`](references/modern-deconstruct-keys.md) - Implement deconstruct_keys for Custom Pattern Matching
- [`modern-endless-methods`](references/modern-endless-methods.md) - Use Endless Method Definition for Simple Methods
- [`modern-hash-pattern-guard`](references/modern-hash-pattern-guard.md) - Use Pattern Matching with Guard Clauses
- [`modern-rightward-assignment`](references/modern-rightward-assignment.md) - Use Rightward Assignment for Pipeline Expressions

### 8. Naming & Readability

- [`name-intention-revealing`](references/name-intention-revealing.md) - Use Intention-Revealing Names
- [`name-consistent-vocabulary`](references/name-consistent-vocabulary.md) - Use One Word per Concept Across Codebase
- [`name-avoid-abbreviations`](references/name-avoid-abbreviations.md) - Spell Out Names Except Universal Abbreviations
- [`name-rename-to-remove-comments`](references/name-rename-to-remove-comments.md) - Rename to Eliminate Need for Comments

## Supporting references

Read [category guidance](references/_sections.md) to select an approach.
Use the [rule template](assets/templates/_template.md) when maintaining this skill.
