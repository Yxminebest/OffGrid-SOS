"""Generate the app-owned, offline Shortbread style. No remote glyphs/sprites."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'assets/maps/pathum_thani'

def build(dark=False):
    layers = [dict(id='background', type='background', paint={
        'background-color': '#242b32' if dark else '#f5f3e9'})]
    def layer(id, type, source, paint, minimum=8, filter=None, layout=None):
        item = dict(id=id, type=type, source='shortbread', minzoom=minimum,
                    paint=paint, **{'source-layer': source})
        if filter is not None: item['filter'] = filter
        if layout is not None: item['layout'] = layout
        layers.append(item)
    layer('land', 'fill', 'land', {'fill-color': '#35463b' if dark else '#dce8cd'})
    layer('sites', 'fill', 'sites', {'fill-color': '#414044' if dark else '#ebe0d7'}, 13)
    layer('water', 'fill', 'water_polygons', {'fill-color': '#284f68' if dark else '#a4d6e6'})
    layer('canals', 'line', 'water_lines', {'line-color': '#3d708d' if dark else '#82bdcf',
          'line-width': ['interpolate', ['linear'], ['zoom'], 8, .5, 14, 2.2, 19, 8]})
    layer('buildings', 'fill', 'buildings', {'fill-color': '#515456' if dark else '#d9d3c5',
          'fill-outline-color': '#606263' if dark else '#c8c0af'}, 14)
    layer('street-areas', 'fill', 'street_polygons', {'fill-color': '#636465' if dark else '#ffffff'}, 13)
    width = ['interpolate', ['linear'], ['zoom'], 8, .4, 12, 1.5, 14, 3, 17, 8, 19, 17]
    layer('roads-case', 'line', 'streets', {'line-color': '#20262c' if dark else '#c3bda9',
          'line-width': ['interpolate', ['linear'], ['zoom'], 8, 1, 12, 2.5, 14, 4.5, 17, 10, 19, 20]})
    layer('roads', 'line', 'streets', {'line-color': '#8c8b81' if dark else '#ffffff', 'line-width': width})
    layer('main-roads', 'line', 'streets', {'line-color': '#d1a95c' if dark else '#f7ce6f',
          'line-width': ['interpolate', ['linear'], ['zoom'], 8, 1, 12, 3, 14, 5, 17, 11, 19, 22]},
          filter=['in', 'kind', 'motorway', 'trunk', 'primary', 'secondary', 'tertiary'])
    layer('rails', 'line', 'streets', {'line-color': '#9aa4a8' if dark else '#807c78',
          'line-width': 1.5, 'line-dasharray': [3, 2]}, 11, ['==', 'rail', True])
    layer('boundary', 'line', 'boundaries', {'line-color': '#b695ba' if dark else '#9a82a0',
          'line-width': 1.2, 'line-dasharray': [4, 3]}, 8)
    def label(id, source, minimum, size, color=None, line=False, filter=None):
        layout = {'text-field': ['coalesce', ['get', 'name'], ['get', 'name_en'], ['get', 'ref'], ''],
                  'text-font': ['NotoSansThai'], 'text-size': size,
                  'text-max-width': 9, 'text-padding': 5,
                  'symbol-placement': 'line' if line else 'point'}
        layer(id, 'symbol', source, {'text-color': color or ('#f3eee0' if dark else '#353a38'),
              'text-halo-color': '#242b32' if dark else '#fffdf4', 'text-halo-width': 1.4}, minimum, filter, layout)
    label('places', 'place_labels', 8, ['interpolate', ['linear'], ['zoom'], 8, 12, 14, 15, 18, 17])
    label('street-names', 'street_labels', 13, 12, line=True)
    label('river-names', 'water_lines_labels', 12, 12, '#8dc6df' if dark else '#336e87', True)
    label('landmark-names', 'pois', 15, 12, filter=['in', 'amenity', 'hospital', 'clinic', 'police', 'fire_station', 'school', 'university', 'place_of_worship'])
    return dict(version=8, name='Offgrid Pathum Thani '+('dark' if dark else 'light'),
                sources={'shortbread': {'type': 'vector', 'minzoom': 8, 'maxzoom': 14}}, layers=layers)

if __name__ == '__main__':
    for dark in (False, True):
        (OUT / ('dark.json' if dark else 'light.json')).write_text(
            json.dumps(build(dark), ensure_ascii=False, indent=2), encoding='utf-8')
