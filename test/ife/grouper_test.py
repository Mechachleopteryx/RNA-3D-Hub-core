import collections as coll

from test import StageTest

from pymotifs.ife.helpers import IfeChain
from pymotifs.ife.grouper import Grouper as IfeGrouper


class ShouldJoinTest(StageTest):
    loader_class = IfeGrouper

    def setUp(self):
        super(ShouldJoinTest, self).setUp()
        self.ife1 = IfeChain(pdb='1S72', chain='A', internal=0, length=10)
        self.ife2 = IfeChain(pdb='1S72', chain='B', internal=0, length=10)
        self.ife3 = IfeChain(pdb='1S72', chain='C', internal=10, length=10)
        self.ife4 = IfeChain(pdb='1S72', chain='D', internal=10, length=10)

    def test_will_join_if_both_unstructured(self):
        self.assertTrue(self.loader.should_join(self.ife1, self.ife2, 1))

    def test_will_join_if_both_unstructured_with_no_interactions(self):
        self.assertFalse(self.loader.should_join(self.ife1, self.ife2, 0))

    def test_will_not_join_to_itself(self):
        self.assertFalse(self.loader.should_join(self.ife1, self.ife1, 10))

    def test_will_not_join_structured_no_interactions(self):
        self.assertFalse(self.loader.should_join(self.ife3, self.ife4, 0))

    def test_will_join_structured_with_enough_external_interactions(self):
        self.assertTrue(self.loader.should_join(self.ife3, self.ife4, 10))


class PartitingInteractionsTest(StageTest):
    loader_class = IfeGrouper

    def setUp(self):
        super(PartitingInteractionsTest, self).setUp()
        inters = {
            'A': {'A': 0, 'B': 3, 'C': 2, 'D': 0},
            'B': {'A': 3, 'B': 0, 'C': 0, 'D': 4},
            'C': {'A': 2, 'B': 0, 'C': 0, 'D': 0},
            'D': {'A': 0, 'B': 4, 'C': 0, 'D': 0}
        }

        ifes = [
            IfeChain(chain='A', internal=10),
            IfeChain(chain='B', internal=0),
            IfeChain(chain='C', internal=10),
            IfeChain(chain='D', internal=0),
        ]
        self.same, self.rest = self.loader.parition_interactions(ifes, inters)

    def test_will_extract_same_structured_pairs(self):
        ans = {
            'A': {'A': 0, 'B': 0, 'C': 2, 'D': 0},
            'B': {'A': 0, 'B': 0, 'C': 0, 'D': 4},
            'C': {'A': 2, 'B': 0, 'C': 0, 'D': 0},
            'D': {'A': 0, 'B': 4, 'C': 0, 'D': 0}
        }
        self.assertEquals(ans, self.same)

    def test_will_extract_differently_structured_pairs(self):
        ans = {
            'A': {'A': 0, 'B': 3, 'C': 0, 'D': 0},
            'B': {'A': 3, 'B': 0, 'C': 0, 'D': 0},
            'C': {'A': 0, 'B': 0, 'C': 0, 'D': 0},
            'D': {'A': 0, 'B': 0, 'C': 0, 'D': 0}
        }
        self.assertEquals(ans, self.rest)


class GroupingTest(StageTest):
    loader_class = IfeGrouper

    def grouping(self, chains, interactions):
        groups = self.loader.group(chains, interactions)
        grouping = coll.defaultdict(list)
        for group in groups:
            for chain in group.chains():
                grouping[chain.id].append(group.id)
        return dict(grouping)

    def test_will_put_non_interacting_chains_seperately(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=10),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=10)]
        ans = {'1S72|1|A': ['1S72|1|A'], '1S72|1|B': ['1S72|1|B']}
        self.assertEquals(ans, self.grouping(chains, {}))

    def test_puts_non_interactions_unstructured_chains_seperately(self):
        chains = [IfeChain(internal=0, pdb='1S72', model=1, chain='A', length=10),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='B', length=10)]
        ans = {'1S72|1|A': ['1S72|1|A'], '1S72|1|B': ['1S72|1|B']}
        self.assertEquals(ans, self.grouping(chains, {}))

    def test_will_put_structured_but_interacting_chains_seperatly(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=50),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=50)]
        interactions = {'A': {'B': 3}, 'B': {'A': 3}}
        val = self.grouping(chains, interactions)
        ans = {'1S72|1|A': ['1S72|1|A'], '1S72|1|B': ['1S72|1|B']}
        self.assertEquals(ans, val)

    def test_will_join_structured_chains_if_enough_interactions(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=50),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=50)]
        interactions = {'A': {'B': 30}, 'B': {'A': 30}}
        val = self.grouping(chains, interactions)
        ans = {'1S72|1|A': ['1S72|1|A+1S72|1|B'], '1S72|1|B': ['1S72|1|A+1S72|1|B']}
        self.assertEquals(ans, val)

    def test_will_join_unstructured_chains_on_interactions(self):
        chains = [IfeChain(internal=0, pdb='1S72', model=1, chain='A', length=10),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='B', length=10)]
        interactions = {'A': {'B': 10}, 'B': {'A': 10}}
        val = self.grouping(chains, interactions)
        ans = {'1S72|1|A': ['1S72|1|A+1S72|1|B'], '1S72|1|B': ['1S72|1|A+1S72|1|B']}
        self.assertEquals(ans, val)

    def test_unstructured_single_chains_will_be_alone(self):
        chains = [IfeChain(internal=0, pdb='1S72', model=1, chain='A', length=10)]
        val = self.grouping(chains, {})
        self.assertEquals({'1S72|1|A': ['1S72|1|A']}, val)

    def test_structured_chains_joined_only_by_unstructured_arent_joined(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=50),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=50),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='C', length=10)]
        interactions = {
            'A': {'B': 1, 'C': 5},
            'B': {'A': 1, 'C': 5},
            'C': {'A': 5, 'B': 5}
        }
        assert self.grouping(chains, interactions) == {
            '1S72|1|A': ['1S72|1|A'],
            '1S72|1|B': ['1S72|1|B'],
            '1S72|1|C': ['1S72|1|A', '1S72|1|B']
        }

    def test_structured_chains_joined_only_by_unstructureds_arent_joined(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=50),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=50),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='C', length=10),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='D', length=10)]
        interactions = {
            'A': {'B': 1, 'C': 5},
            'B': {'A': 1, 'C': 5},
            'C': {'A': 5, 'B': 5, 'D': 10},
            'D': {'A': 0, 'B': 0, 'C': 10}
        }
        val = self.grouping(chains, interactions)
        ans = {
            '1S72|1|A': ['1S72|1|A'],
            '1S72|1|B': ['1S72|1|B'],
            '1S72|1|C': ['1S72|1|A', '1S72|1|B'],
            '1S72|1|D': ['1S72|1|A', '1S72|1|B'],
        }
        self.assertEquals(ans, val)

    def test_structured_chains_joined_with_unstructured_are_joined(self):
        chains = [IfeChain(internal=10, pdb='1S72', model=1, chain='A', length=50),
                  IfeChain(internal=10, pdb='1S72', model=1, chain='B', length=50),
                  IfeChain(internal=0, pdb='1S72', model=1, chain='C', length=10)]
        interactions = {
            'A': {'B': 30, 'C': 5},
            'B': {'A': 30, 'C': 5},
            'C': {'A': 5, 'B': 5}
        }
        ans = {
            '1S72|1|A': ['1S72|1|A+1S72|1|B'],
            '1S72|1|B': ['1S72|1|A+1S72|1|B'],
            '1S72|1|C': ['1S72|1|A+1S72|1|B'],
        }
        val = self.grouping(chains, interactions)
        self.assertEquals(ans, val)


class RealDataTest(StageTest):
    loader_class = IfeGrouper

    def grouping(self, pdb):
        groups = self.loader(pdb)
        grouping = coll.defaultdict(list)
        for group in groups:
            for chain in group.chains():
                grouping[chain.id].append(group.id)
        return dict(grouping)

    def test_1EKD_groups(self):
        assert self.grouping('1EKD') == {
            '1EKD|1|A': ['1EKD|1|A+1EKD|1|B'],
            '1EKD|1|B': ['1EKD|1|A+1EKD|1|B']
        }

    def test_1A34_groups(self):
        ans = {
            '1A34|1|B': ['1A34|1|B+1A34|1|C'],
            '1A34|1|C': ['1A34|1|B+1A34|1|C'],
        }
        self.assertEquals(ans, self.grouping('1A34'))

    def test_1ET4_groups(self):
        ans = {
            '1ET4|1|A': ['1ET4|1|A'],
            '1ET4|1|B': ['1ET4|1|B'],
            '1ET4|1|C': ['1ET4|1|C'],
            '1ET4|1|D': ['1ET4|1|D'],
            '1ET4|1|E': ['1ET4|1|E']
        }
        self.assertEquals(ans, self.grouping('1ET4'))

    def test_1FEU_groups(self):
        ans = {
            '1FEU|1|B': ['1FEU|1|C+1FEU|1|B'],
            '1FEU|1|C': ['1FEU|1|C+1FEU|1|B'],
            '1FEU|1|F': ['1FEU|1|F+1FEU|1|E'],
            '1FEU|1|E': ['1FEU|1|F+1FEU|1|E'],
        }
        self.assertEquals(ans, self.grouping('1FEU'))

    def test_1F5U_groups(self):
        ans = {
            '1F5U|1|A': ['1F5U|1|A'],
            '1F5U|1|B': ['1F5U|1|B']
        }
        self.assertEquals(ans, self.grouping('1F5U'))

    def test_bact_with_trna_4V42(self):
        ans = {
            '4V42|1|AA': ['4V42|1|AA'],             # Lone SSU
            '4V42|1|A1': ['4V42|1|AB', '4V42|1|AC'],  # mRNA with 2 tRNAs
            '4V42|1|AB': ['4V42|1|AB'],             # tRNA/mRNA
            '4V42|1|AC': ['4V42|1|AC'],             # tRNA/mRNA
            '4V42|1|AD': ['4V42|1|AD'],             # E-site tRNA
            '4V42|1|BA': ['4V42|1|BA'],             # Lone LSU
            '4V42|1|BB': ['4V42|1|BB'],             # Lone 5S
        }
        self.assertEquals(ans, self.grouping('4V42'))

    def test_bact_with_duplicates_4V4Q(self):
        ans = {
            '4V4Q|1|AA': ['4V4Q|1|AA'],  # Lone SSU
            '4V4Q|1|BA': ['4V4Q|1|BA'],  # Lone 5S
            '4V4Q|1|BB': ['4V4Q|1|BB'],  # Lone LSU
            '4V4Q|1|CA': ['4V4Q|1|CA'],  # Lone SSU
            '4V4Q|1|DA': ['4V4Q|1|DA'],  # Lone 5S
            '4V4Q|1|DB': ['4V4Q|1|DB'],  # Lone LSU
        }

        self.assertEquals(ans, self.grouping('4V4Q'))

    def test_euk_ribo_with_duplicates_4V88(self):
        ans = {
            '4V88|1|A2': ['4V88|1|A2'],          # SSU alone
            '4V88|1|A3': ['4V88|1|A3'],          # 5S alone
            '4V88|1|A1': ['4V88|1|A1+4V88|1|A4'],  # LSU/5.8S
            '4V88|1|A4': ['4V88|1|A1+4V88|1|A4'],  # LSU/5.8S
            '4V88|1|A5': ['4V88|1|A5+4V88|1|A8'],  # LSU/5.8S
            '4V88|1|A8': ['4V88|1|A5+4V88|1|A8'],  # LSU/5.8S
            '4V88|1|A6': ['4V88|1|A6'],          # SSU alone
            '4V88|1|A7': ['4V88|1|A7'],          # 5S alone
        }
        self.assertEquals(ans, self.grouping('4V88'))

    def test_many_ustructured_1YZ9(self):
        ans = {
            '1YZ9|1|C': ['1YZ9|1|C+1YZ9|1|D+1YZ9|1|E+1YZ9|1|F'],
            '1YZ9|1|D': ['1YZ9|1|C+1YZ9|1|D+1YZ9|1|E+1YZ9|1|F'],
            '1YZ9|1|E': ['1YZ9|1|C+1YZ9|1|D+1YZ9|1|E+1YZ9|1|F'],
            '1YZ9|1|F': ['1YZ9|1|C+1YZ9|1|D+1YZ9|1|E+1YZ9|1|F']
        }
        self.assertEquals(ans, self.grouping('1YZ9'))

    def test_handles_yeast_ribo_4V7R(self):
        ans = {
            '4V7R|1|A1': ['4V7R|1|A1'],           # SSU
            '4V7R|1|B3': ['4V7R|1|B1+4V7R|1|B3'],   # LSU/5.8S
            '4V7R|1|B1': ['4V7R|1|B1+4V7R|1|B3'],   # LSU/5.8S
            '4V7R|1|B2': ['4V7R|1|B2'],           # 5S
            '4V7R|1|C1': ['4V7R|1|C1'],           # SSU
            '4V7R|1|D3': ['4V7R|1|D1+4V7R|1|D3'],   # LSU/5.8S
            '4V7R|1|D1': ['4V7R|1|D1+4V7R|1|D3'],   # LSU/5.8S
            '4V7R|1|D2': ['4V7R|1|D2']            # 5S
        }
        self.assertEquals(ans, self.grouping('4V7R'))
