import unittest

from validate_app_store_builds import der_signature_to_raw, valid_build_number


class AppStoreBuildValidationTest(unittest.TestCase):
    def test_accepts_one_to_three_numeric_components(self):
        self.assertTrue(valid_build_number("1"))
        self.assertTrue(valid_build_number("35.1"))
        self.assertTrue(valid_build_number("1.0.1"))

    def test_rejects_invalid_build_numbers(self):
        for value in ["", "0", "1.2.3.4", "1.beta", "-1"]:
            self.assertFalse(valid_build_number(value), value)

    def test_converts_der_ecdsa_signature_to_jwt_width(self):
        raw = der_signature_to_raw(bytes.fromhex("3006020101020102"))
        self.assertEqual(64, len(raw))
        self.assertEqual(1, raw[31])
        self.assertEqual(2, raw[63])


if __name__ == "__main__":
    unittest.main()
