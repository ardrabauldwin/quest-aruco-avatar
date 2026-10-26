import subprocess
import unittest
from unittest.mock import patch
from usb_bridge_recovery import quest_usb_present, should_recover, speech_bridge_healthy, repair_speech_bridge


class RecoveryTests(unittest.TestCase):
    def test_path_probe_requires_a_real_ready_response(self):
        from unittest.mock import Mock
        adb = Mock(return_value=subprocess.CompletedProcess([], 0, 'HTTP/1.0 200 OK\r\n\r\n{"ready": true}', ''))
        self.assertTrue(speech_bridge_healthy(adb, 'quest'))
        adb.return_value = subprocess.CompletedProcess([], 0, '', '')
        self.assertFalse(speech_bridge_healthy(adb, 'quest'))
        adb.return_value = subprocess.CompletedProcess([], 0, 'HTTP/1.0 503 Unavailable', '')
        self.assertFalse(speech_bridge_healthy(adb, 'quest'))

    def test_path_repair_recreates_only_the_speech_forward(self):
        from unittest.mock import Mock, call
        adb = Mock(return_value=subprocess.CompletedProcess([], 0, '', ''))
        self.assertTrue(repair_speech_bridge(adb, 'quest'))
        self.assertEqual(adb.call_args_list, [
            call(['-s', 'quest', 'reverse', '--remove', 'tcp:8767']),
            call(['-s', 'quest', 'reverse', 'tcp:8767', 'tcp:8767'])])

    def test_attached_quest_recovers_even_after_a_previous_failed_reset(self):
        self.assertTrue(should_recover("List of devices attached\n", 4, 25, True))
        self.assertTrue(should_recover("List of devices attached\n", 12, 80, True))

    def test_recovery_is_bounded_and_requires_attached_hardware(self):
        self.assertFalse(should_recover("", 1, 80, True))
        self.assertFalse(should_recover("", 5, 10, True))
        self.assertFalse(should_recover("", 5, 80, False))

    def test_other_connected_devices_and_authorization_prompts_are_protected(self):
        self.assertFalse(should_recover("phone\tdevice\n", 5, 80, True))
        self.assertFalse(should_recover("quest\tunauthorized\n", 5, 80, True))

    @patch("usb_bridge_recovery.subprocess.run")
    def test_windows_presence_is_specific_to_meta(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, "USB\\VID_2833&PID_5013", "")
        self.assertTrue(quest_usb_present())
        run.return_value = subprocess.CompletedProcess([], 0, "USB\\VID_1234", "")
        self.assertFalse(quest_usb_present())
        run.side_effect = subprocess.TimeoutExpired([], 15)
        self.assertFalse(quest_usb_present())


if __name__ == "__main__":
    unittest.main()
