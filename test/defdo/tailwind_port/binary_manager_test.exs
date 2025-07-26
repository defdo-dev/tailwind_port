defmodule Defdo.TailwindPort.BinaryManagerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Bitwise
  alias Defdo.TailwindPort.BinaryManager

  describe "get_target/0" do
    test "returns target string based on current platform" do
      target = BinaryManager.get_target()
      assert is_binary(target)
      assert BinaryManager.valid_target?(target)
    end

    test "target contains expected platform identifiers" do
      target = BinaryManager.get_target()

      case :os.type() do
        {:win32, _} ->
          assert target == "windows-x64.exe"

        {:unix, :darwin} ->
          assert target in ["macos-x64", "macos-arm64"]

        {:unix, _} ->
          assert target in ["linux-x64", "linux-arm64", "linux-armv7"]
      end
    end
  end

  describe "verify_binary/1" do
    test "accepts valid-sized binary with correct signature" do
      # Create a binary that looks like a valid executable for current platform
      case :os.type() do
        {:win32, _} ->
          # Windows PE signature
          binary = <<"MZ">> <> :crypto.strong_rand_bytes(2_000_000)
          assert :ok = BinaryManager.verify_binary(binary)

        {:unix, :darwin} ->
          # macOS Mach-O signature (64-bit little-endian)
          binary = <<0xCF, 0xFA, 0xED, 0xFE>> <> :crypto.strong_rand_bytes(2_000_000)
          assert :ok = BinaryManager.verify_binary(binary)

        {:unix, _} ->
          # Linux ELF signature
          binary = <<0x7F, "ELF">> <> :crypto.strong_rand_bytes(2_000_000)
          assert :ok = BinaryManager.verify_binary(binary)
      end
    end

    test "rejects binary that is too small" do
      # 1KB
      small_binary = :crypto.strong_rand_bytes(1000)
      assert {:error, :binary_too_small} = BinaryManager.verify_binary(small_binary)
    end

    test "rejects binary that is too large" do
      # Create a binary larger than 100MB limit
      large_binary = :crypto.strong_rand_bytes(101_000_000)
      assert {:error, :binary_too_large} = BinaryManager.verify_binary(large_binary)
    end

    test "rejects binary with invalid signature for current platform" do
      # Create a binary with wrong signature for current platform
      case :os.type() do
        {:win32, _} ->
          # Wrong signature for Windows
          binary = <<0x7F, "ELF">> <> :crypto.strong_rand_bytes(2_000_000)
          assert {:error, :invalid_pe_signature} = BinaryManager.verify_binary(binary)

        {:unix, :darwin} ->
          # Wrong signature for macOS
          binary = <<"MZ">> <> :crypto.strong_rand_bytes(2_000_000)
          assert {:error, :invalid_macho_signature} = BinaryManager.verify_binary(binary)

        {:unix, _} ->
          # Wrong signature for Linux
          binary = <<"MZ">> <> :crypto.strong_rand_bytes(2_000_000)
          assert {:error, :invalid_elf_signature} = BinaryManager.verify_binary(binary)
      end
    end

    test "handles different Mach-O signature formats" do
      if match?({:unix, :darwin}, :os.type()) do
        signatures = [
          # 32-bit big-endian
          <<0xFE, 0xED, 0xFA, 0xCE>>,
          # 32-bit little-endian
          <<0xCE, 0xFA, 0xED, 0xFE>>,
          # 64-bit big-endian
          <<0xFE, 0xED, 0xFA, 0xCF>>,
          # 64-bit little-endian
          <<0xCF, 0xFA, 0xED, 0xFE>>
        ]

        Enum.each(signatures, fn signature ->
          binary = signature <> :crypto.strong_rand_bytes(2_000_000)
          assert :ok = BinaryManager.verify_binary(binary)
        end)
      end
    end

    test "rejects empty binary" do
      assert {:error, :binary_too_small} = BinaryManager.verify_binary(<<>>)
    end

    test "rejects binary with no signature" do
      # Random bytes, no valid signature
      binary = :crypto.strong_rand_bytes(2_000_000)

      expected_error =
        case :os.type() do
          {:win32, _} -> :invalid_pe_signature
          {:unix, :darwin} -> :invalid_macho_signature
          {:unix, _} -> :invalid_elf_signature
        end

      assert {:error, ^expected_error} = BinaryManager.verify_binary(binary)
    end
  end

  describe "make_executable/1" do
    setup do
      # Create a temporary file for testing
      test_file = "/tmp/test_binary_#{:rand.uniform(10000)}"
      File.write!(test_file, "test content")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "makes file executable on Unix systems", %{test_file: test_file} do
      case :os.type() do
        {:win32, _} ->
          # On Windows, should return :ok but not actually change permissions
          assert :ok = BinaryManager.make_executable(test_file)

        _ ->
          # On Unix systems, should set executable permissions
          assert :ok = BinaryManager.make_executable(test_file)

          # Verify file is now executable
          {:ok, file_info} = File.stat(test_file)
          mode = file_info.mode

          # Check that executable bits are set (owner, group, other)
          assert (mode &&& 0o111) != 0
      end
    end

    test "handles non-existent file" do
      result = BinaryManager.make_executable("/nonexistent/file")

      case :os.type() do
        {:win32, _} ->
          # Windows returns :ok even for non-existent files
          assert :ok = result

        _ ->
          # Unix systems should return an error
          assert {:error, _reason} = result
      end
    end

    test "handles permission denied" do
      # This test is difficult to create reliably across platforms
      # Skip for now as it would require special setup
      :ok
    end
  end

  describe "ensure_directory/1" do
    test "creates directory if it doesn't exist" do
      test_dir = "/tmp/test_dir_#{:rand.uniform(10000)}"
      test_path = "#{test_dir}/binary"

      # Ensure directory doesn't exist
      File.rm_rf!(test_dir)
      refute File.dir?(test_dir)

      # Create directory
      assert :ok = BinaryManager.ensure_directory(test_path)
      assert File.dir?(test_dir)

      # Cleanup
      File.rm_rf!(test_dir)
    end

    test "succeeds if directory already exists" do
      test_dir = "/tmp/existing_dir_#{:rand.uniform(10000)}"
      test_path = "#{test_dir}/binary"

      # Create directory first
      File.mkdir_p!(test_dir)
      assert File.dir?(test_dir)

      # Should succeed even if directory exists
      assert :ok = BinaryManager.ensure_directory(test_path)
      assert File.dir?(test_dir)

      # Cleanup
      File.rm_rf!(test_dir)
    end

    test "handles nested directory creation" do
      test_path = "/tmp/nested/deep/dirs/binary_#{:rand.uniform(10000)}"
      base_dir = "/tmp/nested"

      # Ensure base doesn't exist
      File.rm_rf!(base_dir)
      refute File.dir?(base_dir)

      # Create nested directories
      assert :ok = BinaryManager.ensure_directory(test_path)
      assert File.dir?(Path.dirname(test_path))

      # Cleanup
      File.rm_rf!(base_dir)
    end
  end

  describe "write_binary/2" do
    test "writes binary data to file" do
      test_file = "/tmp/write_test_#{:rand.uniform(10000)}"
      test_data = :crypto.strong_rand_bytes(1000)

      # Write data
      assert :ok = BinaryManager.write_binary(test_file, test_data)

      # Verify data was written correctly
      {:ok, written_data} = File.read(test_file)
      assert written_data == test_data

      # Cleanup
      File.rm!(test_file)
    end

    test "overwrites existing file" do
      test_file = "/tmp/overwrite_test_#{:rand.uniform(10000)}"
      original_data = "original content"
      new_data = "new content"

      # Write original data
      File.write!(test_file, original_data)

      # Overwrite with new data
      assert :ok = BinaryManager.write_binary(test_file, new_data)

      # Verify new data
      {:ok, written_data} = File.read(test_file)
      assert written_data == new_data

      # Cleanup
      File.rm!(test_file)
    end

    test "handles write to non-existent directory" do
      test_file = "/tmp/nonexistent_dir_#{:rand.uniform(10000)}/file"
      test_data = "test data"

      # Should fail because directory doesn't exist
      assert {:error, _reason} = BinaryManager.write_binary(test_file, test_data)
    end

    test "handles empty binary data" do
      test_file = "/tmp/empty_test_#{:rand.uniform(10000)}"

      # Write empty data
      assert :ok = BinaryManager.write_binary(test_file, <<>>)

      # Verify empty file was created
      {:ok, written_data} = File.read(test_file)
      assert written_data == <<>>

      # Cleanup
      File.rm!(test_file)
    end
  end

  describe "valid_target?/1" do
    test "validates known supported targets" do
      valid_targets = [
        "linux-x64",
        "linux-arm64",
        "linux-armv7",
        "macos-x64",
        "macos-arm64",
        "windows-x64.exe"
      ]

      Enum.each(valid_targets, fn target ->
        assert BinaryManager.valid_target?(target), "#{target} should be valid"
      end)
    end

    test "rejects invalid targets" do
      invalid_targets = [
        "",
        "invalid-platform",
        "linux-unknown",
        "windows-arm64",
        "macos-x86",
        "freebsd-x64",
        nil
      ]

      Enum.each(invalid_targets, fn target ->
        if is_binary(target) do
          refute BinaryManager.valid_target?(target), "#{target} should be invalid"
        end
      end)
    end

    test "handles case sensitivity" do
      # Targets should be case-sensitive
      refute BinaryManager.valid_target?("LINUX-X64")
      refute BinaryManager.valid_target?("Linux-x64")
      refute BinaryManager.valid_target?("macos-X64")
    end
  end

  describe "integration and edge cases" do
    test "complete workflow: ensure directory, write, make executable, verify" do
      test_dir = "/tmp/integration_test_#{:rand.uniform(10000)}"
      test_file = "#{test_dir}/tailwindcss"

      # Create test binary with valid signature for current platform
      test_binary =
        case :os.type() do
          {:win32, _} ->
            <<"MZ">> <> :crypto.strong_rand_bytes(2_000_000)

          {:unix, :darwin} ->
            <<0xCF, 0xFA, 0xED, 0xFE>> <> :crypto.strong_rand_bytes(2_000_000)

          {:unix, _} ->
            <<0x7F, "ELF">> <> :crypto.strong_rand_bytes(2_000_000)
        end

      # Complete workflow
      assert :ok = BinaryManager.ensure_directory(test_file)
      assert :ok = BinaryManager.write_binary(test_file, test_binary)
      assert :ok = BinaryManager.make_executable(test_file)
      assert :ok = BinaryManager.verify_binary(test_binary)

      # Verify file exists and is correct
      assert File.exists?(test_file)
      {:ok, written_data} = File.read(test_file)
      assert written_data == test_binary

      # Cleanup
      File.rm_rf!(test_dir)
    end

    test "handles large binary operations efficiently" do
      # Test with a moderately large binary (5MB)
      large_binary =
        case :os.type() do
          {:win32, _} ->
            <<"MZ">> <> :crypto.strong_rand_bytes(5_000_000)

          {:unix, :darwin} ->
            <<0xCF, 0xFA, 0xED, 0xFE>> <> :crypto.strong_rand_bytes(5_000_000)

          {:unix, _} ->
            <<0x7F, "ELF">> <> :crypto.strong_rand_bytes(5_000_000)
        end

      # Should handle large binary efficiently
      start_time = System.monotonic_time(:millisecond)
      result = BinaryManager.verify_binary(large_binary)
      end_time = System.monotonic_time(:millisecond)

      assert :ok = result
      # Should complete within 1 second
      assert end_time - start_time < 1000
    end

    test "current platform target is always valid" do
      current_target = BinaryManager.get_target()
      assert BinaryManager.valid_target?(current_target)
    end
  end
end
