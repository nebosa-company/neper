"""(C171) The AI app's model providers on the test boot's HTTPS server: the OpenAI-shaped local model (neper.test) and
the three hosted providers' own shapes, with each provider's own status codes and error bodies.

  api.openai.com / neper.test            POST /v1/chat/completions      Authorization: Bearer <key>
  api.anthropic.com                      POST /v1/messages              x-api-key: <key>
  generativelanguage.googleapis.com      POST /v1beta/models/<m>:streamGenerateContent?alt=sse&key=<key>
  each                                   GET  the model list (the app's cheap key check)

The key chooses the answer: `bad` is refused (401; Google's 400 API_KEY_INVALID) at the key check and at the chat,
`limit` passes the key check and is rate limited at the chat (429), `busy` is overloaded at the chat (Anthropic 529,
the others 503), `gone` answers 404 at the chat; any other key streams the echo of the last message. The echo names
what arrived: the message count, the text (a quoted text file included), and for a picture its kind and size read from
the PNG header; a request that offers tools and whose last message mentions `battery` is answered with a tool call, and
a request whose last message is a tool result is answered with a sentence that quotes it.
"""
import base64
import json
import struct
import time
import urllib.parse

HOSTS = {
    'api.anthropic.com': 'anthropic',
    'api.openai.com': 'openai',
    'generativelanguage.googleapis.com': 'google',
    'neper.test': 'openai',
}


def _key(handler, provider, query):
    if provider == 'anthropic':
        return handler.headers.get('x-api-key') or ''
    if provider == 'google':
        return (query.get('key') or [''])[0]
    auth = handler.headers.get('Authorization') or ''
    return auth[len('Bearer '):] if auth.startswith('Bearer ') else ''


def _error(handler, provider, status, kind, message):
    if provider == 'anthropic':
        body = {'type': 'error', 'error': {'type': kind, 'message': message}}
    elif provider == 'google':
        body = {'error': {'code': status, 'message': message, 'status': kind}}
    else:
        body = {'error': {'message': message, 'type': kind}}
    handler.reply(status, json.dumps(body).encode('utf-8'), 'application/json')


def _refuse(handler, provider, key, chat):
    """The refusals a key brings: True when one was sent."""
    if key == 'bad':
        if provider == 'anthropic':
            _error(handler, provider, 401, 'authentication_error', 'invalid x-api-key')
        elif provider == 'google':
            _error(handler, provider, 400, 'INVALID_ARGUMENT', 'API key not valid. Please pass a valid API key.')
        else:
            _error(handler, provider, 401, 'invalid_request_error', 'bad key')
        return True
    if not chat:
        return False
    if key == 'limit':
        if provider == 'anthropic':
            _error(handler, provider, 429, 'rate_limit_error', 'Number of request tokens has exceeded your rate limit')
        elif provider == 'google':
            _error(handler, provider, 429, 'RESOURCE_EXHAUSTED', 'Resource has been exhausted (e.g. check quota).')
        else:
            _error(handler, provider, 429, 'requests', 'rate limited')
        return True
    if key == 'busy':
        if provider == 'anthropic':
            _error(handler, provider, 529, 'overloaded_error', 'Overloaded')
        elif provider == 'google':
            _error(handler, provider, 503, 'UNAVAILABLE', 'The model is overloaded. Please try again later.')
        else:
            _error(handler, provider, 503, 'server_error', 'The server is overloaded or not ready yet.')
        return True
    if key == 'gone':
        _error(handler, provider, 404, 'not_found_error', 'The model does not exist')
        return True
    return False


def get(handler, host, path):
    """The model lists (the key check). True when the request was answered here."""
    provider = HOSTS.get(host)
    url = urllib.parse.urlparse(path)
    if provider is None:
        return False
    if url.path not in ('/v1/models', '/v1beta/models'):
        return False
    key = _key(handler, provider, urllib.parse.parse_qs(url.query))
    if _refuse(handler, provider, key, False):
        return True
    handler.reply(200, b'{"object":"list","data":[{"id":"llama-7b"}]}', 'application/json')
    return True


def _png_size(data):
    try:
        raw = base64.b64decode(data)
    except Exception:
        return None
    if raw[:8] != b'\x89PNG\r\n\x1a\n' or raw[12:16] != b'IHDR':
        return None
    w, h = struct.unpack('>II', raw[16:24])
    return w, h


def _parts(provider, message):
    """The text and the pictures of one message: (text, [(w, h)])."""
    text, pictures = [], []
    if provider == 'google':
        for part in message.get('parts', []):
            if 'text' in part:
                text.append(part['text'])
            if 'inlineData' in part:
                size = _png_size(part['inlineData'].get('data', ''))
                if size:
                    pictures.append(size)
        return '\n'.join(text), pictures
    content = message.get('content')
    if isinstance(content, str):
        return content, pictures
    for part in content or []:
        kind = part.get('type')
        if kind == 'text':
            text.append(part.get('text', ''))
        elif kind == 'image_url':
            url = part.get('image_url', {}).get('url', '')
            if url.startswith('data:image/png;base64,'):
                size = _png_size(url.split(',', 1)[1])
                if size:
                    pictures.append(size)
        elif kind == 'image':
            size = _png_size(part.get('source', {}).get('data', ''))
            if size:
                pictures.append(size)
    return '\n'.join(text), pictures


def _chunks(handler, pieces, wrap, tail=()):
    """Send `pieces` as a chunked text/event-stream a moment apart: each is wrapped into an event by `wrap`."""
    handler.send_response(200)
    handler.send_header('Content-Type', 'text/event-stream')
    handler.send_header('Transfer-Encoding', 'chunked')
    handler.send_header('Connection', 'close')
    handler.end_headers()

    def chunk(data):
        handler.wfile.write(('%x\r\n' % len(data)).encode() + data + b'\r\n')
        handler.wfile.flush()
    for piece in pieces:
        time.sleep(0.7)
        chunk(wrap(piece))
    for data in tail:
        chunk(data)
    handler.wfile.write(b'0\r\n\r\n')
    handler.wfile.flush()


def _split(text):
    words = text.split(' ')
    step = max(1, len(words) // 4)
    return [' '.join(words[i:i + step]) + ('' if i + step >= len(words) else ' ') for i in range(0, len(words), step)]


def _data(obj):
    return b'data: ' + json.dumps(obj).encode() + b'\n\n'


def post(handler, host, path, raw):
    """The chat endpoints. True when the request was answered here."""
    provider = HOSTS.get(host)
    url = urllib.parse.urlparse(path)
    if provider is None:
        return False
    chat = (provider == 'openai' and url.path == '/v1/chat/completions') or \
           (provider == 'anthropic' and url.path == '/v1/messages') or \
           (provider == 'google' and url.path.startswith('/v1beta/models/') and ':streamGenerateContent' in url.path)
    if not chat:
        return False
    key = _key(handler, provider, urllib.parse.parse_qs(url.query))
    if _refuse(handler, provider, key, True):
        return True
    request = json.loads(raw.decode('utf-8'))
    messages = request.get('contents' if provider == 'google' else 'messages', [])
    last_user, pictures = '', []
    for m in messages:
        if m.get('role') == 'user':
            last_user, pictures = _parts(provider, m)
    text = 'Echo from the neper test model (%d messages): %s' % (len(messages), last_user)
    for w, h in pictures:
        text += ' [picture png %dx%d]' % (w, h)
    # The tool round (OpenAI shape): a call for the battery, then a sentence quoting the result.
    if provider == 'openai' and request.get('tools'):
        last = messages[-1] if messages else {}
        if last.get('role') == 'tool':
            text = 'The tool said: %s' % last.get('content', '')
        elif 'battery' in last_user.lower():
            call = {'index': 0, 'id': 'call_7', 'type': 'function', 'function': {'name': 'battery', 'arguments': ''}}
            pieces = [
                {'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': None, 'tool_calls': [call]}}]},
                {'choices': [{'index': 0, 'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': '{}'}}]}}]},
                {'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}]},
            ]
            _chunks(handler, pieces, _data, tail=(b'data: [DONE]\n\n',))
            return True
    if provider == 'anthropic':
        def wrap(piece):
            return b'event: content_block_delta\n' + _data({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': piece}})
        _chunks(handler, _split(text), wrap, tail=(b'event: message_stop\n' + _data({'type': 'message_stop'}),))
    elif provider == 'google':
        def wrap(piece):
            return _data({'candidates': [{'content': {'parts': [{'text': piece}], 'role': 'model'}}]})
        _chunks(handler, _split(text), wrap)
    else:
        if request.get('stream'):
            _chunks(handler, _split(text), lambda p: _data({'choices': [{'index': 0, 'delta': {'content': p}}]}),
                    tail=(b': keep-alive\n\n', b'data: [DONE]\n\n'))
            return True
        answer = {'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': text}, 'finish_reason': 'stop'}]}
        handler.reply(200, json.dumps(answer).encode('utf-8'), 'application/json')
    return True
