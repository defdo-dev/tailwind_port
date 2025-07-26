---
name: Bug report
about: Create a report to help us improve
title: '[BUG] '
labels: 'bug'
assignees: ''

---

## Bug Description

A clear and concise description of what the bug is.

## Environment

- **TailwindPort version:** [e.g., 0.2.0]
- **Elixir version:** [e.g., 1.17.0]
- **Erlang/OTP version:** [e.g., 27.0]
- **Operating system:** [e.g., macOS 14.0, Ubuntu 22.04]
- **Tailwind CSS version:** [e.g., 3.4.1]

## Steps to Reproduce

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

## Expected Behavior

A clear and concise description of what you expected to happen.

## Actual Behavior

A clear and concise description of what actually happened.

## Code Example

```elixir
# Minimal reproducible example
{:ok, pid} = Defdo.TailwindPort.start_link(opts: [...])
# ... rest of the code that reproduces the issue
```

## Error Messages/Logs

```
Paste any error messages or relevant log output here
```

## Configuration

```elixir
# config/config.exs or relevant configuration
config :tailwind_port,
  version: "3.4.1",
  # ... other relevant config
```

## Health Information

If applicable, include health information from the affected process:

```elixir
health = Defdo.TailwindPort.health(:process_name)
IO.inspect(health)
```

## Telemetry Events

If you have telemetry handlers set up, include relevant events:

```
List any telemetry events that were (or weren't) emitted during the issue
```

## Additional Context

Add any other context about the problem here, such as:

- Does this happen consistently or intermittently?
- Did this work in a previous version?
- Are there any workarounds you've discovered?
- Any relevant network/firewall/proxy configurations?

## Possible Solution

If you have ideas about what might be causing the issue or how to fix it, please share them here.

## Impact

- [ ] Blocks development/testing
- [ ] Blocks production deployment
- [ ] Performance issue
- [ ] Documentation issue
- [ ] Minor inconvenience

## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have provided a minimal reproducible example
- [ ] I have included relevant configuration
- [ ] I have included error messages/logs
- [ ] I have specified the exact versions I'm using