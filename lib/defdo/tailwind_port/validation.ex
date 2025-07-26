defmodule Defdo.TailwindPort.Validation do
  @moduledoc """
  Validation functionality for TailwindPort.

  This module centralizes all validation logic for TailwindPort components,
  providing a consistent interface for validating arguments, configurations,
  paths, and other inputs across the entire system.

  ## Features

  - **Argument Validation**: Validates GenServer start and API arguments
  - **Path Validation**: Validates file paths, URLs, and directory structures  
  - **Configuration Validation**: Validates Tailwind configuration files
  - **Binary Validation**: Validates binary paths and executable permissions
  - **Type Validation**: Validates data types and structures

  ## Usage

      # Validate start arguments
      case Validation.validate_start_args(args) do
        :ok -> 
          # Arguments are valid
        {:error, reason} ->
          # Handle validation error
      end

      # Validate download arguments
      case Validation.validate_download_args(path, url) do
        :ok ->
          # Safe to proceed with download
        {:error, reason} ->
          # Invalid arguments
      end

  """

  @typedoc "Validation result"
  @type validation_result :: :ok | {:error, term()}

  @typedoc "Start arguments for GenServer"
  @type start_args :: keyword()

  @typedoc "Port manager arguments"
  @type port_args :: keyword()

  @doc """
  Validates arguments for GenServer start_link/1.

  This function validates the arguments passed to TailwindPort.start_link/1
  to ensure they have the correct structure and types before attempting
  to start the GenServer process.

  ## Parameters

    * `args` - Keyword list of start arguments

  ## Valid Arguments

    * `:name` - Atom name for the GenServer process (optional)
    * `:opts` - List of CLI options for Tailwind (optional)
    * `:cmd` - String path to custom binary (optional)

  ## Returns

    * `:ok` - Arguments are valid
    * `{:error, reason}` - Arguments are invalid

  ## Examples

      # Valid arguments
      assert :ok = Validation.validate_start_args([])
      assert :ok = Validation.validate_start_args([name: :my_port])
      assert :ok = Validation.validate_start_args([opts: ["-w"]])

      # Invalid arguments
      assert {:error, :invalid_name} = Validation.validate_start_args([name: "string"])
      assert {:error, :invalid_opts} = Validation.validate_start_args([opts: "string"])

  ## Error Reasons

    * `:invalid_args` - Arguments are not a keyword list
    * `:invalid_name` - Name is not an atom
    * `:invalid_opts` - Options are not a list

  """
  @spec validate_start_args(term()) :: validation_result()
  def validate_start_args(args) when is_list(args) do
    name_value = Keyword.get(args, :name)
    opts_value = Keyword.get(args, :opts)

    cond do
      Keyword.has_key?(args, :name) && not is_nil(name_value) && not is_atom(name_value) ->
        {:error, :invalid_name}

      Keyword.has_key?(args, :opts) && not is_nil(opts_value) && not is_list(opts_value) ->
        {:error, :invalid_opts}

      true ->
        :ok
    end
  end

  def validate_start_args(_), do: {:error, :invalid_args}

  @doc """
  Validates arguments for port creation.

  This function validates arguments passed to port creation functions
  to ensure they have the correct structure for creating Elixir ports
  with the Tailwind CSS binary.

  ## Parameters

    * `args` - Keyword list of port creation arguments

  ## Valid Arguments

    * `:cmd` - String path to Tailwind binary (optional)
    * `:opts` - List of CLI options (optional)

  ## Returns

    * `:ok` - Arguments are valid
    * `{:error, reason}` - Arguments are invalid

  ## Examples

      # Valid arguments
      assert :ok = Validation.validate_port_args([])
      assert :ok = Validation.validate_port_args([cmd: "/usr/bin/tailwindcss"])
      assert :ok = Validation.validate_port_args([opts: ["-i", "input.css"]])

      # Invalid arguments
      assert {:error, :invalid_cmd} = Validation.validate_port_args([cmd: 123])
      assert {:error, :invalid_opts} = Validation.validate_port_args([opts: "string"])

  """
  @spec validate_port_args(term()) :: validation_result()
  def validate_port_args(args) when is_list(args) do
    cond do
      Keyword.has_key?(args, :cmd) && not is_binary(Keyword.get(args, :cmd)) ->
        {:error, :invalid_cmd}

      Keyword.has_key?(args, :opts) && not is_list(Keyword.get(args, :opts)) ->
        {:error, :invalid_opts}

      true ->
        :ok
    end
  end

  def validate_port_args(_), do: {:error, :invalid_args}

  @doc """
  Validates arguments for download operations.

  This function validates path and URL arguments for download operations
  to ensure they are properly formatted and safe to use.

  ## Parameters

    * `path` - Destination file path
    * `base_url` - Base URL for download

  ## Returns

    * `:ok` - Arguments are valid
    * `{:error, reason}` - Arguments are invalid

  ## Examples

      # Valid arguments
      assert :ok = Validation.validate_download_args("/tmp/binary", "https://example.com")

      # Invalid arguments
      assert {:error, :invalid_path} = Validation.validate_download_args(nil, "https://example.com")
      assert {:error, :empty_url} = Validation.validate_download_args("/tmp/binary", "")

  ## Error Reasons

    * `:invalid_path` - Path is not a string or is empty
    * `:invalid_url` - URL is not a string
    * `:empty_url` - URL is an empty string

  """
  @spec validate_download_args(term(), term()) :: validation_result()
  def validate_download_args(path, base_url) do
    cond do
      not is_binary(path) || String.trim(path) == "" ->
        {:error, :invalid_path}

      not is_binary(base_url) ->
        {:error, :invalid_url}

      String.trim(base_url) == "" ->
        {:error, :empty_url}

      true ->
        :ok
    end
  end

  @doc """
  Validates configuration file syntax and structure.

  This function performs basic validation of Tailwind configuration files
  to ensure they have valid JavaScript syntax and basic structure.

  ## Parameters

    * `config_path` - Path to configuration file

  ## Returns

    * `:ok` - Configuration is valid
    * `{:error, reason}` - Configuration is invalid

  ## Examples

      # Valid config file
      assert :ok = Validation.validate_config("/path/to/valid/tailwind.config.js")

      # Invalid config file
      assert {:error, :config_not_found} = Validation.validate_config("/nonexistent/config.js")

  ## Error Reasons

    * `:config_not_found` - Configuration file does not exist
    * `:invalid_syntax` - Configuration has syntax errors
    * `:invalid_structure` - Configuration structure is invalid

  """
  @spec validate_config(String.t()) :: validation_result()
  def validate_config(config_path) when is_binary(config_path) do
    with :ok <- validate_file_exists(config_path),
         {:ok, content} <- File.read(config_path),
         :ok <- validate_config_syntax(content),
         :ok <- validate_config_structure(content) do
      :ok
    else
      {:error, :enoent} -> {:error, :config_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that a file path exists and is readable.

  ## Parameters

    * `path` - File path to validate

  ## Returns

    * `:ok` - File exists and is readable
    * `{:error, reason}` - File validation failed

  """
  @spec validate_file_exists(String.t()) :: validation_result()
  def validate_file_exists(path) when is_binary(path) do
    if File.exists?(path) && File.regular?(path) do
      :ok
    else
      {:error, :config_not_found}
    end
  end

  @doc """
  Validates that a directory path exists or can be created.

  ## Parameters

    * `path` - Directory path to validate

  ## Returns

    * `:ok` - Directory exists or can be created
    * `{:error, reason}` - Directory validation failed

  """
  @spec validate_directory(String.t()) :: validation_result()
  def validate_directory(path) when is_binary(path) do
    cond do
      File.dir?(path) ->
        :ok

      File.exists?(path) ->
        {:error, :not_a_directory}

      true ->
        # Try to create directory to validate permissions
        case File.mkdir_p(path) do
          :ok ->
            # Clean up test directory
            File.rmdir(path)
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Validates URL format and basic structure.

  ## Parameters

    * `url` - URL string to validate

  ## Returns

    * `:ok` - URL is valid
    * `{:error, reason}` - URL is invalid

  ## Examples

      # Valid URLs
      assert :ok = Validation.validate_url("https://example.com")
      assert :ok = Validation.validate_url("http://localhost:3000")

      # Invalid URLs
      assert {:error, :invalid_url_format} = Validation.validate_url("not-a-url")
      assert {:error, :unsupported_scheme} = Validation.validate_url("ftp://example.com")

  """
  @spec validate_url(String.t()) :: validation_result()
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and not is_nil(host) and host != "" ->
        :ok

      %URI{scheme: scheme} when not is_nil(scheme) and scheme not in ["http", "https"] ->
        {:error, :unsupported_scheme}

      _ ->
        {:error, :invalid_url_format}
    end
  end

  @doc """
  Validates CLI options list structure and format.

  ## Parameters

    * `opts` - List of CLI options

  ## Returns

    * `:ok` - Options are valid
    * `{:error, reason}` - Options are invalid

  ## Examples

      # Valid options
      assert :ok = Validation.validate_cli_options(["-i", "input.css", "-o", "output.css"])
      assert :ok = Validation.validate_cli_options([])

      # Invalid options
      assert {:error, :invalid_option_type} = Validation.validate_cli_options(["valid", 123])

  """
  @spec validate_cli_options(term()) :: validation_result()
  def validate_cli_options(opts) when is_list(opts) do
    if Enum.all?(opts, &is_binary/1) do
      :ok
    else
      {:error, :invalid_option_type}
    end
  end

  def validate_cli_options(_), do: {:error, :invalid_options_format}

  @doc """
  Validates process name for GenServer registration.

  ## Parameters

    * `name` - Process name (atom or tuple)

  ## Returns

    * `:ok` - Name is valid
    * `{:error, reason}` - Name is invalid

  """
  @spec validate_process_name(term()) :: validation_result()
  def validate_process_name(name) when is_atom(name) and not is_nil(name), do: :ok
  def validate_process_name({:global, name}) when is_atom(name), do: :ok
  # Catch invalid global names
  def validate_process_name({:global, _}), do: {:error, :invalid_process_name}
  def validate_process_name({:via, module, _name}) when is_atom(module), do: :ok
  # Catch invalid via tuples
  def validate_process_name({:via, _, _}), do: {:error, :invalid_process_name}
  # Catch other invalid 3-tuples
  def validate_process_name({_, _, _}), do: {:error, :invalid_process_name}
  def validate_process_name(_), do: {:error, :invalid_process_name}

  # Private helper functions

  defp validate_config_syntax(content) do
    # Basic syntax validation - check for common issues
    cond do
      String.trim(content) == "" ->
        {:error, :empty_config}

      not String.contains?(content, "module.exports") and not String.contains?(content, "export") ->
        {:error, :missing_export}

      String.contains?(content, "module.exports = {") and not String.contains?(content, "}") ->
        {:error, :unclosed_brace}

      true ->
        :ok
    end
  end

  defp validate_config_structure(_content) do
    # For now, accept any structure that passed syntax validation
    # In the future, could add more sophisticated validation
    :ok
  end
end
