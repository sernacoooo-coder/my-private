import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import app


class AtlasPersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        root = Path(self.temp_dir.name)
        app.DATA_DIR = root
        app.INDEX_PATH = root / "atlas.index"
        app.METADATA_PATH = root / "atlas.json"
        app.EVENTS_PATH = root / "events.jsonl"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_coordinates_require_real_pair(self):
        self.assertEqual(app.parse_coordinates("street__-6.2088_106.8456.jpg"), (-6.2088, 106.8456))
        self.assertIsNone(app.parse_coordinates("street_without_location.jpg"))

    def test_multiview_descriptor_handles_tiny_image(self):
        vector = app.visual_vector(Image.new("RGB", (1, 1), (30, 120, 220)))
        self.assertEqual(vector.shape, (190,))
        self.assertTrue(np.isfinite(vector).all())
        self.assertAlmostEqual(float(np.linalg.norm(vector)), 1.0, places=5)
        self.assertEqual(len(app._views(Image.new("RGB", (8, 8), (10, 20, 30)))), 9)

    def test_confidence_is_bounded(self):
        first = app.Sample("a__0_0.jpg", 0.0, 0.0, [1.0, 0.0])
        second = app.Sample("b__1_1.jpg", 1.0, 1.0, [0.0, 1.0])
        score = app.confidence_score([(first, 0.01), (second, 0.8)], 2.0)
        self.assertGreaterEqual(score, 0.0)
        self.assertLessEqual(score, 100.0)

    def test_append_deduplicates_and_survives_reload(self):
        first = app.Sample("a__0_0.jpg", 0.0, 0.0, [1.0, 0.0])
        second = app.Sample("b__1_1.jpg", 1.0, 1.0, [0.0, 1.0])
        index, samples, added = app.append_atlas([first, second])
        self.assertEqual(added, 2)
        self.assertEqual(index.ntotal, 2)

        duplicate = app.Sample("a__0_0.jpg", 0.0, 0.0, [1.0, 0.0])
        third = app.Sample("c__2_2.jpg", 2.0, 2.0, [0.7, 0.7])
        index, samples, added = app.append_atlas([duplicate, third])
        self.assertEqual(added, 1)
        self.assertEqual(len(samples), 3)
        self.assertEqual(index.ntotal, 3)

        reloaded_index, reloaded_samples = app.load_atlas()
        self.assertEqual(reloaded_index.ntotal, 3)
        self.assertEqual([sample.name for sample in reloaded_samples], ["a__0_0.jpg", "b__1_1.jpg", "c__2_2.jpg"])
        prediction = app.predict(np.asarray([1.0, 0.0], dtype=np.float32), reloaded_samples, reloaded_index, neighbours=1)
        self.assertAlmostEqual(prediction[0], 0.0, places=3)
        self.assertAlmostEqual(prediction[1], 0.0, places=3)

        app.INDEX_PATH.write_bytes(b"broken-index")
        recovered_index, recovered_samples = app.load_atlas()
        self.assertEqual(recovered_index.ntotal, 3)
        self.assertEqual(len(recovered_samples), 3)


if __name__ == "__main__":
    unittest.main()