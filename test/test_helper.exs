# Configure faster retries for tests
Application.put_env(:tailwind_port, :retry_delay, 50)  # 50ms instead of 1000ms
Application.put_env(:tailwind_port, :max_retries, 2)   # 2 retries instead of 3

ExUnit.start()
