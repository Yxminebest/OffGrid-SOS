# Pathum Thani offline street database

© OpenStreetMap contributors, https://www.openstreetmap.org/copyright
Tiles by Geofabrik GmbH, https://download.geofabrik.de/asia/thailand.html
Database licensed under Open Database License 1.0 (ODbL): see ODbL-1.0.txt.

This is real OpenStreetMap road/water/building/place data, not a sketch or a
coordinate-only placeholder. The APK contains the complete regional pack;
there is no first-use download, remote glyph server or network tile fallback.
Data changes require rebuilding the pack and shipping an app update.

## Coverage and format

- Province boundary: OSM relation 1908797, ISO3166-2 TH-13, retained in boundary.json.
- Longitude 100.3266046–100.9570756; latitude 13.9112736–14.2810439.
- Bounding rectangle of the province plus 0.005 degrees margin, retaining all
  intersecting tiles. Neighboring parts of tiles are included as edge context.
  This is not a Thailand-wide offline database.
- Shortbread 1.0, native zoom 8–14; renderer overzooms up to 19.
- 783 gzip-compressed MVT tiles, tiles.pack = 8,652,247 bytes.
- Pack SHA-256: 152347aaf1f1ec66ec04e228d360b8b937510c736c8fc412be2d399d0844aae6
- index.json: entries `[z, x, xyz_y, offset_bytes, length_bytes]` into tiles.pack.
  Original MBTiles TMS rows were converted to XYZ once at export time.
- Manifest records source URL, ETag, source size and Last-Modified 19 Oct 2026.
  Tile generation date is not a guarantee that every OSM feature is current.

## Open database / reproducibility

The openly distributed derivative database is tiles.pack + index.json, here
alongside its license. Each indexed slice is an unchanged gzip MVT tile and can
be decoded or repacked to MBTiles using the published index. Attribution must be
retained and derivative database redistribution must comply with ODbL.

Run `python tool/download_map_source.py`, then `python tool/build_pathum_map.py`.
The original national MBTiles (~514 MB) stays in ignored build/map-source;
only this regional database is distributed with the app. Source URLs are
public, licensed raw/vector data; the build never bulk-downloads OSM's public
raster tile server. The public boundary snapshot is retained for reproducibility.

Styles light.json/dark.json are app-authored; regenerate with
`python tool/build_pathum_style.py`. No glyphs/sprites URLs are declared.
NotoSansThai.ttf is from Google Fonts (SIL OFL 1.1), see FONT-LICENSE.txt:
https://github.com/google/fonts/tree/main/ofl/notosansthai

GPS works independently of Internet but needs Android location permission,
location services enabled and a satellite fix. This map has no turn-by-turn
route engine, live traffic or live disaster/road closure information.
