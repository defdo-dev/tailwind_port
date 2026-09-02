defmodule Defdo.TailwindPort.BinaryVersionTest do
  @moduledoc """
  A binary that merely exists is not the binary that was configured.

  These tests cover the gap that let a host run Tailwind v4.1.16 for months
  with `config :tailwind_port, version: "4.3.2"`: the installer only asked
  whether a file was present.
  """
  use ExUnit.Case, async: false

  alias Defdo.TailwindDownload
  alias Defdo.TailwindPort.BinaryManager

  # Any download attempt must announce itself, so point installs at a port
  # nothing listens on. Reuse returns :ok; a re-download returns an error.
  @unreachable_url "http://127.0.0.1:1/v$version/tailwindcss-$target"

  setup do
    dir =
      Path.join(System.tmp_dir!(), "tailwind_port_version_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    version = Application.get_env(:tailwind_port, :version)
    verify = Application.get_env(:tailwind_port, :verify_binary_version)

    on_exit(fn ->
      File.rm_rf!(dir)
      restore(:version, version)
      restore(:verify_binary_version, verify)
    end)

    {:ok, dir: dir}
  end

  defp restore(key, nil), do: Application.delete_env(:tailwind_port, key)
  defp restore(key, value), do: Application.put_env(:tailwind_port, key, value)

  # Stands in for the real CLI: prints the same banner and exits.
  defp fake_cli(dir, reported_version) do
    path = Path.join(dir, "tailwindcss")
    File.write!(path, "#!/bin/sh\necho \"≈ tailwindcss v#{reported_version}\"\n")
    File.chmod!(path, 0o755)
    path
  end

  # Stands in for a build with a plugin bundled: the version banner on --help,
  # and on a compile it announces the plugin the way daisyUI does.
  defp fake_cli_with_plugin(dir, reported_version, plugin, plugin_version) do
    path = Path.join(dir, "tailwindcss")

    File.write!(path, """
    #!/bin/sh
    echo "≈ tailwindcss v#{reported_version}"
    case "$*" in
      *--input*) echo "/*! 🌼 #{plugin} #{plugin_version} */" ;;
    esac
    exit 0
    """)

    File.chmod!(path, 0o755)
    path
  end

  # Stands in for the stock upstream build: same version, no plugin.
  defp fake_cli_without_plugin(dir, reported_version) do
    path = Path.join(dir, "tailwindcss")

    File.write!(path, """
    #!/bin/sh
    echo "≈ tailwindcss v#{reported_version}"
    case "$*" in
      *--input*) echo "Error: Can't resolve 'daisyui'"; exit 1 ;;
    esac
    exit 0
    """)

    File.chmod!(path, 0o755)
    path
  end

  describe "installed_version/1" do
    test "reads the version the binary reports", %{dir: dir} do
      assert {:ok, "4.3.3"} = BinaryManager.installed_version(fake_cli(dir, "4.3.3"))
    end

    test "reads a v3 banner too", %{dir: dir} do
      assert {:ok, "3.4.1"} = BinaryManager.installed_version(fake_cli(dir, "3.4.1"))
    end

    test "reports a missing file as absent", %{dir: dir} do
      assert {:error, :enoent} = BinaryManager.installed_version(Path.join(dir, "nope"))
    end

    test "reports a directory as absent", %{dir: dir} do
      assert {:error, :enoent} = BinaryManager.installed_version(dir)
    end

    test "does not mistake arbitrary output for a version", %{dir: dir} do
      path = Path.join(dir, "tailwindcss")
      File.write!(path, "#!/bin/sh\necho hello\n")
      File.chmod!(path, 0o755)

      assert {:error, :unrecognized_output} = BinaryManager.installed_version(path)
    end

    test "surfaces an unexecutable file as an error, not as a version", %{dir: dir} do
      path = Path.join(dir, "tailwindcss")
      File.write!(path, "not a program")
      File.chmod!(path, 0o644)

      assert {:error, {:exec_failed, _}} = BinaryManager.installed_version(path)
    end
  end

  describe "install/2 version gate" do
    test "keeps a binary whose version matches", %{dir: dir} do
      path = fake_cli(dir, "4.3.3")
      Application.put_env(:tailwind_port, :version, "4.3.3")

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "replaces a binary whose version differs", %{dir: dir} do
      path = fake_cli(dir, "4.1.16")
      Application.put_env(:tailwind_port, :version, "4.3.3")

      assert {:error, _} = TailwindDownload.install(path, @unreachable_url)
    end

    test "keeps a mismatched binary when the check is disabled", %{dir: dir} do
      path = fake_cli(dir, "4.1.16")
      Application.put_env(:tailwind_port, :version, "4.3.3")
      Application.put_env(:tailwind_port, :verify_binary_version, false)

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "treats a pre-release channel as the release it was cut from", %{dir: dir} do
      # The 4.3.2-rc1 build channel ships a binary that reports plain 4.3.2.
      # Comparing full strings would re-download on every boot.
      path = fake_cli(dir, "4.3.2")
      Application.put_env(:tailwind_port, :version, "4.3.2-rc1")

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "keeps a binary it cannot interrogate rather than destroying it", %{dir: dir} do
      path = Path.join(dir, "tailwindcss")
      File.write!(path, "opaque")
      File.chmod!(path, 0o644)
      Application.put_env(:tailwind_port, :version, "4.3.3")

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end
  end

  describe "probe_plugin/2" do
    test "reports the bundled plugin version", %{dir: dir} do
      path = fake_cli_with_plugin(dir, "4.3.3", "daisyui", "5.7.4")

      assert {:ok, "5.7.4"} = BinaryManager.probe_plugin(path, "daisyui")
    end

    test "reports a build that cannot resolve the plugin", %{dir: dir} do
      path = fake_cli_without_plugin(dir, "4.3.3")

      assert {:error, :plugin_unavailable} = BinaryManager.probe_plugin(path, "daisyui")
    end

    test "accepts a plugin that resolves without announcing a version", %{dir: dir} do
      path = Path.join(dir, "tailwindcss")
      File.write!(path, "#!/bin/sh\necho \"≈ tailwindcss v4.3.3\"\nexit 0\n")
      File.chmod!(path, 0o755)

      assert {:ok, nil} = BinaryManager.probe_plugin(path, "daisyui")
    end
  end

  describe "install/2 build gate" do
    setup %{dir: dir} do
      Application.put_env(:tailwind_port, :version, "4.3.3")
      plugins = Application.get_env(:tailwind_port, :required_plugins)
      on_exit(fn -> restore(:required_plugins, plugins) end)
      {:ok, dir: dir}
    end

    test "keeps a binary that bundles the required plugin", %{dir: dir} do
      path = fake_cli_with_plugin(dir, "4.3.3", "daisyui", "5.7.4")
      Application.put_env(:tailwind_port, :required_plugins, ["daisyui"])

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "replaces the right version from the wrong build", %{dir: dir} do
      # This is the case no version check can catch: the stock upstream binary
      # reports exactly the version that was configured.
      path = fake_cli_without_plugin(dir, "4.3.3")
      Application.put_env(:tailwind_port, :required_plugins, ["daisyui"])

      assert {:error, _} = TailwindDownload.install(path, @unreachable_url)
    end

    test "replaces a build carrying the wrong plugin version", %{dir: dir} do
      path = fake_cli_with_plugin(dir, "4.3.3", "daisyui", "5.4.3")
      Application.put_env(:tailwind_port, :required_plugins, [{"daisyui", "5.7.4"}])

      assert {:error, _} = TailwindDownload.install(path, @unreachable_url)
    end

    test "ignores the plugin version when none is pinned", %{dir: dir} do
      path = fake_cli_with_plugin(dir, "4.3.3", "daisyui", "5.4.3")
      Application.put_env(:tailwind_port, :required_plugins, ["daisyui"])

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "skips the check when no plugins are required", %{dir: dir} do
      path = fake_cli_without_plugin(dir, "4.3.3")
      Application.put_env(:tailwind_port, :required_plugins, [])

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "keeps a binary whose plugin version it cannot read", %{dir: dir} do
      path = Path.join(dir, "tailwindcss")
      File.write!(path, "#!/bin/sh\necho \"≈ tailwindcss v4.3.3\"\nexit 0\n")
      File.chmod!(path, 0o755)
      Application.put_env(:tailwind_port, :required_plugins, [{"daisyui", "5.7.4"}])

      assert :ok = TailwindDownload.install(path, @unreachable_url)
    end

    test "the wrong version is caught before the build is probed", %{dir: dir} do
      path = fake_cli_with_plugin(dir, "4.1.16", "daisyui", "5.7.4")
      Application.put_env(:tailwind_port, :required_plugins, ["daisyui"])

      assert {:error, _} = TailwindDownload.install(path, @unreachable_url)
    end
  end
end
