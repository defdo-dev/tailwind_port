defmodule Defdo.TailwindPortTest do
  use ExUnit.Case

  alias Defdo.TailwindPort

  @tag :capture_log
  test "initialize / terminate port" do
    name = :tw_port

    assert {:ok, _pid} = TailwindPort.start_link([opts: ["-w"], name: name])

    assert %{port: port} = TailwindPort.state(name)

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

    assert {:ok, _pid} =
             TailwindPort.start_link([opts: opts])

    assert %{port: port} = TailwindPort.state()

    # We must improve time relaying on some startup monitor for waiting to the execution of the tailwind-cli.
    Process.sleep(3000)

    assert File.exists?(output)

    assert is_nil(Port.info(port))
    assert :ok = File.rm(output)
  end
end
