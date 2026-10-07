# LaunchDeck Performance Validation

Validated on October 7, 2026, on Apple Silicon using a Release build, after the application and unified indexes moved to one shared matcher with top-K ranking.

## 100k search workload

The repeatable benchmark creates 100,000 synthetic installed applications and a 200,000-item unified index. The strict same-machine gates live in `Benchmarks/search-thresholds-100k.json`; the checked-in evidence is `Benchmarks/search-100k-baseline.json`.

| Measurement | Result | Gate |
| --- | ---: | ---: |
| Cold application discovery | 22,803.1 ms | 100,000 ms |
| Incremental update | 63.2 ms | 800 ms |
| Fuzzy search p95 | 261.0 ms | 1,400 ms |
| Ten-query app sequence | 218.4 ms | 12,500 ms |
| Intent candidate retrieval | 186.5 ms | 750 ms |
| Unified search p95 | 2.5 ms | 25 ms |
| Qualified search p95 | 2.5 ms | 1,400 ms |
| Unified ten-query sequence | 743.5 ms | 2,500 ms |
| Qualified ten-query sequence | 796.6 ms | 14,000 ms |
| Five unified-index rebuilds | 4,899.0 ms | 15,000 ms |
| 100-search durability run | 7,749.8 ms | 25,000 ms |
| Memory growth after durability run | 0.0 MB | 128 MB |
| Resident memory | 1,167.5 MB | 1,200 MB |
| Index memory delta | 1,161.2 MB | 1,200 MB |

These measurements are environment-specific baselines. Release candidates should be re-measured on the same machine before comparing trends.

GitHub Actions runs the identical workload against
`Benchmarks/search-thresholds-100k-ci.json`. Most timing ceilings are 25% above
the strict local gates. The repeated unified-query and durability loops use a
60% allowance because their cumulative timings show substantially higher
scheduling variance on shared macOS runners. Memory ceilings are 1,350 MB, about
15% above the measured baseline: resident memory shifts with runner images and the
system allocator, and the previous 2.8% margin could fail CI without any code change,
while 15% still catches a regression of roughly 180 MB or more. The strict local gate
stays at 1,200 MB.
Benchmark JSON is uploaded on every run, including failures, so a sustained
regression remains inspectable.

## Reliability and interaction gates

The 100k CI workload also guards the paths exercised by the launcher UI:

- a ten-step incremental query sequence, matching continuous typing;
- a qualified ten-step sequence using `kind:` and `ext:` filters;
- five complete unified-index rebuilds;
- 100 repeated searches followed by a resident-memory growth check.

The app job builds the universal Release product and runs
`scripts/validate-runtime-smoke.sh`. That script launches and terminates the
actual app binary three times, verifies that every cold launch remains alive,
and reports resident memory for each cycle. Unit tests separately cover stale
intent cancellation, local-index cancellation, corrupt-cache recovery, stable
search selection, application incremental refresh, and coalesced icon loads.
