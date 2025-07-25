defmodule Defdo.TailwindPort.WorkingFiles do
  @moduledoc """
  Working files structure for TailwindPort.
  
  This module defines the structure for tracking various file paths
  used during Tailwind CSS processing.
  """
  @type path :: String.t()
  @type t :: %__MODULE__{
          input_css_path: path(),
          tailwind_config_path: path(),
          content_path: path(),
          output_css_path: path()
        }

  defstruct [:input_css_path, :tailwind_config_path, :content_path, :output_css_path]

  @doc """
  Creates a new `WorkingFiles` struct, in order to keep related filenames.

    Example:

      iex> opts = [input_css_path: "/tmp/app.css", tailwind_config_path: "/tmp/tailwind.config.js", content_path: "/tmp/index.html", output_css_path: "/tmp/output.css"]
      iex> Defdo.TailwindPort.WorkingFiles.new(opts)
      iex> %Defdo.TailwindPort.WorkingFiles{
            input_css_path: "/tmp/app.css",
            tailwind_config_path: "/tmp/tailwind.config.js",
            content_path: "/tmp/index.html",
            output_css_path: "/tmp/output.css"
          }
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts) do
    struct(__MODULE__, opts)
  end

  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{} = wf, opts) do
    struct(wf, opts)
  end
end
