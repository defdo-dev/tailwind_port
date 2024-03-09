defmodule Defdo.TailwindPort.WorkFiles do
  @moduledoc false
  @type path :: String.t()
  @type t :: %__MODULE__{
          input_css_path: path(),
          tailwind_config_path: path(),
          content_path: path()
        }

  defstruct [:input_css_path, :tailwind_config_path, :content_path]

  @doc """
  Creates a new `WorkingFiles` struct, in order to keep related filenames.

    Example:

      iex> opts = [input_css_path: "/tmp/app.css", tailwind_config_path: "/tmp/tailwind.config.js", content_path: "/tmp/index.html"]
      iex> Defdo.TailwindPort.WorkFiles.new(opts)
      iex> %Defdo.TailwindPort.WorkFiles{
            input_css_path: "/tmp/app.css",
            tailwind_config_path: "/tmp/tailwind.config.js",
            content_path: "/tmp/index.html"
          }
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts) do
    struct(__MODULE__, opts)
  end

  def update(%__MODULE__{} = wf, opts) do
    struct(wf, opts)
  end
end
