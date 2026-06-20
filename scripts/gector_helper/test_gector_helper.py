import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gector_helper import HelperConfig, correct_text, issue_summary


class GECToRHelperTests(unittest.TestCase):
    def test_echo_backend_returns_contract(self):
        config = HelperConfig(
            host="127.0.0.1",
            port=8765,
            backend="echo",
            gector_repo=None,
            python="python",
            model_paths=[],
            vocab_path=None,
            timeout=1,
            min_error_probability=None,
            additional_confidence=None,
            special_tokens_fix=0,
        )

        result = correct_text("He go to school yesterday.", config)

        self.assertEqual(result["originalText"], "He go to school yesterday.")
        self.assertEqual(result["correctedText"], "He go to school yesterday.")
        self.assertEqual(result["issues"], [])
        json.dumps(result)

    def test_issue_summary_reports_changed_fragments(self):
        issues = issue_summary("He go to school yesterday.", "He went to school yesterday.")

        self.assertEqual(issues, [{
            "original": "go",
            "replacement": "went",
            "message": "GECToR grammar improvement",
        }])


if __name__ == "__main__":
    unittest.main()
