"""Record the API replies the Stocks fixture is served (C118, D2251).

  python record.py

Coinbase Exchange's daily candles for BTC-USD and ETH-USD (public, no key) and Twelve Data's time_series
for AAPL with its public demo key, written next to this script as JSON. The fixture's host_services.py
serves them; the suites never touch the internet, so run this only to refresh the recordings. Candles are
cut to the 70 newest (the app reads 60) to keep the files small.
"""
import json
import pathlib
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'NeperOS-fixture/1.0'})
    with urllib.request.urlopen(request, timeout=30) as reply:
        return json.loads(reply.read())


for product in ('BTC-USD', 'ETH-USD'):
    candles = fetch('https://api.exchange.coinbase.com/products/%s/candles?granularity=86400' % product)[:70]
    (HERE / ('candles-%s.json' % product)).write_text(json.dumps(candles, separators=(',', ':')), encoding='utf-8')
    print(product, len(candles), 'candles, newest', candles[0][0])
series = fetch('https://api.twelvedata.com/time_series?symbol=AAPL&interval=1day&outputsize=60&apikey=demo')
assert series.get('status') == 'ok', series
(HERE / 'time_series-AAPL.json').write_text(json.dumps(series, separators=(',', ':')), encoding='utf-8')
print('AAPL', len(series['values']), 'values, newest', series['values'][0]['datetime'])

# Alpha Vantage's TIME_SERIES_DAILY for IBM with its public demo key (the demo key serves IBM only), and Twelve
# Data's symbol_search for "app" (public, no key). The Polygon reply is not recorded: Polygon has no public
# key, so the file is the AAPL closes above in the shape its docs give for /v2/aggs (results[].c, newest
# first, status OK); only the shape is claimed, not a recording.
daily = fetch('https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=IBM&apikey=demo')
assert 'Time Series (Daily)' in daily, daily
(HERE / 'daily-IBM.json').write_text(json.dumps(daily, separators=(',', ':')), encoding='utf-8')
print('IBM', len(daily['Time Series (Daily)']), 'days, newest', next(iter(daily['Time Series (Daily)'])))
found = fetch('https://api.twelvedata.com/symbol_search?symbol=app&outputsize=30')
assert found.get('status') == 'ok', found
(HERE / 'symbol_search-app.json').write_text(json.dumps(found, separators=(',', ':')), encoding='utf-8')
print('search app', len(found['data']), 'matches')
results = [{'v': 1, 'vw': float(v['close']), 'o': float(v['open']), 'c': float(v['close']), 'h': float(v['high']),
            'l': float(v['low']), 't': 1700000000000 - 86400000 * i, 'n': 1} for i, v in enumerate(series['values'])]
(HERE / 'aggs-AAPL.json').write_text(json.dumps({'ticker': 'AAPL', 'queryCount': len(results), 'resultsCount': len(results),
    'adjusted': True, 'results': results, 'status': 'OK', 'request_id': 'fixture', 'count': len(results)}, separators=(',', ':')), encoding='utf-8')
print('aggs AAPL', len(results), 'results (shape from docs)')

# Weather (C119): Open-Meteo's forecast for three places (keyless) and its geocoding search for "bergen". The
# forecast URL is the one weather.e builds; the coordinates are the app's places in hundredths of a degree.
FORECAST = ('https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,relative_humidity_2m,'
            'apparent_temperature,weather_code,wind_speed_10m,uv_index,is_day&hourly=temperature_2m,weather_code,'
            'precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,'
            'precipitation_probability_max,uv_index_max&timezone=auto&forecast_days=7&forecast_hours=24')
for name, lat, lon in (('seattle', '47.61', '-122.33'), ('oslo', '59.91', '10.75'), ('bergen', '60.39', '5.32')):
    forecast = fetch(FORECAST % (lat, lon))
    assert 'current' in forecast, forecast
    (HERE / ('forecast-%s.json' % name)).write_text(json.dumps(forecast, separators=(',', ':')), encoding='utf-8')
    print(name, 'forecast, now', forecast['current']['time'])
places = fetch('https://geocoding-api.open-meteo.com/v1/search?name=bergen&count=5&language=en&format=json')
assert places.get('results'), places
(HERE / 'geocode-bergen.json').write_text(json.dumps(places, separators=(',', ':')), encoding='utf-8')
print('geocode bergen', [(r['name'], round(r['latitude'], 2), round(r['longitude'], 2)) for r in places['results']])
