defmodule Defdo.TailwindPort.FSEdgeCasesTest do
  @moduledoc false
  use ExUnit.Case
  alias Defdo.TailwindPort.FS

  describe "edge cases" do
    test "cast_existing_path with nil returns false" do
      # This tests the uncovered line in FS module
      fs = FS.new(path: nil)
      refute fs.path_exists
    end

    test "random_fs creates unique paths" do
      fs1 = FS.random_fs()
      fs2 = FS.random_fs()
      
      assert fs1.path != fs2.path
      assert String.contains?(fs1.path, System.tmp_dir())
      assert String.contains?(fs2.path, System.tmp_dir())
    end

    test "random_dir_name with custom length" do
      name1 = FS.random_dir_name(5)
      name2 = FS.random_dir_name(15)
      
      assert String.length(name1) < String.length(name2)
      assert name1 != name2
    end

    test "update with empty working files" do
      fs = FS.new(path: "/tmp")
      updated = FS.update(fs, working_files: [])
      
      assert updated.working_files.input_css_path == nil
      assert updated.working_files.output_css_path == nil
    end
  end
end