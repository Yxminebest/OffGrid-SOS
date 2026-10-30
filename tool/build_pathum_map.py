"""Cut licensed Shortbread MBTiles into an offline, APK-bundled regional pack.

Run download_map_source.py first. No raster tile server is contacted. All source
tiles intersecting the province bounding box + 0.005 degree margin are retained.
The resulting ODbL database is distributed openly in assets/maps/pathum_thani/.
"""
import hashlib
import json
import math
import pathlib
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/maps/pathum_thani'

def tile(lat, lon, z):
    return (int((lon + 180) / 360 * 2**z),
            int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2**z))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source_boundary = ROOT / 'build/pathum-boundary.json'
    if source_boundary.exists():
        boundary = json.loads(source_boundary.read_text(encoding='utf-8'))
        relation = next(e for e in boundary['elements'] if e['type'] == 'relation')
    else:
        relation = json.loads((OUT/'boundary.json').read_text(encoding='utf-8'))
    bounds = relation['bounds']
    coverage = [bounds['minlon'] - .005, bounds['minlat'] - .005,
                bounds['maxlon'] + .005, bounds['maxlat'] + .005]
    db = sqlite3.connect(ROOT / 'build/map-source/thailand-shortbread.mbtiles')
    entries, data = [], bytearray()
    for z in range(8, 15):
        x0, y0 = tile(coverage[3], coverage[0], z)
        x1, y1 = tile(coverage[1], coverage[2], z)
        rows = db.execute('select tile_column, tile_row, tile_data from tiles '
                          'where zoom_level=? and tile_column between ? and ? '
                          'and tile_row between ? and ? order by tile_column, tile_row',
                          (z, x0, x1, 2**z-1-y1, 2**z-1-y0)).fetchall()
        assert len(rows) == (x1-x0+1)*(y1-y0+1), f'Missing source tile at {z}'
        for x, row, blob in rows:
            entries.append([z, x, 2**z-1-row, len(data), len(blob)])
            data.extend(blob)
    pack = OUT / 'tiles.pack'
    pack.write_bytes(data)
    download = json.loads((ROOT / 'build/map-source/download.json').read_text())
    manifest = dict(format=1, id='pathum-thani-shortbread-20261019',
                    name='Pathum Thani', minzoom=8, maxzoom=14,
                    bounds=coverage, province_bounds=bounds, boundary_relation=relation['id'],
                    data_date='2026-10-19', source=download,
                    attribution='© OpenStreetMap contributors; tiles by Geofabrik',
                    license='ODbL-1.0', license_url='https://opendatacommons.org/licenses/odbl/1-0/',
                    bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), tiles=entries)
    (OUT/'index.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (OUT/'boundary.json').write_text(json.dumps(relation, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(f'{len(entries)} tiles; {len(data):,} bytes; sha256={manifest["sha256"]}')

if __name__ == '__main__':
    main()
