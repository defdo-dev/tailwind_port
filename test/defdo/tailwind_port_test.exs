defmodule Defdo.TailwindPortTest do
  use ExUnit.Case

  alias Defdo.TailwindPort

  @tag :capture_log
  test "initialize / terminate port" do
    assert {:ok, %{exit_status: nil, latest_output: nil, port: port}} = TailwindPort.init([])
    refute is_nil(Port.info(port))

    assert :shutdown = TailwindPort.terminate("We complete our job", %{port: port})
    assert is_nil(Port.info(port))
  end

  @tag :capture_log
  test "check if output is created" do
    content = "./priv/static/html/*.html"
    input = "./assets/css/app.css"
    output = "/tmp/app.css"
    config = "./assets/tailwind.config.js"

    opts = ["-i", input, "-o", output, "-c", config, "--content", content, "-m"]

    assert {:ok, %{exit_status: nil, latest_output: nil, port: port, fs: _}} =
             TailwindPort.init(opts: opts)

    # We must improve time relaying on some startup monitor for waiting to the execution of the tailwind-cli.
    Process.sleep(4000)

    assert File.exists?(output)
    assert Port.info(port)

    assert :shutdown == TailwindPort.terminate("finish test", %{port: port})

    assert is_nil(Port.info(port))
    assert :ok = File.rm(output)
  end
end
