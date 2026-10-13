"""More pages and feeds for the Browser, Maps and Weather fixtures (C159, C160, C156), hooked into host_services.py.

get(handler, host, path, query) and post(handler, host, path, raw) answer and return True, or return False to let
the older routes of host_services.py answer. Everything here is written from the documented shape of the thing it
stands for (an HTML form, an OSRM route, a Nominatim search), not captured from a live service.
"""
import pathlib
import urllib.parse

here = pathlib.Path(__file__).resolve().parent

PAGE_POST = (b'<!doctype html><html><head><title>Post form</title></head><body><h1>Post form</h1>'
             b'<form action="/pages/submit.html" method="post">'
             b'<input type="text" name="user" value="ada"><input type="text" name="note" value="hi">'
             b'<input type="hidden" name="token" value="t1"><input type="submit" value="Send"></form></body></html>')
PAGE_PHOTOS = (b'<!doctype html><html><head><title>Photos</title></head><body><h1>Photos</h1>'
               b'<img src="/pages/logo.png" alt="logo"><img src="/pages/photo.jpg" alt="photo">'
               b'<p>Two pictures.</p></body></html>')
PAGE_ETAG = (b'<!doctype html><html><head><title>Versioned</title></head><body><h1>Versioned</h1>'
             b'<p>This page carries an ETag.</p><p><a href="/pages/about.html">About</a></p></body></html>')
ETAG = '"v7"'
# A page with its own stylesheet: a colour and centring on the heading, a size and a colour on a class, a hidden
# paragraph, a bold one and an inline style.
PAGE_STYLED = (b'<!doctype html><html><head><title>Styled</title><style>'
               b'h1{color:#ff8800;text-align:center} .big{font-size:28px;color:#33cc66} .hide{display:none} '
               b'p.note{font-weight:bold}</style></head><body><h1>Styled page</h1>'
               b'<p class="big">Big green</p><p class="hide">hidden text</p><p class="note">Bold note</p>'
               b'<div style="color:#4488ff">Inline blue</div></body></html>')


def tile_for(z, x, y):
    """(C160) A vector tile of the pyramid: a main road across it (so it continues in the tile next to it), a street
    down the middle, a river, and one place named by the tile; the layers are built as maptile.py builds the first."""
    import maptile
    road = [[(0, 1500 + 20 * (y % 5)), (2048, 1700), (4096, 1500 + 20 * (y % 5))]]
    street = [[(2048, 0), (2048, 4096)]]
    river = [[(0, 3500), (2000, 3300), (4096, 3600)]]
    roads = [maptile.feature([0, 0], 2, maptile.line_geometry(street)),
             maptile.feature([0, 1], 2, maptile.line_geometry(road))]
    name = '%d/%d/%d' % (z, x, y)
    transportation = maptile.layer('transportation', roads, ['class'], ['street', 'primary'])
    water = maptile.layer('water', [maptile.feature([], 2, maptile.line_geometry(river))], [], [])
    poi = maptile.layer('poi', [maptile.feature([0, 0], 1, maptile.point_geometry([(1000, 2500)]))], ['name'], [name])
    return (maptile.field_bytes(3, transportation) + maptile.field_bytes(3, water) + maptile.field_bytes(3, poi))


# (C160) What the place search answers for "library": Nominatim's jsonv2 shape (lat and lon are strings), two places
# near the first tile (14/8681/4769).
SEARCH_RESULTS = [
    {'place_id': 1001, 'osm_type': 'node', 'osm_id': 5001, 'lat': '59.87107', 'lon': '10.75122', 'category': 'amenity',
     'type': 'library', 'importance': 0.31, 'display_name': 'City Library, Oslo'},
    {'place_id': 1002, 'osm_type': 'way', 'osm_id': 5002, 'lat': '59.87516', 'lon': '10.76221', 'category': 'amenity',
     'type': 'library', 'importance': 0.22, 'display_name': 'North Branch Library, Oslo'},
]


def haversine(lat1, lon1, lat2, lon2):
    import math
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371008.8 * 2 * math.asin(math.sqrt(a))


def osrm_route(path):
    """(C160) /route/v1/foot/lon,lat;lon,lat in OSRM's JSON: an L-shaped way (east-west first, then north-south) with
    a depart, a turn and an arrive step; lengths by haversine, a pace by profile (foot 1.4, bike 4.5, car 11 m/s)."""
    profile, coordinates = path.split('/route/v1/')[1].split('?')[0].split('/', 1)
    pace = {'foot': 1.4, 'bike': 4.5, 'car': 11.0}.get(profile, 1.4)
    (lon1, lat1), (lon2, lat2) = [tuple(float(v) for v in pair.split(',')) for pair in coordinates.split(';')]
    corner = (lon2, lat1)
    leg1 = haversine(lat1, lon1, lat1, lon2)
    leg2 = haversine(lat1, lon2, lat2, lon2)
    total = leg1 + leg2
    turn = 'left' if lat2 > lat1 else 'right'
    if lon2 < lon1:
        turn = 'right' if lat2 > lat1 else 'left'
    import json
    return json.dumps({
        'code': 'Ok',
        'routes': [{
            'distance': round(total, 1), 'duration': round(total / pace, 1), 'weight': round(total / pace, 1),
            'weight_name': 'routability',
            'geometry': {'type': 'LineString', 'coordinates': [[lon1, lat1], [corner[0], corner[1]], [lon2, lat2]]},
            'legs': [{'distance': round(total, 1), 'duration': round(total / pace, 1), 'summary': 'Karl Johans gate',
                      'steps': [
                          {'distance': round(leg1, 1), 'duration': round(leg1 / pace, 1), 'name': 'Karl Johans gate',
                           'maneuver': {'type': 'depart', 'location': [lon1, lat1]}},
                          {'distance': round(leg2, 1), 'duration': round(leg2 / pace, 1), 'name': 'Akersgata',
                           'maneuver': {'type': 'turn', 'modifier': turn, 'location': [corner[0], corner[1]]}},
                          {'distance': 0, 'duration': 0, 'name': '',
                           'maneuver': {'type': 'arrive', 'location': [lon2, lat2]}}]}]}],
        'waypoints': []}).encode('utf-8')


def get(handler, host, path, query):
    import json
    if host == 'tiles.openfreemap.org' and path.startswith('/planet/') and path.endswith('.pbf'):
        parts = path[:-4].split('/')
        z, x, y = int(parts[-3]), int(parts[-2]), int(parts[-1])
        if (z, x, y) != (14, 8681, 4769):
            handler.reply(200, tile_for(z, x, y), 'application/x-protobuf')
            return True
        return False
    if host == 'nominatim.openstreetmap.org' and path == '/search':
        wanted = query.get('q', [''])[0].lower()
        found = SEARCH_RESULTS if 'library' in wanted else []
        handler.reply(200, json.dumps(found).encode('utf-8'), 'application/json')
        return True
    if host == 'api.weather.gov' and path == '/alerts/active':
        # (C156) The National Weather Service's active alerts for a point (GeoJSON, the documented shape, not captured):
        # a wind advisory over Seattle's point, none anywhere else.
        if query.get('point', [''])[0] == '47.61,-122.33':
            body = {'type': 'FeatureCollection', 'features': [{'type': 'Feature', 'properties': {
                'event': 'Wind Advisory', 'severity': 'Moderate', 'areaDesc': 'Seattle',
                'headline': 'Wind Advisory until 9 PM PDT'}}]}
        else:
            body = {'type': 'FeatureCollection', 'features': []}
        handler.reply(200, json.dumps(body).encode('utf-8'), 'application/geo+json')
        return True
    if host == 'router.project-osrm.org' and path.startswith('/route/v1/'):
        handler.reply(200, osrm_route(handler.path), 'application/json')
        return True
    if host != 'neper.test':
        return False
    if path == '/pages/post.html':
        handler.reply(200, PAGE_POST, 'text/html')
        return True
    if path == '/pages/photos.html':
        handler.reply(200, PAGE_PHOTOS, 'text/html')
        return True
    if path == '/pages/styled.html':
        handler.reply(200, PAGE_STYLED, 'text/html')
        return True
    if path == '/pages/logo.png':
        handler.reply(200, (here / 'logo-24.png').read_bytes(), 'image/png')
        return True
    if path == '/pages/photo.jpg':
        handler.reply(200, (here / 'photo-32.jpg').read_bytes(), 'image/jpeg')
        return True
    if path == '/pages/etag.html':
        # A page with a validator: a request that names it in If-None-Match gets 304 and no body.
        if handler.headers.get('If-None-Match') == ETAG:
            handler.send_response(304)
            handler.send_header('ETag', ETAG)
            handler.send_header('Content-Length', '0')
            handler.end_headers()
            return True
        handler.reply(200, PAGE_ETAG, 'text/html', (('ETag', ETAG),))
        return True
    return False


def post(handler, host, path, raw):
    if host == 'neper.test' and path == '/pages/submit.html':
        fields = urllib.parse.parse_qs(raw.decode('utf-8'))
        shown = ', '.join('%s=%s' % (k, v[0]) for k, v in sorted(fields.items()))
        page = ('<!doctype html><html><head><title>Posted</title></head><body><h1>Posted</h1>'
                '<p>Body: %s</p><p>Type: %s</p></body></html>'
                % (shown, handler.headers.get('Content-Type'))).encode('utf-8')
        handler.reply(200, page, 'text/html')
        return True
    return False
