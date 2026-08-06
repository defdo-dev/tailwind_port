defmodule Defdo.TailwindPort.PoolStalenessTest do
  # async: false — the pool is a named singleton.
  use ExUnit.Case, async: false

  alias Defdo.TailwindPort.Pool

  @moduletag :tmp_dir

  # A stand-in for the Tailwind CLI: same `-i input -o output` contract, and it
  # copies the input to the output so a compile's result is traceable back to
  # the content that produced it. Prints the "Done in" line the readiness
  # detector looks for.
  defp fake_cli(dir) do
    path = Path.join(dir, "fake_tailwind")

    File.write!(path, """
    #!/bin/sh
    while [ $# -gt 0 ]; do
      case "$1" in
        -i) IN="$2"; shift 2 ;;
        -o) OUT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cat "$IN" > "$OUT"
    echo "Done in 1ms"
    """)

    File.chmod!(path, 0o755)
    path
  end

  setup %{tmp_dir: dir} do
    {:ok, _pid} = Pool.start_link(compile_timeout_ms: 3_000, port_ready_timeout: 3_000)

    opts = [
      cmd: fake_cli(dir),
      input: Path.join(dir, "in.css"),
      output: Path.join(dir, "out.css"),
      content: Path.join(dir, "in.css")
    ]

    {:ok, opts: opts}
  end

  test "a compile returns ITS content, not the previous one", %{opts: opts} do
    # The regression: the pool started the CLI before writing the operation's
    # content, so the run that produced the output had compiled whatever was on
    # disk from last time. The first compile returned an empty/stale artifact
    # and the second returned the first one's — an off-by-one that reads as
    # success, and in production shipped a skin one edit behind.
    assert {:ok, first} = Pool.compile(opts, ".first {}")
    assert first.compiled_css =~ ".first {}"

    assert {:ok, second} = Pool.compile(opts, ".second {}")
    assert second.compiled_css =~ ".second {}"
    refute second.compiled_css =~ ".first {}"

    assert {:ok, third} = Pool.compile(opts, ".third {}")
    assert third.compiled_css =~ ".third {}"
  end

  test "a stale output file left by an earlier run is not returned", %{opts: opts, tmp_dir: dir} do
    # The pool is fresh in every OS process, so `last_output_mtime` starts nil
    # and any pre-existing output file looked like a valid result.
    File.write!(Path.join(dir, "out.css"), ".from-a-previous-process {}")

    assert {:ok, result} = Pool.compile(opts, ".current {}")

    assert result.compiled_css =~ ".current {}"
    refute result.compiled_css =~ ".from-a-previous-process {}"
  end
end
