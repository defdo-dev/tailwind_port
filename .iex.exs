Application.put_env(:elixir, :ansi_enabled, true)

IEx.configure(
  inspect: [limit: :infinity, pretty: true],
  colors: [enabled: true],
  default_prompt:
    [
      # ANSI CHA, move cursor to column 1
      # "\e[G",
      :magenta,
      # IEx prompt variable
      "%prefix",
      # plain string
      ">",
      :reset
    ]
    |> IO.ANSI.format()
    |> IO.chardata_to_string()
)

tailwind_opts = ["--watch", "--content", "#{File.cwd!()}/priv/static/html/**/*.{html,js}", "-c", "#{File.cwd!()}/assets/tailwind.config.js"]
