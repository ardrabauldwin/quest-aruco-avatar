"""Offline regression checks; no real credentials or device access."""
import copy
import unittest

from configure_quest import build_config, ProvisionError
from api_common import BASE_URL


class SpeechOnlyConfigTests(unittest.TestCase):
    def test_switch_preserves_dialogue_and_device_settings(self):
        original = {"api": {"local_asr_url": "http://127.0.0.1:8767/inference",
                            "local_ai_url": "http://127.0.0.1:8768",
                            "llm_model": "existing-dialogue", "tts_model": "existing-voice",
                            "timeout_s": 1.5},
                    "ccbm": {"endpoint": "unchanged"}, "placement": {"offset": [0, 0.1, 0]}}
        snapshot = copy.deepcopy(original)
        configured = build_config(original, offline=False, key="test-placeholder", speech_only=True)
        self.assertEqual(original, snapshot)
        self.assertEqual(configured["ccbm"], snapshot["ccbm"])
        self.assertEqual(configured["placement"], snapshot["placement"])
        for field in ["local_ai_url", "llm_model", "tts_model", "timeout_s"]:
            self.assertEqual(configured["api"][field], snapshot["api"][field])
        self.assertEqual(configured["api"]["base_url"], BASE_URL)
        self.assertEqual(configured["api"]["asr_model"], "large-v3")
        self.assertEqual(configured["api"]["local_asr_url"], "")
        self.assertEqual(configured["api"]["asr_timeout_s"], 0)

    def test_finite_deadline_is_opt_in(self):
        configured = build_config({}, offline=False, key="test-placeholder", speech_only=True, asr_timeout_s=45)
        self.assertEqual(configured["api"]["asr_timeout_s"], 45)
        for invalid in [-1, float("nan"), float("inf")]:
            with self.assertRaises(ProvisionError):
                build_config({}, offline=False, key="test-placeholder", asr_timeout_s=invalid)

    def test_requires_credential(self):
        with self.assertRaises(ProvisionError):
            build_config({}, offline=False, speech_only=True)

    def test_conflicting_modes_refused(self):
        with self.assertRaises(ProvisionError):
            build_config({}, offline=True, speech_only=True)


if __name__ == "__main__":
    unittest.main()
