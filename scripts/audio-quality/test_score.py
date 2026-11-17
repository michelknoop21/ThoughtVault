import unittest
from score import score, word_errors


class ScoreTests(unittest.TestCase):
    def data(self):
        return {"same_model_and_settings": True, "clips": [
            dict(kind="clean", reference="Alex komt maandag om tien", original="Alex komt maandag om tien", candidate="Alex komt maandag om tien", reference_reviewed=True, original_fact_errors=0, candidate_fact_errors=0),
            dict(kind="problem", reference="Alex komt maandag om tien", original="komt maandag om tien", candidate="Alex komt maandag om tien", reference_reviewed=True, original_fact_errors=1, candidate_fact_errors=0)]}

    def test_edits(self):
        self.assertEqual(word_errors("a b c", "a x c d"), (2, 3))
        self.assertEqual(word_errors("Alex, maandag!", "alex maandag"), (0, 2))

    def test_gate(self):
        self.assertTrue(score(self.data())["passes"])
        for key in ("reference_reviewed", "candidate_fact_errors", "candidate"):
            data = self.data()
            data["clips"][0][key] = {"reference_reviewed": False, "candidate_fact_errors": 1, "candidate": "Alex komt dinsdag om tien"}[key]
            self.assertFalse(score(data)["passes"])
        data = self.data()
        data["same_model_and_settings"] = False
        self.assertFalse(score(data)["passes"])

    def test_tie_keeps_original(self):
        data = self.data()
        data["clips"][1]["candidate"] = data["clips"][1]["original"]
        self.assertFalse(score(data)["passes"])

    def test_exact_thresholds(self):
        data = self.data()
        for clip in data["clips"]:
            clip["reference"] = " ".join(["word"] * 100)
            clip["original"] = clip["reference"]
            clip["candidate"] = clip["reference"]
        data["clips"][1]["original"] = " ".join(["word"] * 80)
        data["clips"][1]["candidate"] = " ".join(["word"] * 81)
        data["clips"][0]["candidate"] += " extra"
        self.assertTrue(score(data)["passes"])
        data["clips"][0]["candidate"] += " extra"
        self.assertFalse(score(data)["passes"])

    def test_empty_reference_rejected(self):
        with self.assertRaises(ValueError):
            word_errors("", "hallucination")


if __name__ == "__main__":
    unittest.main()
