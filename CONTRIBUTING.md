# Contributing to TailwindPort

Thank you for your interest in contributing to TailwindPort! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Code of Conduct

This project adheres to a code of conduct that promotes a welcoming and inclusive environment. By participating, you are expected to uphold this standard.

### Our Standards

- **Be respectful**: Treat all community members with respect and courtesy
- **Be inclusive**: Welcome newcomers and help them get started
- **Be constructive**: Provide helpful feedback and suggestions
- **Be patient**: Remember that everyone has different experience levels
- **Be collaborative**: Work together to improve the project

## Getting Started

### Prerequisites

- Elixir 1.14+ 
- Erlang/OTP 24+
- Git
- GitHub account

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tailwind_cli_port.git
   cd tailwind_cli_port
   ```

3. Add the upstream remote:
   ```bash
   git remote add upstream https://github.com/defdo-dev/tailwind_cli_port.git
   ```

## Development Setup

### Install Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Install development tools
mix local.hex --force
mix local.rebar --force
```

### Verify Setup

```bash
# Run tests to ensure everything works
mix test

# Check code formatting
mix format --check-formatted

# Run static analysis
mix credo
mix dialyzer
```

### Development Workflow

1. **Stay up to date**:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**

4. **Test your changes**:
   ```bash
   mix test
   mix format
   mix credo
   ```

5. **Commit and push**:
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   git push origin feature/your-feature-name
   ```

## Making Changes

### Code Style

- Follow Elixir community conventions
- Use `mix format` for consistent formatting
- Pass `mix credo --strict` for code quality
- Include typespecs for public functions
- Write clear, descriptive function and variable names

### Architecture Guidelines

#### Telemetry Integration

All new features should include comprehensive telemetry:

```elixir
# Emit events at key points
Telemetry.emit_event([:tailwind_port, :feature, :start], measurements, metadata)

# Use span tracking for operations
result = Telemetry.span_compilation(fn ->
  # Your operation here
end, metadata, span_name: "operation_name")
```

#### Error Handling

Follow the established error categorization pattern:

```elixir
# Define specific error types
@type feature_error :: 
  {:validation_error, term()} |
  {:network_error, term()} |
  {:system_error, term()}

# Categorize errors for telemetry
defp categorize_error({:validation_error, _}), do: :validation
defp categorize_error({:network_error, _}), do: :network
defp categorize_error({:system_error, _}), do: :system
```

#### Health Monitoring

Include health metrics for new functionality:

```elixir
# Update health metrics
@spec update_feature_metrics(Health.health_metrics()) :: Health.health_metrics()
def update_feature_metrics(health) do
  Map.update!(health, :feature_count, &(&1 + 1))
end
```

### Commit Message Guidelines

Use conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `style:` - Code style changes (no functional changes)
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `test:` - Test additions or modifications
- `chore:` - Build process or auxiliary tool changes

**Examples:**
```
feat(telemetry): add span tracking for downloads
fix(health): resolve memory leak in metrics calculation
docs(usage): add Phoenix integration examples
```

## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run tests with coverage
mix coveralls

# Run tests with detailed output
mix test --trace

# Run specific test file
mix test test/path/to/test_file.exs

# Run tests matching a pattern
mix test --only tag:integration
```

### Writing Tests

#### Unit Tests

```elixir
defmodule MyModuleTest do
  use ExUnit.Case
  
  describe "function_name/2" do
    test "handles valid input correctly" do
      # Arrange
      input = "test_input"
      expected = "expected_output"
      
      # Act
      result = MyModule.function_name(input, :option)
      
      # Assert
      assert result == expected
    end
    
    test "returns error for invalid input" do
      result = MyModule.function_name(nil, :option)
      assert {:error, :invalid_input} = result
    end
  end
end
```

#### Telemetry Testing

```elixir
test "emits telemetry events" do
  # Setup telemetry capture
  telemetry_ref = make_ref()
  events = [[:tailwind_port, :feature, :complete]]
  :telemetry.attach_many(telemetry_ref, events, &capture_event/4, self())
  
  # Execute operation
  perform_operation()
  
  # Verify events
  assert_receive {[:tailwind_port, :feature, :complete], measurements, metadata}
  assert measurements.duration_ms > 0
  
  # Cleanup
  :telemetry.detach(telemetry_ref)
end
```

#### Integration Tests

```elixir
@tag :integration
test "full workflow integration" do
  {:ok, pid} = Defdo.TailwindPort.start_link(opts: test_opts())
  
  assert :ok = Defdo.TailwindPort.wait_until_ready(pid, 5000)
  
  health = Defdo.TailwindPort.health(pid)
  assert health.port_ready
  
  GenServer.stop(pid)
end
```

### Test Coverage

- Maintain test coverage above 80%
- Include both positive and negative test cases
- Test error conditions and edge cases
- Include integration tests for critical paths

## Documentation

### API Documentation

All public functions must include comprehensive documentation:

```elixir
@doc """
Brief description of what the function does.

Longer description with more details about behavior,
use cases, and important considerations.

## Parameters

  * `param1` - Description of parameter
  * `param2` - Description of parameter with type info

## Returns

  * `{:ok, result}` - Success case description
  * `{:error, reason}` - Error case description

## Examples

    iex> MyModule.my_function("input", :option)
    {:ok, "result"}

    iex> MyModule.my_function(nil, :option)
    {:error, :invalid_input}

## See Also

  * `related_function/2` - Related functionality
"""
@spec my_function(String.t(), atom()) :: {:ok, String.t()} | {:error, atom()}
def my_function(input, option) do
  # Implementation
end
```

### Guide Documentation

When adding new features, update relevant guides:

- **Usage Guide**: How to use the new feature
- **API Reference**: Complete API documentation
- **Examples**: Practical usage examples
- **Performance Guide**: Performance implications
- **Migration Guide**: Breaking changes (if any)

### Documentation Testing

```bash
# Generate and verify documentation
mix docs

# Check for documentation warnings
mix docs 2>&1 | grep -i warning
```

## Submitting Changes

### Pull Request Process

1. **Create a descriptive PR title**:
   ```
   feat(telemetry): add comprehensive span tracking
   ```

2. **Fill out the PR template** completely

3. **Ensure all checks pass**:
   - All tests pass
   - Code coverage maintained
   - Documentation updated
   - No linting issues

4. **Request review** from maintainers

5. **Address feedback** promptly and thoroughly

### PR Requirements

- [ ] Tests pass (`mix test`)
- [ ] Code formatting (`mix format`)
- [ ] Code quality (`mix credo --strict`)
- [ ] Type checking (`mix dialyzer`)
- [ ] Documentation updated
- [ ] Telemetry integration (if applicable)
- [ ] Breaking changes documented

### Review Process

1. **Automated checks** must pass
2. **Maintainer review** for:
   - Code quality and architecture
   - Test coverage and quality
   - Documentation completeness
   - Performance implications
   - Breaking change impact

3. **Address feedback** and make necessary changes

4. **Final approval** and merge by maintainers

## Release Process

### Version Numbering

TailwindPort follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backward-compatible functionality additions
- **PATCH** version for backward-compatible bug fixes

### Release Workflow

1. **Prepare release**:
   - Update version in `mix.exs`
   - Update `CHANGELOG.md`
   - Update documentation

2. **Create release PR**:
   - Title: `chore: prepare release v1.2.3`
   - Include changelog entries
   - Get maintainer approval

3. **Tag and release**:
   - Maintainers create git tag: `git tag v1.2.3`
   - Push tag: `git push origin v1.2.3`
   - GitHub Actions handles publication

### Changelog Guidelines

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [1.2.3] - 2024-01-15

### Added
- New feature descriptions

### Changed
- Changes to existing functionality

### Deprecated
- Features that will be removed

### Removed
- Features that were removed

### Fixed
- Bug fixes

### Security
- Security improvements
```

## Getting Help

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and community discussion
- **Pull Request Comments**: Code-specific questions and feedback

### Maintainer Contact

- Create an issue for bugs or feature requests
- Use discussions for general questions
- Tag maintainers in PRs for review

### Development Questions

When asking for help:

1. **Search existing issues** first
2. **Provide context**: What are you trying to achieve?
3. **Include code examples**: Minimal reproducible examples
4. **Specify versions**: Elixir, OTP, TailwindPort versions
5. **Share error messages**: Full error output when applicable

## Recognition

Contributors are recognized in:

- **CHANGELOG.md**: Major contributions noted in release notes
- **GitHub Contributors**: Automatic recognition on the repository
- **Documentation**: Significant contributors mentioned in guides

Thank you for contributing to TailwindPort! 🎉