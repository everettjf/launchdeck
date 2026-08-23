# LaunchDeck 1.6 Performance Validation

Validated on August 23, 2026, on the release candidate branch.

## Search workload

The repeatable benchmark uses 10,000 synthetic installed applications and the thresholds in `Benchmarks/search-thresholds.json`.

| Measurement | Result | Gate |
| --- | ---: | ---: |
| Cold index | 1,851.0 ms | 2,500 ms |
| Incremental update | 3.7 ms | 50 ms |
| Search p95 | 58.0 ms | 75 ms |
| Ten-query sequence | 438.5 ms | 750 ms |
| Intent query | 39.8 ms | 75 ms |
| Unified search p95 | 0.4 ms | 10 ms |

## Build workload

The repository benchmark runner recorded three samples per scenario:

| Scenario | Median |
| --- | ---: |
| Clean Debug build | 4.50 s |
| Real one-file incremental build | 1.93 s |
| Zero-change build | 0.95 s |

## SwiftUI trace

An Instruments SwiftUI trace covering cold launch and steady-state rendering reported zero hangs and zero hitches over 10.84 seconds. It recorded 45,174 view updates totaling 376.87 ms. The largest individual work occurred during cold creation; repeated `AppTile` updates averaged 0.03 ms.

These measurements are environment-specific baselines. CI enforces the search gates; release candidates should be re-measured on the same machine before comparing trends.
