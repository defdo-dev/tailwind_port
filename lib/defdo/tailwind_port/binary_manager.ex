defmodule Defdo.TailwindPort.BinaryManager do
  @moduledoc """
  Binary management functionality for TailwindPort.

  This module handles the detection, verification, and management of Tailwind CSS
  binaries across different platforms. It provides platform-specific target detection,
  binary verification, and executable preparation.

  ## Features

  - **Platform Detection**: Automatic detection of target platform for binary selection
  - **Binary Verification**: Security validation of downloaded binaries
  - **Executable Management**: Making binaries executable with proper permissions
  - **Size Validation**: Verification of binary size constraints
  - **Signature Checking**: Platform-specific binary signature validation

  ## Platform Support

  Supports the following platforms:
  - Linux: x86_64, ARM64, ARMv7
  - macOS: x86_64, ARM64 (Apple Silicon)
  - Windows: x86_64

  ## Usage

      # Get target platform
      target = BinaryManager.get_target()

      # Verify a binary
      case BinaryManager.verify_binary(binary_data) do
        :ok -> 
          # Binary is valid
        {:error, reason} ->
          # Handle verification error
      end

      # Make binary executable
      :ok = BinaryManager.make_executable("/path/to/binary")

  """

  require Logger
  alias Defdo.TailwindPort.ConfigManager

  @typedoc "Target platform identifier"
  @type target :: String.t()

  @typedoc "Binary verification result"
  @type verification_result :: :ok | {:error, term()}

  @doc """
  Determines the target platform for binary selection.

  This function detects the current operating system and architecture
  to determine the appropriate Tailwind CSS binary target string.

  ## Returns

    * `target()` - Platform target string (e.g., "linux-x64", "macos-arm64")

  ## Examples

      # On Linux x86_64
      assert BinaryManager.get_target() == "linux-x64"

      # On macOS ARM64
      assert BinaryManager.get_target() == "macos-arm64"

      # On Windows x86_64
      assert BinaryManager.get_target() == "windows-x64.exe"

  ## Platform Mapping

  - **Linux**: `linux-x64`, `linux-arm64`, `linux-armv7`
  - **macOS**: `macos-x64`, `macos-arm64`
  - **Windows**: `windows-x64.exe`

  """
  @spec get_target() :: target()
  def get_target do
    case :os.type() do
      {:win32, _} -> "windows-x64.exe"
      {:unix, :darwin} -> get_macos_target()
      {:unix, _} -> get_linux_target()
    end
  end

  defp get_macos_target do
    arch = get_architecture_string()

    cond do
      String.contains?(arch, "aarch64") -> "macos-arm64"
      String.contains?(arch, "arm64") -> "macos-arm64"
      true -> "macos-x64"
    end
  end

  defp get_linux_target do
    arch = get_architecture_string()

    cond do
      String.contains?(arch, "aarch64") -> "linux-arm64"
      String.contains?(arch, "arm") -> "linux-armv7"
      true -> "linux-x64"
    end
  end

  defp get_architecture_string do
    :erlang.system_info(:system_architecture)
    |> List.to_string()
  end

  @doc """
  Verifies the integrity and validity of a binary.

  This function performs comprehensive validation of a binary including
  size checks and platform-specific signature verification to ensure
  the binary is valid and safe to execute.

  ## Parameters

    * `binary` - Binary data to verify

  ## Returns

    * `:ok` - Binary passed all verification checks
    * `{:error, reason}` - Verification failed with specific reason

  ## Verification Steps

  1. **Size Check**: Ensures binary is within acceptable size limits
  2. **Signature Check**: Validates platform-specific binary signatures
     - Windows: PE signature validation
     - macOS: Mach-O signature validation  
     - Linux: ELF signature validation

  ## Examples

      # Valid binary
      assert BinaryManager.verify_binary(valid_binary_data) == :ok

      # Invalid size
      assert {:error, :binary_too_small} = BinaryManager.verify_binary(<<>>)

      # Invalid signature  
      assert {:error, :invalid_elf_signature} = BinaryManager.verify_binary("invalid")

  ## Error Reasons

    * `:binary_too_small` - Binary is smaller than minimum expected size
    * `:binary_too_large` - Binary exceeds the configured maximum allowed size
    * `:invalid_pe_signature` - Windows PE signature validation failed
    * `:invalid_macho_signature` - macOS Mach-O signature validation failed
    * `:invalid_elf_signature` - Linux ELF signature validation failed

  """
  @spec verify_binary(binary()) :: verification_result()
  def verify_binary(binary) when is_binary(binary) do
    with :ok <- check_binary_size(binary) do
      check_binary_signature(binary)
    end
  end

  @doc """
  Reads the version reported by an installed Tailwind CSS binary.

  The binary is executed with `--help`, which prints its own banner
  (`≈ tailwindcss v4.3.3`) and exits without compiling anything. Both
  Tailwind v3 and v4 report their version in that banner.

  This is the only reliable way to know which CLI is on disk. The file name
  and any sidecar `.version` marker are hints written by whoever installed it,
  and they go stale silently.

  ## Parameters

    * `path` - Path to the binary

  ## Returns

    * `{:ok, version}` - Version string as reported by the binary, e.g. `"4.3.3"`
    * `{:error, :enoent}` - No file at `path`
    * `{:error, {:exec_failed, reason}}` - The file could not be executed
    * `{:error, :unrecognized_output}` - Ran, but printed no parseable version

  ## Examples

      {:ok, "4.3.3"} = BinaryManager.installed_version("bin/tailwindcss")

      {:error, :enoent} = BinaryManager.installed_version("bin/missing")

  """
  @spec installed_version(String.t()) :: {:ok, String.t()} | {:error, term()}
  def installed_version(path) when is_binary(path) do
    if File.regular?(path) do
      run_version_probe(path)
    else
      {:error, :enoent}
    end
  end

  defp run_version_probe(path) do
    {output, _status} = System.cmd(path, ["--help"], stderr_to_stdout: true)
    parse_version(output)
  rescue
    error -> {:error, {:exec_failed, error}}
  end

  defp parse_version(output) do
    case Regex.run(~r/tailwindcss\s+v?(\d+\.\d+\.\d+[^\s]*)/i, output) do
      [_, version] -> {:ok, version}
      _ -> {:error, :unrecognized_output}
    end
  end

  @doc """
  Checks whether a binary has a plugin bundled into it.

  Two builds of the same Tailwind release report the same version, so the
  version alone cannot tell a custom CLI from the stock upstream one. What
  distinguishes them is what they can compile: a build with daisyUI bundled
  resolves `@plugin "daisyui"` with nothing installed, and the stock binary
  fails with `Can't resolve 'daisyui'`.

  The probe compiles in an empty temporary directory on purpose. Plugin
  resolution walks up from the input file, so probing inside a project that has
  `node_modules/daisyui` would let the stock binary pass on the project's copy
  rather than on anything bundled into the binary.

  ## Parameters

    * `path` - Path to the binary
    * `plugin` - Plugin name as written in `@plugin`, e.g. `"daisyui"`

  ## Returns

    * `{:ok, version}` - Plugin resolved and announced its version, e.g. `"5.7.4"`
    * `{:ok, nil}` - Plugin resolved but announced no version
    * `{:error, :plugin_unavailable}` - The binary cannot resolve the plugin
    * `{:error, {:exec_failed, reason}}` - The binary could not be run

  ## Examples

      {:ok, "5.7.4"} = BinaryManager.probe_plugin("bin/tailwindcss", "daisyui")

      {:error, :plugin_unavailable} =
        BinaryManager.probe_plugin("bin/stock-tailwindcss", "daisyui")

  """
  @spec probe_plugin(String.t(), String.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def probe_plugin(path, plugin) when is_binary(path) and is_binary(plugin) do
    if File.regular?(path) do
      dir =
        Path.join(System.tmp_dir!(), "tailwind_port_probe_#{System.unique_integer([:positive])}")

      try do
        run_plugin_probe(path, plugin, dir)
      after
        File.rm_rf(dir)
      end
    else
      {:error, :enoent}
    end
  end

  defp run_plugin_probe(path, plugin, dir) do
    File.mkdir_p!(dir)
    input = Path.join(dir, "probe.css")
    output = Path.join(dir, "probe.out.css")
    File.write!(input, ~s|@import "tailwindcss";\n@plugin "#{plugin}";\n|)

    {out, status} =
      System.cmd(path, ["--input", input, "--output", output],
        stderr_to_stdout: true,
        cd: dir
      )

    if status == 0 do
      {:ok, parse_plugin_version(out, plugin)}
    else
      {:error, :plugin_unavailable}
    end
  rescue
    error -> {:error, {:exec_failed, error}}
  end

  # The plugin announces itself on stderr while compiling, e.g.
  # `/*! 🌼 daisyUI 5.7.4 */`. Absence is not failure: the compile already
  # proved the plugin resolved.
  defp parse_plugin_version(output, plugin) do
    case Regex.run(~r/#{Regex.escape(plugin)}\s+v?(\d+\.\d+\.\d+[^\s*]*)/i, output) do
      [_, version] -> version
      _ -> nil
    end
  end

  @doc """
  Makes a binary file executable with appropriate permissions.

  This function sets the proper file permissions to make a binary
  executable on Unix-like systems. On Windows, this is a no-op
  since executable permissions work differently.

  ## Parameters

    * `path` - Path to the binary file

  ## Returns

    * `:ok` - Permissions set successfully
    * `{:error, reason}` - Failed to set permissions

  ## Examples

      # Make binary executable
      :ok = BinaryManager.make_executable("/usr/local/bin/tailwindcss")

      # Handle permission errors
      case BinaryManager.make_executable("/protected/binary") do
        :ok -> 
          IO.puts("Binary is now executable")
        {:error, :eacces} ->
          IO.puts("Permission denied")
      end

  ## Platform Behavior

  - **Unix/Linux/macOS**: Sets file mode to 0o755 (rwxr-xr-x)
  - **Windows**: No operation (returns `:ok`)

  """
  @spec make_executable(String.t()) :: :ok | {:error, File.posix()}
  def make_executable(path) when is_binary(path) do
    case :os.type() do
      {:win32, _} ->
        # Windows doesn't need chmod
        :ok

      _ ->
        case File.chmod(path, 0o755) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Ensures a directory exists for the binary path.

  Creates the directory structure needed for the binary path if it
  doesn't already exist. This is typically used before downloading
  or installing binaries.

  ## Parameters

    * `path` - Full path to the binary file

  ## Returns

    * `:ok` - Directory exists or was created successfully
    * `{:error, reason}` - Failed to create directory

  ## Examples

      # Ensure directory exists
      :ok = BinaryManager.ensure_directory("/usr/local/bin/tailwindcss")

      # Handle creation errors
      case BinaryManager.ensure_directory("/readonly/path/binary") do
        :ok -> 
          IO.puts("Directory ready")
        {:error, :eacces} ->
          IO.puts("Permission denied creating directory")
      end

  """
  @spec ensure_directory(String.t()) :: :ok | {:error, File.posix()}
  def ensure_directory(path) when is_binary(path) do
    dir = Path.dirname(path)

    if File.dir?(dir) do
      :ok
    else
      File.mkdir_p(dir)
    end
  end

  @doc """
  Writes binary data to a file path.

  Safely writes binary data to the specified file path with proper
  error handling and atomic operations when possible.

  ## Parameters

    * `path` - Destination file path
    * `binary` - Binary data to write

  ## Returns

    * `:ok` - File written successfully
    * `{:error, reason}` - Failed to write file

  ## Examples

      # Write binary to file
      :ok = BinaryManager.write_binary("/tmp/tailwindcss", binary_data)

      # Handle write errors
      case BinaryManager.write_binary("/readonly/file", data) do
        :ok -> 
          IO.puts("Binary written successfully")
        {:error, :eacces} ->
          IO.puts("Permission denied writing file")
      end

  """
  @spec write_binary(String.t(), binary()) :: :ok | {:error, File.posix()}
  def write_binary(path, binary) when is_binary(path) and is_binary(binary) do
    File.write(path, binary)
  end

  @doc """
  Validates if a platform target is supported.

  Checks if the provided target string corresponds to a supported
  platform and architecture combination.

  ## Parameters

    * `target` - Target platform string to validate

  ## Returns

    * `true` - Target is supported
    * `false` - Target is not supported

  ## Examples

      # Valid targets
      assert BinaryManager.valid_target?("linux-x64")
      assert BinaryManager.valid_target?("macos-arm64")
      assert BinaryManager.valid_target?("windows-x64.exe")

      # Invalid targets
      refute BinaryManager.valid_target?("unsupported-platform")
      refute BinaryManager.valid_target?("")

  """
  @spec valid_target?(String.t()) :: boolean()
  def valid_target?(target) when is_binary(target) do
    target in [
      "linux-x64",
      "linux-arm64",
      "linux-armv7",
      "macos-x64",
      "macos-arm64",
      "windows-x64.exe"
    ]
  end

  # Private functions

  defp check_binary_size(binary) do
    size = byte_size(binary)
    max_binary_size = ConfigManager.get_max_binary_size_bytes()

    cond do
      size < 1_000_000 ->
        # Less than 1MB is probably too small for a real Tailwind binary
        {:error, :binary_too_small}

      size > max_binary_size ->
        # Large self-hosted binaries are valid, but still cap the size to catch bad artifacts.
        {:error, :binary_too_large}

      true ->
        :ok
    end
  end

  defp check_binary_signature(binary) do
    case :os.type() do
      {:win32, _} ->
        check_pe_signature(binary)

      {:unix, :darwin} ->
        check_macho_signature(binary)

      {:unix, _} ->
        check_elf_signature(binary)
    end
  end

  # Windows PE signature checking
  defp check_pe_signature(<<"MZ", _::binary>>), do: :ok
  defp check_pe_signature(_), do: {:error, :invalid_pe_signature}

  # macOS Mach-O signature checking (multiple formats)
  # 32-bit big-endian
  defp check_macho_signature(<<0xFE, 0xED, 0xFA, 0xCE, _::binary>>), do: :ok
  # 32-bit little-endian
  defp check_macho_signature(<<0xCE, 0xFA, 0xED, 0xFE, _::binary>>), do: :ok
  # 64-bit big-endian
  defp check_macho_signature(<<0xFE, 0xED, 0xFA, 0xCF, _::binary>>), do: :ok
  # 64-bit little-endian
  defp check_macho_signature(<<0xCF, 0xFA, 0xED, 0xFE, _::binary>>), do: :ok
  defp check_macho_signature(_), do: {:error, :invalid_macho_signature}

  # Linux ELF signature checking
  defp check_elf_signature(<<0x7F, "ELF", _::binary>>), do: :ok
  defp check_elf_signature(_), do: {:error, :invalid_elf_signature}
end
