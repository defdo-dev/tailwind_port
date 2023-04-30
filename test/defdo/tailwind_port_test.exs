defmodule Defdo.TailwindPortTest do
  use ExUnit.Case

  alias Defdo.TailwindPort

  test "initialize / terminate port" do
    assert {:ok, %{exit_status: nil, latest_output: nil, port: port}} = TailwindPort.init []
    refute is_nil(Port.info(port))

    assert :shutdown = TailwindPort.terminate("We complete our job", %{port: port})
    assert is_nil(Port.info(port))
  end
end
