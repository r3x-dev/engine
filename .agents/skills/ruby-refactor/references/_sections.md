# Select a Refactoring

Use this table to locate a relevant example; do not treat a category as a
severity level or a mandate to change working code.

| Prefix | Inspect this problem | Preserve or check |
| --- | --- | --- |
| `struct-` | A method or class mixes independently changing responsibilities | Caller API, visibility, state ownership, and evaluation order |
| `cond-` | Duplicated branches or hard-to-follow conditions | All fallback paths, truthiness, missing keys, and exceptions |
| `couple-` | A dependency makes an actual change difficult | Public contracts; avoid adding delegation or injection without a need |
| `idiom-` | A local expression obscures intent | Return values, block behavior, reflection, and project style |
| `data-` | Repeated fields form one domain concept | Equality, validation, coercion, mutability, and serialization |
| `pattern-` | Multiple existing behaviors need one explicit protocol | Avoid speculative factories, strategies, and null objects |
| `modern-` | Supported syntax clarifies a real operation | Ruby version, pattern failure, and input domain |
| `name-` | A name hides a domain meaning | Call sites and external compatibility |
