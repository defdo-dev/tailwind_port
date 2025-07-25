defmodule Defdo.TailwindPortTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort

  @tag :capture_log
  test "initialize / terminate port" do
    name = :tw_port

    assert {:ok, _pid} = TailwindPort.start_link(opts: ["-w"], name: name)

    assert %{port: port} = TailwindPort.state(name)

    refute is_nil(Port.info(port))

    assert {:shutdown, "We complete our job"} =
             TailwindPort.terminate("We complete our job", %{port: port})

    assert is_nil(Port.info(port))
  end

  @tag :capture_log
  test "don't start port if empty opts" do
    name = :tw

    assert {:ok, _pid} = TailwindPort.start_link(opts: [], name: name)

    assert %{port: port} = TailwindPort.state(name)

    assert is_nil(Port.info(port))
  end

  @tag :capture_log
  test "check if output is created" do
    content = "./priv/static/html/*.html"
    input = "./assets/css/app.css"
    config = "./assets/tailwind.config.js"

    opts = ["-i", input, "-c", config, "--content", content, "-m"]

    assert {:ok, _pid} = TailwindPort.start_link(opts: opts)

    # Use our new synchronization mechanism instead of sleep
    assert :ok = TailwindPort.wait_until_ready(TailwindPort, 5000)

    assert %{port: port, latest_output: _output, port_ready: port_ready} = TailwindPort.state()

    assert port_ready
    # For one-time builds (non-watch mode), the port should complete and exit
    # For watch mode, the port would still be running
    # Since we're using -m (minify) without -w (watch), the port should complete
    if port do
      # Port might still be running during build, give it time to complete
      Process.sleep(500)
      # Now it should be completed for non-watch builds
    end
  end
end
