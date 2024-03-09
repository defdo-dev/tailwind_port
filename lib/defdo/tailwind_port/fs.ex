defmodule Defdo.TailwindPort.FS do
  @moduledoc false
  alias Defdo.TailwindPort.WorkFiles

  @type t :: %__MODULE__{
          path: WorkFiles.path(),
          path_exists: boolean(),
          working_files: WorkFiles.t()
        }

  defstruct path: nil,
            path_exists: false,
            working_files: %WorkFiles{}

  @doc """
  Creates a new `FS` (FileSystem) struct, in order to keep related working paths.

    Example:

      iex> opts = [
        path: "/tmp",
        working_files: [
          input_css_path: "/tmp/app.css",
          tailwind_config_path: "/tmp/tailwind.config.js",
          content_path: "/tmp/index.html"
        ]
      ]
      iex> Defdo.TailwindPort.FS.new(opts)
      iex> %Defdo.TailwindPort.FS{
        path: "/tmp",
        path_exists: true,
        working_files: %Defdo.TailwindPort.WorkFiles{
          input_css_path: "/tmp/app.css",
          tailwind_config_path: "/tmp/tailwind.config.js",
          content_path: "/tmp/index.html"
        }
      }
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts) do
    working_files = get_working_files(opts)
    path_exists = check_if_path_exists?(opts)

    new_opts =
      opts
      |> Keyword.put(:working_files, working_files)
      |> Keyword.put(:path_exists, path_exists)

    struct(__MODULE__, new_opts)
  end

  def update(%__MODULE__{path: path, working_files: %WorkFiles{} = work_file} = struct, opts) do
    working_files = update_working_files(work_file, opts)

    path_exists = check_if_path_exists?(opts, path)

    updated_opts =
      opts
      |> Keyword.put(:working_files, working_files)
      |> Keyword.put(:path_exists, path_exists)

    struct(struct, updated_opts)
  end

  def init_path(%__MODULE__{path: path} = fs) do
    File.mkdir_p(path)
    update(fs, [])
  end

  @doc """
  Obtain a random temporal directory structure
  """
  def random_fs do
    path = [System.tmp_dir(), random_dir_name()] |> Enum.reject(&is_nil/1) |> Path.join()

    new(path: path)
  end

  @doc """
  Obtain a random name to use as dynamic directory.
  """
  def random_dir_name(len \\ 10) do
    :crypto.strong_rand_bytes(len) |> Base.encode64(padding: false)
  end

  defp get_working_files(opts, default \\ []) do
    working_files_opts = Keyword.get(opts, :working_files, default)

    WorkFiles.new(working_files_opts)
  end

  defp update_working_files(struct, opts) do
    work_file_opts = Keyword.get(opts, :working_files, [])

    WorkFiles.update(struct, work_file_opts)
  end

  defp check_if_path_exists?(opts, default \\ nil) do
    opts
    |> Keyword.get(:path, default)
    |> cast_existing_path()
  end

  defp cast_existing_path(nil), do: false
  defp cast_existing_path(path), do: File.exists?(path)
end
