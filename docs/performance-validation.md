# LaunchDeck 1.7 Performance Validation

Validated on August 23, 2026, on Apple Silicon using a Release build.

## 100k search workload

The repeatable benchmark creates 100,000 synthetic installed applications and a 200,000-item unified index. CI gates the same workload with `Benchmarks/search-thresholds-100k.json`; the checked-in evidence is `Benchmarks/search-100k-baseline.json`.

| Measurement | Result | Gate |
| --- | ---: | ---: |
| Cold application discovery | 34,368.8 ms | 45,000 ms |
| Incremental update | 97.7 ms | 100 ms |
| Fuzzy search p95 | 709.4 ms | 750 ms |
| Ten-query sequence | 6,497.3 ms | 7,500 ms |
| Intent candidate retrieval | 446.1 ms | 750 ms |
| Unified search p95 | 4.0 ms | 25 ms |
| Qualified search p95 | 581.0 ms | 750 ms |
| Resident memory | 644.6 MB | 1,024 MB |
| Index memory delta | 638.1 MB | 800 MB |

These measurements are environment-specific baselines. Release candidates should be re-measured on the same machine before comparing trends.
