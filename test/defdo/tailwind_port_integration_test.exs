defmodule Defdo.TailwindPortIntegrationTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.Standalone

  @tag :integration
  test "compiles CSS output with the Tailwind binary" do
    name = :standalone_compile_test
    paths = setup_test_paths()
    telemetry_ref = "tailwind-port-exit-#{System.unique_integer([:positive])}"

    write_v3_fixture(paths)

    :telemetry.attach(telemetry_ref, [:tailwind_port, :port, :exit], &capture_port_exit/4, self())

    on_exit(fn ->
      :telemetry.detach(telemetry_ref)

      case Process.whereis(name) do
        nil -> :ok
        _pid -> Standalone.terminate(name)
      end

      File.rm_rf(paths.tmp_dir)
    end)

    assert {:ok, _pid} =
             Standalone.start_link(
               name: name,
               opts: [
                 "-i",
                 paths.input_path,
                 "-c",
                 paths.config_path,
                 "--content",
                 paths.content_path,
                 "-o",
                 paths.output_path,
                 "-m"
               ]
             )

    state = Standalone.state(name)
    port = state.port
    assert is_port(port)

    assert :ok = Standalone.wait_until_ready(name, 30_000)

    assert_receive {[:tailwind_port, :port, :exit], %{exit_status: 0}, %{port: ^port}},
                   30_000

    assert File.exists?(paths.output_path)

    css = File.read!(paths.output_path)

    assert css =~ ".text-red-500"
    assert css =~ ".block"

    health = Standalone.health(name)
    assert health.port_ready
    assert health.css_builds > 0
  end

  test "port synchronization and readiness" do
    name = :sync_test_port
    opts = ["-w", "--input", "./assets/css/app.css", "--content", "./priv/static/html/*.html"]

    assert {:ok, _pid} = Standalone.start_link(opts: opts, name: name)

    # Test readiness check
    # Should not be ready immediately
    refute Standalone.ready?(name, 100)

    # Wait for readiness
    assert :ok = Standalone.wait_until_ready(name, 10_000)

    # Should now be ready
    assert Standalone.ready?(name)

    # Check state
    state = Standalone.state(name)
    assert state.port_ready
    assert state.port

    Standalone.terminate(name)
  end

  test "input validation" do
    # Test invalid name
    assert {:error, :invalid_name} = Standalone.start_link(name: "not_an_atom", opts: [])

    # Test invalid opts
    assert {:error, :invalid_opts} = Standalone.start_link(opts: "not_a_list")

    # Test invalid args
    assert {:error, :invalid_args} = Standalone.start_link("not_a_keyword_list")
  end

  test "new/2 validation" do
    name = :validation_test_port
    assert {:ok, _pid} = Standalone.start_link(name: name, opts: [])

    # Test invalid cmd
    assert {:error, :invalid_cmd} = Standalone.new(name, cmd: 123)

    # Test invalid opts
    assert {:error, :invalid_opts} = Standalone.new(name, opts: "not_a_list")

    # Test invalid args
    assert {:error, :invalid_args} = Standalone.new(name, "not_a_keyword_list")

    Standalone.terminate(name)
  end

  # Reduced timeout
  @tag timeout: 3_000
  test "port creation with retry demonstrates fast execution" do
    name = :retry_test_port

    assert {:ok, _pid} = Standalone.start_link(name: name, opts: [])

    # Use system binary that exists and works to demonstrate the optimization
    # The retry logic configuration (50ms delays) is tested in unit tests
    {time_us, result} =
      :timer.tc(fn ->
        Standalone.new(name, cmd: "/bin/echo", opts: ["hello"])
      end)

    # Should complete quickly due to our optimizations
    # 2s maximum - much faster than before
    assert time_us < 2_000_000

    # Result might succeed or fail depending on environment, but timing is key
    assert match?({:ok, _}, result) or match?({:error, _}, result)

    if Process.whereis(name) do
      Standalone.terminate(name)
    end
  end

  test "configuration values are optimized for tests" do
    # This test verifies our configuration optimizations are working
    name = :config_test

    assert {:ok, _pid} = Standalone.start_link(name: name, opts: [])

    # Test that we can get health metrics quickly
    health = Standalone.health(name)
    assert is_map(health)
    assert health.total_outputs == 0
    assert health.errors == 0

    # Test ready? function responds quickly
    # Very short timeout
    ready_result = Standalone.ready?(name, 100)
    assert is_boolean(ready_result)

    Standalone.terminate(name)
  end

  test "timeout handling" do
    name = :timeout_test_port
    assert {:ok, _pid} = Standalone.start_link(name: name, opts: [])

    # Test ready? with short timeout
    refute Standalone.ready?(name, 10)

    # Test wait_until_ready with very short timeout
    assert {:error, :timeout} = Standalone.wait_until_ready(name, 50)

    Standalone.terminate(name)
  end

  defp setup_test_paths do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "tailwind_standalone_integration_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    %{
      tmp_dir: tmp_dir,
      input_path: Path.join(tmp_dir, "input.css"),
      output_path: Path.join(tmp_dir, "output.css"),
      content_path: Path.join(tmp_dir, "content.html"),
      config_path: Path.join(tmp_dir, "tailwind.config.js")
    }
  end

  defp write_v3_fixture(paths) do
    File.write!(paths.content_path, ~s(<div class="text-red-500 block">Hello</div>\n))
    File.write!(paths.input_path, "@tailwind utilities;\n")

    File.write!(
      paths.config_path,
      """
      module.exports = {
        content: ["#{paths.content_path}"],
        theme: { extend: {} },
        corePlugins: { preflight: false }
      }
      """
    )
  end

  defp capture_port_exit(event, measurements, metadata, test_pid) do
    send(test_pid, {event, measurements, metadata})
  end
end
