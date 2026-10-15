import unittest
from unittest.mock import patch
import subprocess
from pathlib import Path
from server import infer, parse_posterior


class ProtocolTest(unittest.TestCase):
    def test_posterior(self):
        result = parse_posterior('Time "INITIALIZE" "(begin_check)"\n0 1 0\n1 0 1\n', 1)
        self.assertEqual(result['action'], 'begin_check')
        self.assertEqual(result['probability'], 1)

    def test_special_state_not_removed(self):
        result = parse_posterior('Time "BLOCKED" "(begin_check)"\n1 0.95 0.05\n', 1)
        self.assertEqual(result['action'], 'BLOCKED')

    def test_empty_native_column(self):
        result = parse_posterior('Time "(begin_check)" ""\n1 1 0', 1)
        self.assertEqual(result['action'], 'begin_check')

    def test_partial_missing_invalid(self):
        for output in ['', 'Time "(begin_check)"\n0 1\n', 'Time "(begin_check)"\n1 nan\n']:
            with self.assertRaises(ValueError):
                parse_posterior(output, 1)

    def test_ventilation_aliases(self):
        result = parse_posterior('Time "(ventilation_first)" "(ventilation_second)"\n1 0.4 0.6', 1)
        self.assertEqual(result['action'], 'ventilation')

    def test_no_shell_and_real_filter_required(self):
        with patch('server.subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, 'Time "(begin_check)"\n1 1\n', '')
            self.assertEqual(infer(['begin_check'], Path('/filter'), Path('/states'))['engine'], 'ccbm')
            self.assertEqual(run.call_args.kwargs['input'], 'begin_check\n')
            self.assertEqual(run.call_args.kwargs['timeout'], 8)
        with self.assertRaises(ValueError):
            infer(['arbitrary text'], Path('/filter'), Path('/states'))


if __name__ == '__main__':
    unittest.main()
