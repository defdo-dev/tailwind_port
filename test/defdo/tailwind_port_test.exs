defmodule Defdo.TailwindPortTest do
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

    assert {:ok, _pid} =
             TailwindPort.start_link(opts: opts)

    # We must improve time relaying on some startup monitor for waiting to the execution of the tailwind-cli.
    Process.sleep(3000)

    assert %{port: port, latest_output: output} = TailwindPort.state()

    refute is_nil(output)

    assert is_nil(Port.info(port))
  end
end
