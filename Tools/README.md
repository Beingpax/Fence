# Tools

Scripts that are not part of the app target. They live outside `Shift/` on purpose:
that folder is a folder-synced group, so anything inside it gets compiled into the app.

## make-icon.swift

Regenerates every PNG in `Shift/Assets.xcassets/AppIcon.appiconset` and rewrites that
catalog's `Contents.json` to match. The icon is drawn in code rather than stored as a
binary blob, so changing the mark or the palette is a diff rather than a redesign.

```bash
swift Tools/make-icon.swift "Shift/Assets.xcassets/AppIcon.appiconset"
```

The palette is keyed to `AccentColor` in the asset catalog, and the mark is the same
scope glyph the menu bar uses. Keep those three in sync.

## Website catalog benchmark

From the repository root, compile the standalone benchmark with optimizations. It reads the bundled lists and creates temporary indexed SQLite copies for comparison.

```sh
benchdir="$(mktemp -d)"
swiftc -O -parse-as-library Shift/Intelligence/WebsiteCategoryCatalog.swift Tools/benchmark-website-catalogs.swift -o "$benchdir/catalog-benchmark"
"$benchdir/catalog-benchmark"
```

Each round uses 20,000 deterministic probes, half hits and half misses. Every result is checked against the input data. The tool reports the median of five rounds. Initialization includes the first query with filesystem caches warm. Lookup timings cover normalized hostname matching. Browser detection and tab closing are outside the measurement.

On an Apple M2 Pro, loading the shared JSON and looking up the first adult hostname took 10.7 ms. For subsequent adult lookups, p95 was 0.125 µs. The previous line-delimited adult catalog measured 11.2 ms and 0.084 µs in the same benchmark session. The shared index is built once, when the category picker or category matching first needs it.
