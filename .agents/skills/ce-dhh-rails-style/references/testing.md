# Test expression

Use the 37signals preference for plain Minitest tests and named fixtures as a readability reference. Preserve the project's test framework, data setup, and required validation workflow.

## Tell a small domain story

Name the test for observable behavior. Choose fixture names that explain their role, such as `open_card` and `closed_card`, rather than making the reader decode numbered records.

In an existing Minitest suite, keep setup and expectations direct:

```ruby
test "closing a card records who closed it" do
  card = cards(:open_card)
  creator = users(:editor)

  card.close(creator: creator)

  assert_predicate card.reload, :closed?
  assert_equal creator, card.closure.creator
end
```

Keep assertions about the behavior that matters. Avoid expecting private helper calls merely to enforce a preferred decomposition. Keep meaningful domain state real where practical and use the project's existing external-boundary fakes.

Use request tests for HTTP behavior and browser tests when browser interaction is the contract. Choose the narrowest useful level; do not duplicate the same story across every layer or introduce another test stack for style.
