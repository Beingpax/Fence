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
