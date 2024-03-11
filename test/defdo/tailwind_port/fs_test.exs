defmodule Defdo.TailwindPort.FSTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Defdo.TailwindPort.FS
  alias Defdo.TailwindPort.WorkingFiles

  @valid_opts [
    path: "/tmp",
    working_files: [
      input_css_path: "/tmp/app.css",
      tailwind_config_path: "/tmp/tailwind.config.js",
      content_path: "/tmp/index.html"
    ]
  ]

  @updated_opts [
    path: "/tmp/defdo",
    working_files: [
      input_css_path: "/tmp/defdo/app.css",
      tailwind_config_path: "/tmp/defdo/tailwind.config.js"
    ]
  ]

  @tag :fs
  test "create a new FS struct" do
    assert %FS{
             path: "/tmp",
             path_exists: true,
             working_files: %Defdo.TailwindPort.WorkingFiles{
               input_css_path: "/tmp/app.css",
               tailwind_config_path: "/tmp/tailwind.config.js",
               content_path: "/tmp/index.html"
             }
           } == FS.new(@valid_opts)
  end

  @tag :fs
  test "updates an existing FS struct" do
    assert updated_wf =
             %WorkingFiles{} =
             [
               input_css_path: "/tmp/defdo/app.css",
               tailwind_config_path: "/tmp/defdo/tailwind.config.js",
               content_path: "/tmp/index.html"
             ]
             |> WorkingFiles.new()

    assert fs = %FS{} = FS.new(@valid_opts)
    assert updated_fs = FS.update(fs, @updated_opts)
    refute updated_fs.path_exists
    assert updated_wf == updated_fs.working_files
    refute fs == updated_fs

    assert %{fs | path: "/tmp/defdo_tw_port", path_exists: false} ==
             FS.update(fs, path: "/tmp/defdo_tw_port")
  end

  @tag :fs
  test "initialize a path from FS struct" do
    dirname = FS.random_dir_name()
    assert fs = %FS{} = FS.new(path: "/tmp/#{dirname}")
    refute fs.path_exists

    assert updated_fs = FS.init_path(fs)
    assert updated_fs.path_exists

    assert %{fs | path_exists: true} == updated_fs

    clean_build_dir(updated_fs.path)

    refute fs.path_exists
  end

  defp clean_build_dir(path) do
    if File.dir?(path) do
      File.rm_rf(path)
    else
      {:error, "path is not a dir: #{inspect(path)}"}
    end
  end
end
