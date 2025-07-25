defmodule Defdo.TailwindPort.Config do
  @moduledoc """
  Configuration management for TailwindPort.
  
  This module provides utilities for validating and managing Tailwind configuration
  files and port settings.
  """

  @type config_error :: {:error, :invalid_config | :config_not_found | :config_parse_error}

  @doc """
  Validates a Tailwind configuration file.
  """
  @spec validate_config(String.t()) :: :ok | config_error()
  def validate_config(config_path) when is_binary(config_path) do
    with {:ok, content} <- read_config_file(config_path),
         :ok <- validate_config_syntax(content),
         :ok <- validate_config_structure(content) do
      :ok
    end
  end

  @doc """
  Creates a default configuration file if it doesn't exist.
  """
  @spec ensure_config(String.t()) :: :ok | {:error, term()}
  def ensure_config(config_path) when is_binary(config_path) do
    if File.exists?(config_path) do
      validate_config(config_path)
    else
      create_default_config(config_path)
    end
  end

  @doc """
  Gets effective configuration for a TailwindPort process.
  """
  @spec get_effective_config(keyword()) :: map()
  def get_effective_config(opts \\ []) do
    %{
      binary_path: get_binary_path(opts),
      config_path: get_config_path(opts),
      input_path: get_input_path(opts),
      output_path: get_output_path(opts),
      content_paths: get_content_paths(opts),
      watch_mode: get_watch_mode(opts),
      minify: get_minify_option(opts),
      timeout: get_timeout(opts),
      retry_count: get_retry_count(opts)
    }
  end

  # Private functions

  defp read_config_file(config_path) do
    case File.read(config_path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :config_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_config_syntax(content) do
    # Basic syntax validation - check for common issues
    cond do
      not String.contains?(content, "module.exports") and not String.contains?(content, "export default") ->
        {:error, :invalid_config}
      String.contains?(content, "content:") or String.contains?(content, "content =") ->
        :ok
      true ->
        {:error, :invalid_config}
    end
  end

  defp validate_config_structure(_content) do
    # For now, we'll just do basic checks
    # In a real implementation, we might parse the JS and validate structure
    :ok
  end

  defp create_default_config(config_path) do
    default_content = """
    /** @type {import('tailwindcss').Config} */
    module.exports = {
      content: [
        "./js/**/*.js",
        "./lib/**/*.ex",
        "./lib/**/*.heex",
        "./priv/static/html/**/*.html"
      ],
      theme: {
        extend: {},
      },
      plugins: [],
    }
    """
    
    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, default_content) do
      :ok
    else
      {:error, reason} -> {:error, {:config_creation_failed, reason}}
    end
  end

  # Configuration option getters with defaults

  defp get_binary_path(opts) do
    Keyword.get(opts, :cmd, default_binary_path())
  end

  defp get_config_path(opts) do
    Keyword.get(opts, :config, "./tailwind.config.js") 
  end

  defp get_input_path(opts) do
    case Keyword.get(opts, :opts, []) do
      opts when is_list(opts) ->
        case Enum.find_index(opts, &(&1 in ["-i", "--input"])) do
          nil -> "./assets/css/app.css"
          index -> Enum.at(opts, index + 1, "./assets/css/app.css")
        end
      _ -> "./assets/css/app.css"
    end
  end

  defp get_output_path(opts) do
    case Keyword.get(opts, :opts, []) do
      opts when is_list(opts) ->
        case Enum.find_index(opts, &(&1 in ["-o", "--output"])) do
          nil -> "./priv/static/css/app.css"
          index -> Enum.at(opts, index + 1, "./priv/static/css/app.css")
        end
      _ -> "./priv/static/css/app.css"
    end
  end

  defp get_content_paths(opts) do
    case Keyword.get(opts, :opts, []) do
      opts when is_list(opts) ->
        case Enum.find_index(opts, &(&1 == "--content")) do
          nil -> ["./lib/**/*.{ex,heex}", "./priv/static/html/**/*.html"]
          index -> 
            content = Enum.at(opts, index + 1, "")
            String.split(content, ",")
        end
      _ -> ["./lib/**/*.{ex,heex}", "./priv/static/html/**/*.html"]
    end
  end

  defp get_watch_mode(opts) do
    case Keyword.get(opts, :opts, []) do
      opts when is_list(opts) -> Enum.any?(opts, &(&1 in ["-w", "--watch"]))
      _ -> false
    end
  end

  defp get_minify_option(opts) do
    case Keyword.get(opts, :opts, []) do
      opts when is_list(opts) -> Enum.any?(opts, &(&1 in ["-m", "--minify"]))
      _ -> false
    end
  end

  defp get_timeout(opts) do
    Keyword.get(opts, :timeout, 5000)
  end

  defp get_retry_count(opts) do
    Keyword.get(opts, :retry_count, 3)
  end

  defp default_binary_path do
    project_path = :code.priv_dir(:tailwind_port)
    Path.join([project_path, "bin", "tailwindcss"])
  end
end