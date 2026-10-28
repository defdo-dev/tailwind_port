defmodule Defdo.TailwindPort.PoolBoundsTest do
  # async: false — the pool is a named singleton.
  use ExUnit.Case, async: false

  alias Defdo.TailwindPort.Pool

  @moduletag :tmp_dir

  # Stand-ins for the Tailwind CLI. Each records its OS pid next to the output
  # (`<out>.pid`) and appends a line per run (`<out>.runs`), so a test can check
  # that the OS process is really gone and how many CLI runs happened.
  #
  #   * :fast  — copies input to output, exits.
  #   * :slow  — the same after 400ms.
  #   * :hang  — never writes output, never exits (a stuck compile).
  #   * :watch — writes output, then stays alive like a watcher.
  defp fake_cli(dir, kind) do
    path = Path.join(dir, "fake_tailwind_#{kind}")

    {before, write, after_write} =
      case kind do
        :fast -> {"", ~s(cat "$IN" > "$OUT"), ""}
        :slow -> {"sleep 0.4", ~s(cat "$IN" > "$OUT"), ""}
        :hang -> {"", "", "exec sleep 30"}
        :watch -> {"", ~s(cat "$IN" > "$OUT"), "exec sleep 30"}
      end

    File.write!(path, """
    #!/bin/sh
    while [ $# -gt 0 ]; do
      case "$1" in
        -i) IN="$2"; shift 2 ;;
        -o) OUT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo $$ > "$OUT.pid"
    echo run >> "$OUT.runs"
    #{before}
    #{write}
    echo "Done in 1ms"
    #{after_write}
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp opts_for(dir, cli, name, extra \\ []) do
    [
      cmd: cli,
      input: Path.join(dir, "#{name}.css"),
      output: Path.join(dir, "#{name}.out.css"),
      content: Path.join(dir, "#{name}.css")
    ] ++ extra
  end

  defp start_pool(opts) do
    start_supervised!(
      {Pool, Keyword.merge([compile_timeout_ms: 3_000, port_ready_timeout: 500], opts)}
    )
  end

  defp os_pid_for(opts) do
    path = opts[:output] <> ".pid"
    wait_until(fn -> File.exists?(path) and File.read!(path) != "" end)
    path |> File.read!() |> String.trim()
  end

  defp os_alive?(os_pid) do
    match?({_, 0}, System.cmd("kill", ["-0", os_pid], stderr_to_stdout: true))
  end

  defp wait_until(fun, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_until(fun, deadline)
    assert fun.(), "condition not met within #{timeout}ms"
  end

  defp poll_until(fun, deadline) do
    unless fun.() or System.monotonic_time(:millisecond) > deadline do
      Process.sleep(25)
      poll_until(fun, deadline)
    end
  end

  defp pool_children do
    Registry.select(TailwindPort.PoolRegistry, [{{{Pool, :_}, :"$1", :_}, [], [:"$1"]}])
  end

  setup do
    # Ports left by another test module must not count against this one.
    Enum.each(
      pool_children(),
      &DynamicSupervisor.terminate_child(TailwindPort.DynamicSupervisor, &1)
    )

    :ok
  end

  test "the size cap holds across distinct configurations", %{tmp_dir: dir} do
    start_pool(max_pool_size: 2, max_queue: 10)
    cli = fake_cli(dir, :slow)

    tasks =
      for i <- 1..5 do
        Task.async(fn -> Pool.compile(opts_for(dir, cli, "cfg#{i}"), ".c#{i} {}") end)
      end

    samples =
      for _ <- 1..30 do
        Process.sleep(40)
        {Pool.get_stats().active_ports, length(pool_children())}
      end

    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.all?(samples, fn {ports, procs} -> ports <= 2 and procs <= 2 end)
    assert Enum.any?(samples, fn {ports, _} -> ports == 2 end)
  end

  test "a failed compile frees its slot and kills the OS process", %{tmp_dir: dir} do
    start_pool(max_pool_size: 1, compile_timeout_ms: 400)
    opts = opts_for(dir, fake_cli(dir, :hang), "stuck")

    assert {:error, :compile_timeout} = Pool.compile(opts, ".stuck {}")
    os_pid = os_pid_for(opts)

    assert Pool.get_stats().active_ports == 0
    assert pool_children() == []
    wait_until(fn -> not os_alive?(os_pid) end)

    # The single slot is usable again.
    assert {:ok, %{compiled_css: css}} =
             Pool.compile(opts_for(dir, fake_cli(dir, :fast), "next"), ".next {}")

    assert css =~ ".next {}"
  end

  test "stopping the pool stops every CLI it owns", %{tmp_dir: dir} do
    start_pool(compile_timeout_ms: 10_000)
    opts = opts_for(dir, fake_cli(dir, :hang), "held")

    caller = spawn(fn -> Pool.compile(opts, ".held {}") end)
    os_pid = os_pid_for(opts)
    assert [_] = pool_children()

    stop_supervised!(Pool)
    Process.exit(caller, :kill)

    assert pool_children() == []
    wait_until(fn -> not os_alive?(os_pid) end)
  end

  test "a pool killed outright has its orphans reaped on restart", %{tmp_dir: dir} do
    {:ok, pool} = GenServer.start(Pool, compile_timeout_ms: 10_000)
    Process.register(pool, Pool)
    opts = opts_for(dir, fake_cli(dir, :hang), "orphan")

    caller = spawn(fn -> Pool.compile(opts, ".orphan {}") end)
    os_pid = os_pid_for(opts)
    assert [_] = pool_children()

    # No terminate/2: the CLI is still running with nobody tracking it.
    Process.exit(pool, :kill)
    Process.exit(caller, :kill)
    Process.sleep(50)
    assert os_alive?(os_pid)

    start_pool([])

    assert pool_children() == []
    wait_until(fn -> not os_alive?(os_pid) end)
  end

  test "concurrent callers are not serialised below the size cap", %{tmp_dir: dir} do
    start_pool(max_pool_size: 3)
    cli = fake_cli(dir, :slow)

    {micros, results} =
      :timer.tc(fn ->
        1..3
        |> Enum.map(fn i ->
          Task.async(fn -> Pool.compile(opts_for(dir, cli, "par#{i}"), ".p#{i} {}") end)
        end)
        |> Task.await_many(10_000)
      end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    # Three 400ms runs back to back would take 1.2s.
    assert micros < 1_100_000, "took #{div(micros, 1000)}ms — compiles were serialised"
  end

  test "a full queue rejects with :busy; a queued caller is served later", %{tmp_dir: dir} do
    start_pool(max_pool_size: 1, max_queue: 1)
    slow = fake_cli(dir, :slow)

    holder = Task.async(fn -> Pool.compile(opts_for(dir, slow, "a"), ".a {}") end)
    wait_until(fn -> Pool.get_stats().busy_ports == 1 end)

    queued = Task.async(fn -> Pool.compile(opts_for(dir, slow, "b"), ".b {}") end)
    wait_until(fn -> Pool.get_stats().queue_size == 1 end)

    assert {:error, :busy} = Pool.compile(opts_for(dir, slow, "c"), ".c {}")

    assert {:ok, %{compiled_css: a}} = Task.await(holder, 5_000)
    assert {:ok, %{compiled_css: b}} = Task.await(queued, 5_000)
    assert a =~ ".a {}"
    assert b =~ ".b {}"
    assert Pool.get_stats().pool_exhaustions == 1
  end

  test "a queued caller times out instead of waiting forever", %{tmp_dir: dir} do
    start_pool(
      max_pool_size: 1,
      max_queue: 1,
      checkout_timeout_ms: 200,
      compile_timeout_ms: 2_000
    )

    holder =
      Task.async(fn -> Pool.compile(opts_for(dir, fake_cli(dir, :hang), "h"), ".h {}") end)

    wait_until(fn -> Pool.get_stats().busy_ports == 1 end)

    assert {:error, :checkout_timeout} =
             Pool.compile(opts_for(dir, fake_cli(dir, :fast), "w"), ".w {}")

    assert {:error, :compile_timeout} = Task.await(holder, 5_000)
  end

  test "a caller that dies mid-compile has its port retired", %{tmp_dir: dir} do
    start_pool(compile_timeout_ms: 10_000)
    opts = opts_for(dir, fake_cli(dir, :hang), "dead_caller")

    caller = spawn(fn -> Pool.compile(opts, ".x {}") end)
    os_pid = os_pid_for(opts)
    assert Pool.get_stats().busy_ports == 1

    Process.exit(caller, :kill)

    wait_until(fn -> Pool.get_stats().active_ports == 0 end)
    assert pool_children() == []
    wait_until(fn -> not os_alive?(os_pid) end)
  end

  test "one-shot ports never stay in the pool", %{tmp_dir: dir} do
    start_pool([])
    opts = opts_for(dir, fake_cli(dir, :fast), "oneshot")

    assert {:ok, _} = Pool.compile(opts, ".one {}")
    assert Pool.get_stats().active_ports == 0
    assert pool_children() == []
  end

  test "watch ports stay idle, then are swept after the idle timeout", %{tmp_dir: dir} do
    start_pool(port_idle_timeout_ms: 100, cleanup_interval: 50)
    opts = opts_for(dir, fake_cli(dir, :watch), "watched", watch: true)

    assert {:ok, _} = Pool.compile(opts, ".w {}")
    os_pid = os_pid_for(opts)
    assert Pool.get_stats().active_ports == 1

    wait_until(fn -> Pool.get_stats().active_ports == 0 end)
    wait_until(fn -> not os_alive?(os_pid) end)
  end

  test "port_idle_timeout_ms: 0 scales to zero after every compile", %{tmp_dir: dir} do
    start_pool(port_idle_timeout_ms: 0)
    opts = opts_for(dir, fake_cli(dir, :watch), "zero", watch: true)

    assert {:ok, _} = Pool.compile(opts, ".z {}")
    os_pid = os_pid_for(opts)

    assert Pool.get_stats().active_ports == 0
    assert pool_children() == []
    wait_until(fn -> not os_alive?(os_pid) end)
  end

  test "creating ports does not create atoms", %{tmp_dir: dir} do
    start_pool([])
    cli = fake_cli(dir, :fast)
    # Warm every code path once so module loading does not count.
    assert {:ok, _} = Pool.compile(opts_for(dir, cli, "warm"), ".w {}")

    before = :erlang.system_info(:atom_count)

    for i <- 1..20 do
      assert {:ok, _} = Pool.compile(opts_for(dir, cli, "atom#{i}"), ".a#{i} {}")
    end

    assert :erlang.system_info(:atom_count) - before < 5
  end

  test "pool-managed temp files are deleted when the port retires", %{tmp_dir: dir} do
    start_pool([])
    managed = Pool.managed_dir()
    File.mkdir_p!(managed)
    before = MapSet.new(File.ls!(managed))

    # No :input/:output/:content — the pool provides scratch files.
    assert {:ok, %{output_path: output}} =
             Pool.compile([cmd: fake_cli(dir, :fast)], ".managed-#{System.unique_integer()} {}")

    assert Path.dirname(output) == managed
    left = managed |> File.ls!() |> MapSet.new() |> MapSet.difference(before)
    # The fake CLI's own <out>.pid / <out>.runs bookkeeping is not pool state.
    assert Enum.reject(left, &String.ends_with?(&1, [".pid", ".runs"])) == []
    Enum.each(left, &File.rm(Path.join(managed, &1)))
  end

  test "identical concurrent compiles share one CLI run", %{tmp_dir: dir} do
    start_pool(max_pool_size: 1, max_queue: 0)
    opts = opts_for(dir, fake_cli(dir, :slow), "shared")

    results =
      1..3
      |> Enum.map(fn _ -> Task.async(fn -> Pool.compile(opts, ".same {}") end) end)
      |> Task.await_many(5_000)

    assert [{:ok, a}, {:ok, b}, {:ok, c}] = results
    assert a.compiled_css == b.compiled_css and b.compiled_css == c.compiled_css
    assert length(Enum.uniq([a.operation_id, b.operation_id, c.operation_id])) == 3
    assert File.read!(opts[:output] <> ".runs") == "run\n"
    assert Pool.get_stats().single_flight_hits == 2
  end
end
