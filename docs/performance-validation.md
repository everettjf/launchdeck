# LaunchDeck Performance Validation

Validated on August 23, 2026, on Apple Silicon using a Release build.

## 100k search workload

The repeatable benchmark creates 100,000 synthetic installed applications and a 200,000-item unified index. CI gates the same workload with `Benchmarks/search-thresholds-100k.json`; the checked-in evidence is `Benchmarks/search-100k-baseline.json`.

| Measurement | Result | Gate |
| --- | ---: | ---: |
| Cold application discovery | 28,079.9 ms | 100,000 ms |
| Incremental update | 76.5 ms | 800 ms |
| Fuzzy search p95 | 615.8 ms | 1,400 ms |
| Ten-query app sequence | 5,630.1 ms | 12,500 ms |
| Intent candidate retrieval | 426.7 ms | 750 ms |
| Unified search p95 | 3.4 ms | 25 ms |
| Qualified search p95 | 3.4 ms | 1,400 ms |
| Unified ten-query sequence | 1,817.8 ms | 2,500 ms |
| Qualified ten-query sequence | 1,556.9 ms | 14,000 ms |
| Five unified-index rebuilds | 7,572.0 ms | 15,000 ms |
| 100-search durability run | 18,256.3 ms | 25,000 ms |
| Memory growth after durability run | 0.5 MB | 128 MB |
| Resident memory | 1,167.1 MB | 1,200 MB |
| Index memory delta | 1,160.6 MB | 1,200 MB |

These measurements are environment-specific baselines. Release candidates should be re-measured on the same machine before comparing trends.

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
