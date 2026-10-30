"""Download the licensed Geofabrik MBTiles source, with checked HTTP ranges.

Raw country data stays in ignored build/. The app ships only the regional cut.
"""
import concurrent.futures
import json
import pathlib
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'build' / 'map-source'
URL = 'https://download.geofabrik.de/asia/thailand-shortbread-1.0.mbtiles'
AGENT = 'OffgridSOS-map-build/0.5 (+https://github.com/Yxminebest/OffGrid-SOS)'

def main():
    FOLDER.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(URL, headers={
        'User-Agent': AGENT, 'Range': 'bytes=0-99',
    }), timeout=60) as response:
        assert response.status == 206
        total = int(response.headers['Content-Range'].split('/')[-1])
        etag = response.headers['ETag']
        assert response.read().startswith(b'SQLite format 3')
        metadata = dict(url=URL, bytes=total, etag=etag,
                        last_modified=response.headers['Last-Modified'])
    manifest = FOLDER / 'download.json'
    previous = json.loads(manifest.read_text()) if manifest.exists() else None
    if previous is not None and previous != metadata:
        raise RuntimeError('Source changed; use a new build/map-source folder.')
    manifest.write_text(json.dumps(metadata, indent=2))
    chunk = 16 * 1024 * 1024
    def part(index):
        start, end = index * chunk, min(total, (index + 1) * chunk) - 1
        path = FOLDER / f'part-{index:03}.bin'
        if path.exists() and path.stat().st_size == end - start + 1:
            return index
        for attempt in range(3):
            try:
                request = urllib.request.Request(URL, headers={
                    'User-Agent': AGENT, 'Range': f'bytes={start}-{end}',
                    'If-Range': etag,
                })
                with urllib.request.urlopen(request, timeout=120) as response:
                    assert response.status == 206, 'Range was not respected'
                    assert response.headers['ETag'] == etag, 'Source changed'
                    assert response.headers['Content-Range'] == f'bytes {start}-{end}/{total}'
                    with path.open('wb') as output:
                        while block := response.read(1024 * 1024):
                            output.write(block)
                assert path.stat().st_size == end - start + 1
                print(f'part {index} complete', flush=True)
                return index
            except Exception:
                if attempt == 2: raise
                time.sleep(2)
    count = (total + chunk - 1) // chunk
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(part, range(count)))
    destination = FOLDER / 'thailand-shortbread.mbtiles'
    with destination.open('wb') as output:
        for index in range(count):
            with (FOLDER / f'part-{index:03}.bin').open('rb') as source:
                while block := source.read(1024 * 1024): output.write(block)
    assert destination.stat().st_size == total
    print(f'Complete: {total} bytes', flush=True)

if __name__ == '__main__':
    main()
