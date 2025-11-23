defmodule Defdo.TailwindPort.CliCompatibility do
  @moduledoc """
  Manages CLI compatibility between different Tailwind CSS versions.

  This module handles the differences in command-line interface between
  Tailwind CSS v3 and v4, providing version detection and argument filtering.

  ## Version Differences

  ### Tailwind CSS v3 (3.x.x)
  - `--content <paths>`: Specify content paths for scanning
  - `-c, --config <file>`: Path to configuration file
  - `--postcss`: Load custom PostCSS configuration
  - `--poll`: Use polling instead of filesystem events when watching
  - `--no-autoprefixer`: Disable autoprefixer

  ### Tailwind CSS v4 (4.x.x)
  - Content scanning is automatic (no --content option)
  - Configuration is CSS-first via @theme directive (no --config option)
  - PostCSS is integrated (no --postcss option)
  - Polling is not available (no --poll option)
  - NEW: `--optimize`: Optimize output without minifying
  - NEW: `--cwd`: Specify current working directory
  - NEW: `--map`: Generate source map

  ## Migration Notes

  When migrating from v3 to v4:
  1. Remove `--content`, `--config`, `--postcss`, and `--poll` options
  2. Add configuration to CSS file using `@theme` directive
  3. Content paths are automatically detected
  4. Use `@config "./tailwind.config.js"` in CSS if legacy config is needed

  ## Examples

      iex> CliCompatibility.filter_args_for_version([
      ...>   input: "input.css",
      ...>   output: "output.css",
      ...>   content: "*.html",
      ...>   config: "tailwind.config.js",
      ...>   postcss: true
      ...> ], :v4)
      [input: "input.css", output: "output.css"]

      iex> CliCompatibility.filter_args_for_version([
      ...>   input: "input.css",
      ...>   output: "output.css",
      ...>   content: "*.html",
      ...>   config: "tailwind.config.js"
      ...> ], :v3)
      [input: "input.css", output: "output.css", content: "*.html", config: "tailwind.config.js"]
  """

  alias Defdo.TailwindPort.ConfigManager

  @typedoc """
  Supported Tailwind CSS versions.
  """
  @type version :: :v3 | :v4

  @typedoc """
  CLI option key for Tailwind compilation.
  """
  @type cli_option :: atom()

  @typedoc """
  CLI option value for Tailwind compilation.
  """
  @type cli_value :: term()

  @typedoc """
  List of CLI options for Tailwind compilation.
  """
  @type cli_options :: Keyword.t(cli_option(), cli_value())

  # CLI options available in Tailwind v3 but REMOVED in v4
  @v3_only_options [
    :content,
    :config,
    :postcss,
    :poll,
    :no_autoprefixer
  ]

  # CLI options available only in Tailwind v4 (new features)
  @v4_only_options [
    :optimize,
    :cwd,
    :map
  ]

  # CLI options available in both versions (compatible)
  @compatible_options [
    :input,
    :output,
    :minify,
    :watch
  ]

  @doc """
  Detects the current Tailwind CSS version from configuration.

  Returns `:v4` for version 4.x.x or beta versions,
  returns `:v3` for version 3.x.x or when version detection fails.

  ## Examples

      iex> CliCompatibility.detect_version()
      :v4

      iex> CliCompatibility.detect_version()
      :v3
  """
  @spec detect_version() :: version()
  def detect_version do
    version = ConfigManager.get_version()

    cond do
      String.starts_with?(version, "4.") -> :v4
      String.contains?(version, "beta") -> :v4
      String.contains?(version, "alpha") -> :v4
      String.starts_with?(version, "3.") -> :v3
      # Default to v3 for unknown versions
      true -> :v3
    end
  rescue
    # Default to v3 if version detection fails
    _ -> :v3
  end

  @doc """
  Filters CLI arguments based on Tailwind CSS version compatibility.

  Removes v3-only options when targeting v4 and vice versa.

  ## Parameters

  - `args` - List of CLI options and values
  - `version` - Target Tailwind version (`:v3` or `:v4`)

  ## Returns

  Filtered list of CLI options compatible with the specified version.

  ## Examples

      iex> CliCompatibility.filter_args_for_version(
      ...>   [input: "a.css", content: "*.html", config: "config.js"],
      ...>   :v4
      ...> )
      [input: "a.css"]

      iex> CliCompatibility.filter_args_for_version(
      ...>   [input: "a.css", content: "*.html", optimize: true],
      ...>   :v3
      ...> )
      [input: "a.css", content: "*.html"]
  """
  @spec filter_args_for_version(cli_options(), version()) :: cli_options()
  def filter_args_for_version(args, version) when is_list(args) do
    case version do
      :v4 ->
        # Remove v3-only options for v4
        Keyword.reject(args, fn {key, _value} ->
          key in @v3_only_options
        end)

      :v3 ->
        # Remove v4-only options for v3
        Keyword.reject(args, fn {key, _value} ->
          key in @v4_only_options
        end)
    end
  end

  @doc """
  Filters CLI arguments using the detected Tailwind CSS version.

  Convenience function that combines version detection and filtering.

  ## Parameters

  - `args` - List of CLI options and values

  ## Returns

  Filtered list of CLI options compatible with the detected version.

  ## Examples

      iex> CliCompatibility.filter_args_for_current_version([
      ...>   input: "a.css", content: "*.html", config: "config.js"
      ...> ])
      [input: "a.css"]  # When v4 is detected
  """
  @spec filter_args_for_current_version(cli_options()) :: cli_options()
  def filter_args_for_current_version(args) when is_list(args) do
    version = detect_version()
    filter_args_for_version(args, version)
  end

  @doc """
  Validates whether a specific CLI option is supported by a version.

  ## Parameters

  - `option` - CLI option key (atom)
  - `version` - Target Tailwind version (`:v3` or `:v4`)

  ## Returns

  `true` if the option is supported by the version, `false` otherwise.

  ## Examples

      iex> CliCompatibility.option_supported?(:content, :v3)
      true

      iex> CliCompatibility.option_supported?(:content, :v4)
      false

      iex> CliCompatibility.option_supported?(:optimize, :v4)
      true
  """
  @spec option_supported?(cli_option(), version()) :: boolean()
  def option_supported?(option, version) do
    cond do
      option in @compatible_options -> true
      option in @v3_only_options and version == :v3 -> true
      option in @v4_only_options and version == :v4 -> true
      true -> false
    end
  end

  @doc """
  Returns all CLI options supported by a specific version.

  ## Parameters

  - `version` - Target Tailwind version (`:v3` or `:v4`)

  ## Returns

  List of supported option keys for the specified version.

  ## Examples

      iex> CliCompatibility.supported_options(:v3)
      [:input, :output, :minify, :watch, :content, :config, :postcss, :poll, :no_autoprefixer]

      iex> CliCompatibility.supported_options(:v4)
      [:input, :output, :minify, :watch, :optimize, :cwd, :map]
  """
  @spec supported_options(version()) :: [cli_option()]
  def supported_options(version) do
    base = @compatible_options

    case version do
      :v3 -> base ++ @v3_only_options
      :v4 -> base ++ @v4_only_options
    end
  end

  @doc """
  Returns options that were removed when migrating from v3 to v4.

  Useful for debugging configuration migration issues.

  ## Parameters

  - `args` - Original list of CLI options (typically v3 format)

  ## Returns

  List of options that would be removed in v4 format.

  ## Examples

      iex> CliCompatibility.removed_in_v4([input: "a.css", content: "*.html", config: "c.js"])
      [content: "*.html", config: "c.js"]
  """
  @spec removed_in_v4(cli_options()) :: cli_options()
  def removed_in_v4(args) when is_list(args) do
    Keyword.filter(args, fn {key, _value} ->
      key in @v3_only_options
    end)
  end

  @doc """
  Returns options that are new in v4 compared to v3.

  ## Returns

  List of new options introduced in v4.

  ## Examples

      iex> CliCompatibility.new_in_v4()
      [optimize: nil, cwd: nil, map: nil]
  """
  @spec new_in_v4() :: cli_options()
  def new_in_v4 do
    Enum.map(@v4_only_options, &{&1, nil})
  end
end
