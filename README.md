# agentevals-otel-roundtrip

> 📖 **Read the write-up:** [agentevals v0.10.0: Scores Come Back as OpenTelemetry Events](https://webofmike.com/agentevals-otel-native/)

[agentevals](https://github.com/agentevals-dev/agentevals) v0.10.0 (released 2026-10-09) went
OpenTelemetry-native: it ingests OTLP traces from any GenAI-instrumented agent and, with
`--emit-otel`, sends every evaluation score back out as a standard `gen_ai.evaluation.result`
OTel log event. The pitch is that scores show up next to your traces in whatever backend you
already run — no bespoke API to poll, no platform to host.

This repo proves that round trip against a real, independent OTel Collector, with no mocked
output: run an eval, watch the score land in the collector's logs as an OTel event.

## Problem

Agent eval tools are usually their own silo: you get a dashboard, maybe a webhook, and you
wire your own glue to get scores next to the traces that produced them. agentevals' pitch is
that the eval result *is* telemetry — the same OTLP pipe your traces already flow through.

## What this demo shows

1. A plain `otel/opentelemetry-collector-contrib` container with a `debug` (logging) exporter
   stands in for "your existing observability backend."
2. `agentevals run` scores two recorded agent traces against a golden eval set — one that
   passes, one that fails — using the deterministic `tool_trajectory_avg_score` evaluator.
3. `--emit-otel` sends both results to the collector as `gen_ai.evaluation.result` log events,
   over the standard `OTEL_EXPORTER_OTLP_ENDPOINT` variable — the same variable every other
   OTel exporter in your stack already uses.
4. The collector's own logs show the scores arriving, proving the loop closes: agentevals
   produces real OpenTelemetry, not an agentevals-shaped approximation of it.

The two sample traces (`samples/helm.json`, `samples/k8s.json`) and the eval set
(`samples/eval_set_helm.json`) are copied unmodified from the
[agentevals repo's own `samples/`](https://github.com/agentevals-dev/agentevals/tree/v0.10.0/samples)
(Apache-2.0) — a Helm agent asked to list releases, scored on whether it actually called
`helm_list_releases`.

## Architecture

```
samples/helm.json  --\
samples/k8s.json    --+-->  agentevals run --emit-otel  -->  OTel Collector  -->  debug exporter
samples/eval_set_helm.json (stdout)
```

`agentevals run` reads the recorded trace + eval set locally — no live agent needed for this
demo. In production the same binary (`agentevals serve`) also *ingests* live OTLP traces on
`:4318`/`:4317`; this repo exercises only the scores-out half, which is the part the v0.10.0
release changed most.

## Quickstart (under 5 minutes)

Requires Docker and Python 3.10+.

```bash
git clone https://github.com/themsquared/agentevals-otel-roundtrip.git
cd agentevals-otel-roundtrip
./run.sh
```

`run.sh`:
1. Starts the collector (`docker compose up -d`) on `localhost:14318`/`14317` — offset by
   +10000 from the OTel defaults so it won't collide with a collector you already have running.
2. Creates a local venv and installs `agentevals-cli==0.10.0`.
3. Runs the PASS case (`samples/helm.json`) with `--emit-otel`.
4. Runs the FAIL case (`samples/k8s.json`) with `--emit-otel`.
5. Greps the collector's own logs for the `gen_ai.evaluation.result` events and prints them.
6. Tears the collector down on exit.

Validated end to end on 2026-10-10 against `agentevals-cli` 0.10.0 and
`otel/opentelemetry-collector-contrib` 0.137.0.

### What you'll see

The PASS case:

```
[PASS]  tool_trajectory_avg_score        1  PASSED  ...
```

The FAIL case — the trace never called the tool the eval set expected:

```
[FAIL]  tool_trajectory_avg_score        0  FAILED  ...
  Invocation 1 trajectory mismatch:
    Expected:
      - helm_list_releases({})
    Actual:
      (none)
```

Note the FAIL case exits non-zero — that's `agentevals run` behaving correctly as a CI gate,
not a broken demo.

Then, from the collector's own logs, both scores as real OTel log events:

```
EventName: gen_ai.evaluation.result
Attributes:
     -> gen_ai.evaluation.name: Str(tool_trajectory_avg_score)
     -> agentevals.eval.case.id: Str(helm_list_releases)
     -> agentevals.eval_set.id: Str(helm_eval_set)
     -> agentevals.evaluator.type: Str(deterministic)
     -> gen_ai.evaluation.score.value: Double(1)
     -> gen_ai.evaluation.score.label: Str(pass)
     -> gen_ai.conversation.id: Str(ctx-...)
```

...and the second event for the FAIL case with `score.value: Double(0)` / `score.label: Str(fail)`.

## Files

- `run.sh` — the whole demo, start to finish.
- `docker-compose.yml` — the standalone OTel Collector.
- `collector/config.yaml` — OTLP receiver (4317 grpc / 4318 http) → `debug` exporter. This is
  the minimal shape; agentevals' own
  [OpenTelemetry pipelines doc](https://github.com/agentevals-dev/agentevals/blob/v0.10.0/docs/opentelemetry-pipeline.md)
  has the production recipe that forwards to a real backend (Jaeger, Tempo, Datadog, etc.)
  alongside agentevals, with a `filter` processor to drop prompt/response content from the
  backend branch and a connector that turns the score events into a histogram metric.
- `samples/` — the three trace/eval-set fixtures, copied from upstream.

## Notes

- This demo intentionally skips the *ingestion* half (sending live agent OTLP traces into
  `agentevals serve`) to keep scope to what changed most in v0.10.0 and what's provable
  without a live LLM call. The upstream README's "Evaluate a live agent" section covers that
  path; it wasn't re-validated here.
- v0.10.0 also ships experimental kagent 1.0 harness support (tool-call capture for the Claude
  Code harness, full support for Go ADK agents) — not exercised in this repo, which targets
  the Collector-facing OTel contract, not a specific agent runtime.
- Nothing here is Solo.io-specific; it's a standalone exercise of an open-source project's
  public release.

## License

Apache-2.0. See [LICENSE](LICENSE). Sample fixtures under `samples/` originate from
[agentevals-dev/agentevals](https://github.com/agentevals-dev/agentevals) (Apache-2.0).

Topics: `opentelemetry`, `ai-agents`, `observability`, `mcp`, `kubernetes`
