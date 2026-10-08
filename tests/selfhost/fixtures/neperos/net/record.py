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
