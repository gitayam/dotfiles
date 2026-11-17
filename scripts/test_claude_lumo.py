"""Regression tests for the local Claude/Lumo transport; no network needed."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import httpx

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('cc_lumo', str(ROOT / 'shared/bin/cc-lumo'))
spec = importlib.util.spec_from_loader(loader.name, loader)
lumo = importlib.util.module_from_spec(spec)
loader.exec_module(lumo)


class Response:
    status_code = 200
    headers = {'content-type': 'application/json'}
    body = b''

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def read(self):
        return self.body

    def iter_raw(self):
        yield self.body


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.server = lumo.make_bridge('upstream-secret', 'bridge-secret')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}/v1/chat/completions'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, body, key='bridge-secret'):
        req = Request(self.url, data=json.dumps(body).encode(),
                      headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        return urlopen(req, timeout=4)

    def fake_client(self, response):
        captured = {}

        class Client:
            def __init__(self, **_):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *_):
                pass

            def stream(self, method, url, **kwargs):
                captured.update(method=method, url=url, **kwargs)
                return response

        return Client, captured

    def test_rejects_unauthorized_without_contacting_upstream(self):
        with patch.object(httpx, 'Client') as client:
            with self.assertRaises(HTTPError) as error:
                self.request({'model': 'lumo-lite'}, key='wrong')
            self.assertEqual(error.exception.code, 401)
            error.exception.close()
            client.assert_not_called()

    def test_large_request_is_forwarded_without_truncation(self):
        text = 'x' * 170_000
        response = Response()
        response.body = b'{"choices":[]}'
        client, captured = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.request({'model': 'lumo-lite', 'messages': [{'role': 'user', 'content': text}]}) as r:
                self.assertEqual(r.status, 200)
        self.assertEqual(json.loads(captured['content'])['messages'][0]['content'], text)

    def test_normalizes_double_encoded_chat_completion(self):
        obj = {'choices': [{'message': {'content': 'ok'}}]}
        response = Response()
        response.body = json.dumps(json.dumps(obj)).encode()
        client, captured = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.request({'model': 'lumo-lite'}) as r:
                self.assertEqual(json.load(r), obj)
        self.assertEqual(captured['url'], lumo.UPSTREAM + '/chat/completions')
        self.assertEqual(captured['headers']['Authorization'], 'Bearer upstream-secret')

    def test_stream_is_forwarded_without_reencoding(self):
        response = Response()
        response.headers = {'content-type': 'text/event-stream'}
        response.body = b'data: {"choices": []}\n\ndata: [DONE]\n\n'
        client, _ = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.request({'model': 'lumo-lite', 'stream': True}) as r:
                self.assertEqual(r.read(), response.body)

    def test_rejects_non_stream_response_when_stream_requested(self):
        response = Response()
        client, _ = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.assertRaises(HTTPError) as error:
                self.request({'model': 'lumo-lite', 'stream': True})
            self.assertEqual(error.exception.code, 502)
            error.exception.close()

    def test_upstream_errors_do_not_echo_response(self):
        response = Response()
        response.status_code = 401
        response.body = b'secret echo'
        client, _ = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.assertRaises(HTTPError) as error:
                self.request({'model': 'lumo-lite'})
            self.assertNotIn(b'secret', error.exception.read())
            error.exception.close()

    def test_buffered_file_upstream_failure_is_nonretryable_and_explained(self):
        response = Response()
        response.status_code = 500
        response.body = b"AttributeError: '_io.BufferedRandom' object has no attribute 'getvalue'"
        client, _ = self.fake_client(response)
        with patch.object(httpx, 'Client', client):
            with self.assertRaises(HTTPError) as error:
                self.request({'model': 'lumo-lite'})
            self.assertEqual(error.exception.code, 400)
            self.assertIn(b'Upstream request too large', error.exception.read())
            error.exception.close()


class SelectionTests(unittest.TestCase):
    def test_default_tools_and_explicit_choice_are_preserved(self):
        self.assertEqual(lumo.claude_args(['-p', 'hello']), ['-p', 'hello'])
        self.assertEqual(lumo.claude_args(['--tools', 'default']), ['--tools', 'default'])
        self.assertEqual(lumo.claude_args(['--tools=Read']), ['--tools=Read'])
        self.assertEqual(lumo.claude_args(['--read-only', '-p', 'hello']), ['--tools', lumo.READ_ONLY_TOOLS, '-p', 'hello'])
        with self.assertRaises(RuntimeError):
            lumo.claude_args(['--read-only', '--tools', 'default'])
    def test_model_list_refuses_redirects(self):
        handler = lumo.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, '', {}, 'https://other.example/'))

    def test_missing_max_fails_closed_without_starting_claude(self):
        with patch.object(lumo, 'credential', return_value='key'), \
             patch.object(lumo, 'list_models', return_value=['lumo-lite']), \
             patch.object(lumo, 'run_claude') as launch, \
             patch.object(lumo.sys, 'argv', ['cc-lumo', '--check']), \
             patch.dict(lumo.os.environ, {'CLAUDE_LUMO_MODEL': 'lumo-max'}):
            with self.assertRaisesRegex(RuntimeError, 'No automatic fallback'):
                lumo.main()
            launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
