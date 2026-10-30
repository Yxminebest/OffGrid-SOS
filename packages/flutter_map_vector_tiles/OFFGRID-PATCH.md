# Local font patch

Upstream: flutter_map_vector_tiles 2.9.1, downloaded from pub.dev.
Repository: https://github.com/JonasGrunau/flutter-map-vector-tiles
License: BSD-3-Clause; original LICENSE and library source retained.

Only behavioral change: `lib/src/render/label_painter.dart`, `_textStyle`, now
passes the style's `text-font` family list to Flutter's `fontFamily` and
`fontFamilyFallback`. Upstream 2.9.1 used that list only to infer weight/style,
so a bundled Thai font was ignored by map labels. The app's Shortbread styles
specify `NotoSansThai`, shipped in the APK under SIL OFL. No remote glyph fetch.
Packaging only: omitted upstream screenshots/examples/tests; removed screenshot
entries from the local package manifest. Original library license retained.

Regression: `test/bundled_pathum_map_test.dart` renders real Thai place/road
labels with the bundled font, light/dark map, in an offline widget harness.
No national map data or pub cache paths are needed to build the application.
