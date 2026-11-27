# Tools

Scripts that are not part of the app target. They live outside `Fence/` on purpose:
that folder is a folder-synced group, so anything inside it gets compiled into the app.

## Website catalog benchmark

From the repository root, compile the standalone benchmark with optimizations. It reads the bundled lists and creates temporary indexed SQLite copies for comparison.

```sh
benchdir="$(mktemp -d)"
swiftc -O -parse-as-library Fence/Intelligence/WebsiteCategoryCatalog.swift Tools/benchmark-website-catalogs.swift -o "$benchdir/catalog-benchmark"
"$benchdir/catalog-benchmark"
```

Each round uses 20,000 deterministic probes, half hits and half misses. Every result is checked against the input data. The tool reports the median of five rounds. Initialization includes the first query with filesystem caches warm. Lookup timings cover normalized hostname matching. Browser detection and tab closing are outside the measurement.

On an Apple M2 Pro, loading the shared JSON and looking up the first adult hostname took 10.7 ms. For subsequent adult lookups, p95 was 0.125 µs. The previous line-delimited adult catalog measured 11.2 ms and 0.084 µs in the same benchmark session. The shared index is built once, when the category picker or category matching first needs it.
