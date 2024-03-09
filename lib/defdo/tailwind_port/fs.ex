defmodule Defdo.TailwindPort.FS do
  @moduledoc false
  alias Defdo.TailwindPort.WorkFiles

  @type t :: %__MODULE__{
          path: WorkFiles.path(),
          path_exists: boolean(),
          work_files: WorkFiles.t()
        }

  defstruct path: nil,
            path_exists: false,
            work_files: %WorkFiles{}

  @doc """
  Creates a new `FS` (FileSystem) struct, in order to keep related working paths.

    Example:

      iex> opts = [
        path: "/tmp",
        work_files: [
          input_css_path: "/tmp/app.css",
          tailwind_config_path: "/tmp/tailwind.config.js",
          content_path: "/tmp/index.html"
        ]
      ]
      iex> Defdo.TailwindPort.FS.new(opts)
      iex> %Defdo.TailwindPort.FS{
        path: "/tmp",
        path_exists: true,
        work_files: %Defdo.TailwindPort.WorkFiles{
          input_css_path: "/tmp/app.css",
          tailwind_config_path: "/tmp/tailwind.config.js",
          content_path: "/tmp/index.html"
        }
      }
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts) do
    work_files = get_work_files(opts)
    path_exists = check_if_path_exists?(opts)

    new_opts =
      opts
      |> Keyword.put(:work_files, work_files)
      |> Keyword.put(:path_exists, path_exists)

    struct(__MODULE__, new_opts)
  end

  def update(%__MODULE__{path: path, work_files: %WorkFiles{} = work_file} = struct, opts) do
    work_files = update_work_files(work_file, opts)

    path_exists = check_if_path_exists?(opts, path)

    updated_opts =
      opts
      |> Keyword.put(:work_files, work_files)
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

  defp get_work_files(opts, default \\ []) do
    work_files_opts = Keyword.get(opts, :work_files, default)

    WorkFiles.new(work_files_opts)
  end

  defp update_work_files(struct, opts) do
    work_file_opts = Keyword.get(opts, :work_files, [])

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
