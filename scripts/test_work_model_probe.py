"""Qualify probe acceptance and telemetry boundaries without inference."""
import json
import unittest
import urllib.error
from unittest.mock import patch

import probe_work_models as probe


class ProbeChecks(unittest.TestCase):
    def test_positive_and_negative_oracle_controls(self):
        probe.qualify_oracles()
        answer=dict(probe.CASES['review']['answer'],actual=False)
        self.assertEqual(probe.score('review',{'content':json.dumps(answer)},'stop'),'incorrect_artifact')
        self.assertEqual(probe.score('review',{'content':'```json\n{}\n```'},'stop'),'invalid_artifact')

    def test_cloud_credentials_proxy_paths_are_rejected(self):
        for url in ['https://api.example.com/v1','http://127.0.0.1.evil/v1',
                    'http://user:password@127.0.0.1:8080/v1',
                    'http://127.0.0.1:8080/v1?secret=x','http://127.0.0.1:8080/other']:
            with self.assertRaises(ValueError):probe.endpoint({'url':url})
        self.assertEqual(probe.endpoint({'url':'http://127.0.0.1:8080/v1'}),'http://127.0.0.1:8080/v1/chat/completions')

    def test_http_failure_does_not_expose_response_body_or_credentials(self):
        route={'url':'http://127.0.0.1:8080/v1','model':'fixture','context':131072}
        error=urllib.error.HTTPError(route['url'],503,'secret diagnostic',{},None)
        with patch.object(probe.urllib.request.OpenerDirector,'open',side_effect=error):
            row=probe.attempt('local',route,'triage',1,128,{})
        self.assertEqual(row['outcome'],'provider_error')
        self.assertEqual(row['http_status'],503)
        self.assertNotIn('secret',json.dumps(row))


if __name__ == '__main__':unittest.main()
