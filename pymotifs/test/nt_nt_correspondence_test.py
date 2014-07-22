import unittest

from models import Session

import nt_nt_correspondence as ntnt


class NtNtCorrespondencesTest(unittest.TestCase):
    def setUp(self):
        self.corr = ntnt.Loader(Session)

    def test_can_get_longest_chain(self):
        val = self.corr.longest_chain('2AW7')
        self.assertEquals('A', val)

    def test_can_check_if_has_correspondence(self):
        self.assertFalse(self.corr.has_correspondence('1J5E', 'bob'))

    def test_can_get_sequences_to_correlate(self):
        pass

    def test_can_get_ids_to_correlate(self):
        pass

    def test_can_find_reference(self):
        val = self.corr.reference('1J5E')
        self.assertEquals(set(['2VQE', '1FJG']), val)


class ExistingDataTest(unittest.TestCase):
    def test_knows_if_has_correspondence(self):
        pass
