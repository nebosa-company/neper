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
