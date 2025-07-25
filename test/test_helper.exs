# Configure faster retries for tests
# 50ms instead of 1000ms
Application.put_env(:tailwind_port, :retry_delay, 50)
# 2 retries instead of 3
Application.put_env(:tailwind_port, :max_retries, 2)

# Suppress ALL logs during testing to eliminate noise completely
Logger.configure(level: :emergency)

# Disable telemetry warnings about local function handlers during tests
Application.put_env(:telemetry, :warn_on_local_function, false)

ExUnit.start()
