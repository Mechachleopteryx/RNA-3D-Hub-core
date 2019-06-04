"""Load the chain to chain discrepancies. This will 1) look at good
correspondences, 2) extract all the aligned chains, 3) compute the
geometric discrepancy between them, and 4) place the discrepanices
in the database.

This will only compare the first chain in each IFE.
"""


import functools as ft
import itertools as it
import numpy as np
import operator as op
import pickle

from collections import defaultdict

from sqlalchemy import and_
from sqlalchemy import or_
from sqlalchemy.orm import aliased
from sqlalchemy.sql import union_all

from fr3d.geometry.discrepancy import matrix_discrepancy

from pymotifs import core
import pymotifs.utils as ut
from pymotifs import models as mod
from pymotifs.utils import discrepancy as disc

from pymotifs.correspondence.loader import Loader as CorrespondenceLoader
from pymotifs.exp_seq.mapping import Loader as ExpSeqUnitMappingLoader
from pymotifs.ife.loader import Loader as IfeLoader
from pymotifs.units.centers import Loader as CenterLoader
from pymotifs.units.rotation import Loader as RotationLoader

from pymotifs.nr.groups.simplified import Grouper


def pick(preferences, key, iterable):
    """Pick the most preferred value from a list of possibilities.

    Parameters
    ----------
    preferences : list
        A list of possibilities to select from.
    key : str
        Key to define the attribute
    iterable : iterable
        The iterable to get the unique values from.

    Returns
    -------
    choice : obj
        A member of preferences if any exist, otherwise the alphabetically
        first choice from the iterable.
    """

    possible = set(getattr(result, key) for result in iterable)
    if not possible:
        raise core.InvalidState("Nothing to pick from")

    for pref in preferences:
        if pref in possible:
            return pref
    return sorted(possible)[0]


def label_center(table, number):
    """Select the center columns from the given table. This will alias the
    columns to ones that are unique

    Parameters
    ----------
    table : Table
        The table to select columns from.
    number : int
        The number to postfix

    Returns
    -------
    columns : list
        The list of columns to select.
    """

    return [
        getattr(table, 'unit_id').label('unit%s' % number),
        getattr(table, 'x').label('x%s' % number),
        getattr(table, 'y').label('y%s' % number),
        getattr(table, 'z').label('z%s' % number),
    ]


def label_rotation(table, number):
    """Select the tables

    Parameters
    ----------
    table : Table
        The table to select columns from
    number : int
        The number to postfix

    Returns
    -------
    columns : list
        The list of columns to select.
    """

    return [
        getattr(table, 'cell_0_0').label('cell_00_%s' % number),
        getattr(table, 'cell_0_1').label('cell_01_%s' % number),
        getattr(table, 'cell_0_2').label('cell_02_%s' % number),
        getattr(table, 'cell_1_0').label('cell_10_%s' % number),
        getattr(table, 'cell_1_1').label('cell_11_%s' % number),
        getattr(table, 'cell_1_2').label('cell_12_%s' % number),
        getattr(table, 'cell_2_0').label('cell_20_%s' % number),
        getattr(table, 'cell_2_1').label('cell_21_%s' % number),
        getattr(table, 'cell_2_2').label('cell_22_%s' % number),
    ]


def make_unique_list(input_list):
    unique_list = []
    for foo in input_list:
        if foo not in unique_list:
            unique_list.append(foo)
    return unique_list


class Loader(core.SimpleLoader):
    """A Loader to get all chain to chain similarity data. This will use the
    correspondences between ifes to compute the discrepancy between them.
    """

    """The tuple of chains can't be marked in the database."""
    mark = False

    """We allow for no data to be written when appropriate."""
    allow_no_data = True

    """The dependencies for this stage"""
    dependencies = set([CorrespondenceLoader, ExpSeqUnitMappingLoader,
                        IfeLoader, CenterLoader, RotationLoader])

    def known_unit_entries(self, table):
        """Create a set of (pdb, chain) tuples for all chains that have entries
        in the given table. This relies upon the table having a unit_id column
        that can be joined to unit_info.

        Parameters
        ----------
        table : Table
            The table to join against.

        Returns
        -------
        known : set
            A set of tuples of (pdb, chain).
        """
        with self.session() as session:
            info = mod.UnitInfo
            query = session.query(info.pdb_id,
                                  info.chain,
                                  ).\
                join(table, table.unit_id == info.unit_id).\
                distinct()
            return set((r.pdb_id, r.chain) for r in query)


    def is_member(self, known, chain):
        """Check if a chain is a member of the set of knowns.

        Parameters
        ----------
        known : set
            A set of tuples as produced by known_unit_entries.
        chain : dict
            A dict with 'pdb' and 'name' entries for the pdb id and chain name.

        Returns
        -------
        member : bool
            True if the chain is a member of the set.
        """
        getter = op.itemgetter('pdb', 'name')
        return getter(chain) in known


    def to_process(self, pdbs, **kwargs):
        """This will compute all pairs to compare. This will group all pdbs
        using only sequence and species and then produce a list of chains that
        are only the chains in the same group. It will also filter out all
        pairs that have a chain with a poor resolution or is too small. This
        will produce all comparisions that are needed for the NR set and no
        more. If no groups are produced we raise an exception.

        Parameters
        ----------
        pdbs : list
            List of pdb ids to transform.

        Raises
        ------
        pymotifs.core.InvalidState
            If there is no grouping produced.

        Returns
        -------
        pairs : list
            A list of pairs of chain ids to compare.
        """

        self.logger.debug("Entering to_process...")

        grouper = Grouper(self.config, self.session)
        grouper.use_discrepancy = False
        #grouper.must_enforce_single_species = False
        grouper.must_enforce_single_species = True
        groups = grouper(pdbs)
        if not groups:
            raise core.InvalidState("No groups produced")

        has_rotations = ft.partial(self.is_member,
                                   self.known_unit_entries(mod.UnitCenters))
        has_centers = ft.partial(self.is_member,
                                 self.known_unit_entries(mod.UnitRotations))
        possible = []
        for group in groups:
            chains = it.ifilter(disc.valid_chain, group['members'])
            chains = it.ifilter(has_rotations, chains)
            chains = it.ifilter(has_centers, chains)
            chains = it.imap(op.itemgetter('db_id'), chains)
            possible.extend(it.combinations(chains, 2))

        self.logger.debug("Possibles collected...")

        key = op.itemgetter(0)
        ordered_chains = sorted(possible, key = key)
        result = []
        #comp_limit = 200
        #comp_limit = 30
        #comp_limit = 3000
        comp_limit = 460

        calc_limit = 1

        calc = 0

        for (first, rest) in it.groupby(ordered_chains, key):
            #if calc >= calc_limit:
            #    continue
            #seconds = [r[1] for r in rest]
            temp = [r[1] for r in rest]
            #uniq_sec = make_unique_list([r[1] for r in rest])
            #uniq_sec = make_unique_list(seconds)
            seconds = make_unique_list(temp)
            self.logger.info("to_process: first: %s" % first)
            self.logger.info("to_process: seconds: %s" % seconds)
            #self.logger.info("to_process: uniq_sec: %s" % uniq_sec)
            #if len(seconds) < comp_limit:
            if (1 + len(seconds)) == comp_limit:
                result.append((first, seconds))
            else:
                #self.logger.warning("length pass (%s > %s) for %s, %s" % (1+len(seconds), comp_limit, first, seconds))
                self.logger.warning("length skip (%s < %s) for %s, %s" % (1+len(seconds), comp_limit, first, seconds))
            #calc = 1 + calc
        #return sorted(possible)
        self.logger.debug("to_process: result: %s" % result)
        return result


    def is_missing(self, entry, **kwargs):
        """Determine if we do not have any data. If we have no data then we
        will recompute. This method must be implemented by inhering classes
        and is how we determine if we have data or not.

        Parameters
        ----------
        entry : object
            The data to check
        **kwargs : dict
            Generic keyword arguments

        Returns
        -------
        missing : bool
            True if the data is missing.
        """
        return True


    def query(self, session, pair):
        """Create a query to find the comparisions using the given pair of
        chains. This will find a pair in either direction. Also, this ignores
        the model and other information and uses only chain ids.

        Parameters
        ----------
        session : pymotifs.core.Session
            The session to use

        pair : (int, int)
            The pair of chain ids to look up.

        Returns
        -------
        query : query
            The query for chains.
        """

        self.logger.info("query: first: %s // second (clean): %s" % (pair[0], pair[1][0]))

        sim = mod.ChainChainSimilarity

        return session.query(sim).\
            filter(or_(and_(sim.chain_id_1==pair[0],sim.chain_id_2.in_(pair[1])),
                       and_(sim.chain_id_2==pair[0],sim.chain_id_1.in_(pair[1]))))



    def pickledata(self, corr_id, info1, info2, name='base'):
        """Load the matrices used to compute discrepancies. This will look up
        all the centers and rotation matrices in one query. If any centers or
        rotation matrices are missing it will log an error. If there are alt
        ids the 'A' one will be used.

        Parameters
        ----------
        corr_id : int
            The correspondence id.
        info1 : dict
            The result of `info` for the first chain to compare.
        info2 : dict
            The result of `info` for the second chain to compare.
        name : str, optional
            The type of base center to use.

        Returns
        -------
        data : (list, list, list, list)
            This returns 4 lists, which are in order, centers1, centers2,
            rotation1, rotation2.
        """

        allunitdictionary = defaultdict()

        ife_chain_1 = info1['ife_id'].replace('|','-')
        ife_chain_2 = info2['ife_id'].replace('|','-')

        self.logger.info("pickledata (1): start query for ic1: %s // ic2: %s" % (ife_chain_1, ife_chain_2))
        self.logger.debug("pickledata (2.1): info for %s: %s" % (ife_chain_1, str(info1)))
        self.logger.debug("pickledata (2.2): info for %s: %s" % (ife_chain_2, str(info2)))

        with self.session() as session:
            units1 = aliased(mod.UnitInfo)
            units2 = aliased(mod.UnitInfo)
            corr_units = mod.CorrespondenceUnits
            corr_pdb = mod.CorrespondencePdbs

            columns = [corr_pdb.correspondence_id, corr_units.unit_id_1.label('unit1'), corr_units.unit_id_2.label('unit2')]

            query = session.query(*columns).\
                join(corr_units,
                     corr_pdb.correspondence_id == corr_units.correspondence_id).\
                join(units1, units1.unit_id == corr_units.unit_id_1).\
                join(units2, units2.unit_id == corr_units.unit_id_2).\
                filter(corr_pdb.pdb_id_1 == corr_units.pdb_id_1).\
                filter(corr_pdb.pdb_id_2 == corr_units.pdb_id_2).\
                filter(corr_pdb.chain_name_1 == corr_units.chain_name_1).\
                filter(corr_pdb.chain_name_2 == corr_units.chain_name_2).\
                filter(corr_pdb.correspondence_id == corr_id).\
                filter(corr_pdb.chain_id_1 == info1['chain_id']).\
                filter(corr_pdb.chain_id_2 == info2['chain_id']).\
                filter(units1.sym_op == info1['sym_op']).\
                filter(units2.sym_op == info2['sym_op']).\
                filter(units1.alt_id == info1['alt_id']).\
                filter(units2.alt_id == info2['alt_id']).\
                filter(units1.model == info1['model']).\
                filter(units2.model == info2['model']).\
                order_by(corr_units.correspondence_index).\
                distinct()

            self.logger.info("pickledata (3.0):  result set length: %s" % query.count())

            if not query.count():
                self.logger.warning("No geometric data for %s %s", info1, info2)
                #raise core.Skip("Missing geometric data")

            self.logger.info("pickledata (3): obtained correspondence units")

            for key in ( ife_chain_1, ife_chain_2 ):
                splitchain = key.split("+")

                for chunk in splitchain:
                    outfile = 'pickle-FR3D/' + chunk + '_RNA.pickle'

                    self.logger.debug("Pickle file: %s" % str(outfile))

                    with open(outfile, 'rb') as fh:
                        data = map(list,map(None,*pickle.load(fh)))

                        self.logger.debug("Data for %s: %s" % (key, str(data)))

                        for line in data:
                            unitid = line[0]
                            allunitdictionary[unitid] = line

            self.logger.info("pickledata (4): pickle data import complete")

            c1 = []
            c2 = []
            r1 = []
            r2 = []
            seen = set()

            for r in query:
                self.logger.debug("pickledata (5): row: %s" % str(r))

                if r.unit1 in seen:
                    raise core.InvalidState("pickledata: Got duplicate unit (unit1) %s" % r.unit1)
                seen.add(r.unit1)

                if r.unit2 in seen:
                    raise core.InvalidState("pickledata: Got duplicate unit (unit2) %s" % r.unit2)
                seen.add(r.unit2)

                if allunitdictionary.get(r.unit1) is not None and allunitdictionary.get(r.unit2) is not None:
                    c1.append(allunitdictionary[r.unit1][2])
                    c2.append(allunitdictionary[r.unit2][2])
                    r1.append(allunitdictionary[r.unit1][3])
                    r2.append(allunitdictionary[r.unit2][3])

        self.logger.info("pickledata (6): end query for %s // %s" % (ife_chain_1, ife_chain_2))

        return np.array(c1), np.array(c2), np.array(r1), np.array(r2)


    def pd2(self, corr_id, info1, info2, name='base'):
        """Load the matrices used to compute discrepancies. This will look up
        all the centers and rotation matrices in one query. If any centers or
        rotation matrices are missing it will log an error. If there are alt
        ids the 'A' one will be used.

        Parameters
        ----------
        corr_id : int
            The correspondence id.
        info1 : dict
            The result of `info` for the first chain to compare.
        info2 : dict
            The result of `info` for the second chain to compare.
        name : str, optional
            The type of base center to use.

        Returns
        -------
        data : (list, list, list, list)
            This returns 4 lists, which are in order, centers1, centers2,
            rotation1, rotation2.
        """

        allunitdictionary = defaultdict()
        unit_dict_1 = defaultdict()
        unit_dict_2 = defaultdict()

        ife_chain_1 = info1['ife_id'].replace('|','-')
        ife_chain_2 = info2['ife_id'].replace('|','-')

        self.logger.info("pd2 (1): start query for ic1: %s // ic2: %s" % (ife_chain_1, ife_chain_2))
        self.logger.debug("pd2 (2.1): info for %s: %s" % (ife_chain_1, str(info1)))
        self.logger.debug("pd2 (2.2): info for %s: %s" % (ife_chain_2, str(info2)))

        with self.session() as session:
            corr_units = mod.CorrespondenceUnits

            columns = [corr_units.correspondence_id, corr_units.unit_id_1.label('unit1'), corr_units.unit_id_2.label('unit2')]

            query = session.query(*columns).\
                filter(corr_units.correspondence_id == corr_id).\
                filter(corr_units.pdb_id_1 == info1['pdb']).\
                filter(corr_units.pdb_id_2 == info2['pdb']).\
                filter(corr_units.chain_name_1 == info1['chain_name']).\
                filter(corr_units.chain_name_2 == info2['chain_name']).\
                order_by(corr_units.correspondence_index).\
                distinct()

            self.logger.info("pd2 (3.0):  result set length: %s" % query.count())

            if not query.count():
                self.logger.warning("No geometric data for %s %s", info1, info2)
                #raise core.Skip("Missing geometric data")

            self.logger.info("pd2 (3): obtained correspondence units")

            for key in ( ife_chain_1, ife_chain_2 ):
                splitchain = key.split("+")

                if key == ife_chain_1:
                    info_d = info1
                else:
                    info_d = info2

                self.logger.info("pd2: debug: ife_chain %s (root %s): alt_id/sym_op/model: [%s/%s/%s]" % 
                                 (key,info_d['ife_id'],info_d['alt_id'],info_d['sym_op'],info_d['model']))

                for chunk in splitchain:
                    outfile = 'pickle-FR3D/' + chunk + '_RNA.pickle'

                    self.logger.debug("Pickle file: %s" % str(outfile))

                    with open(outfile, 'rb') as fh:
                        data = map(list,map(None,*pickle.load(fh)))

                        self.logger.debug("Data for %s: %s" % (key, str(data)))

                        for line in data:
                            unitid = line[0]
                            split_unit = unitid.split('|')

                            if len(split_unit) > 6:
                                #if split_unit[6] is not None and split_unit[6] <> info_d['alt_id']:
                                #if (split_unit[6] == "" and info_d['alt_id'] is not None) or split_unit[6] <> info_d['alt_id']:
                                if split_unit[6] in ("B", "C"):
                                    self.logger.info("pd2: Extended unit %s, alt_id (desired/actual):  [%s/%s]" % (unitid, info_d['alt_id'], split_unit[6]))
                                    continue

                                if len(split_unit) > 8:
                                    #if split_unit[8] != info_d['sym_op']:
                                    if split_unit[8] is not None:
                                        self.logger.info("pd2: Extended unit %s, sym_op (desired/actual):  %s/%s" % (unitid, info_d['sym_op'], split_unit[8]))
                                        continue

                                self.logger.info("pd2: Extended unit %s to be used" % unitid)

                            if split_unit[1] != str(info_d['model']):
                                self.logger.info("pd2: skipped %s for model number %s" % (unitid, split_unit[1]))
                                continue

                            if key == ife_chain_1:
                                unit_dict_1[unitid] = line
                                self.logger.debug("pd2: unit_dict_1 for unitid %s: %s" % (unitid, line))
                            else:
                                unit_dict_2[unitid] = line 
                                self.logger.debug("pd2: unit_dict_2 for unitid %s: %s" % (unitid, line))

            self.logger.info("pd2: unit_dict lengths:  %s / %s" % (len(unit_dict_1), len(unit_dict_2)))

            c1 = []
            c2 = []
            r1 = []
            r2 = []
            pd2seen = set()

            for r in query:
                self.logger.debug("pd2 (5): row: %s" % str(r))

                uspl1 = r.unit1.split('|')
                uspl2 = r.unit2.split('|')

                if str(uspl1[1]) != '1' or str(uspl2[1]) != '1':
                    continue 

                #if r.unit1 in pd2seen:
                #    raise core.InvalidState("pd2: Got duplicate unit (unit1) %s" % r.unit1)
                #pd2seen.add(r.unit1)

                #if r.unit2 in pd2seen:
                #    raise core.InvalidState("pd2: Got duplicate unit (unit2) %s" % r.unit2)
                #pd2seen.add(r.unit2)

                if unit_dict_1.get(r.unit1) is not None and unit_dict_2.get(r.unit2) is not None:
                    if r.unit1 in pd2seen:
                        raise core.InvalidState("pd2: Got duplicate unit (unit1) %s" % r.unit1)
                    pd2seen.add(r.unit1)

                    if r.unit2 in pd2seen:
                        raise core.InvalidState("pd2: Got duplicate unit (unit2) %s" % r.unit2)
                    pd2seen.add(r.unit2)

                    c1.append(unit_dict_1[r.unit1][2])
                    c2.append(unit_dict_2[r.unit2][2])
                    r1.append(unit_dict_1[r.unit1][3])
                    r2.append(unit_dict_2[r.unit2][3])

        self.logger.info("pd2 (6): end query for %s // %s" % (ife_chain_1, ife_chain_2))

        return np.array(c1), np.array(c2), np.array(r1), np.array(r2)


    def discrepancy(self, corr_id, name1, name2, centers1, centers2, rot1, rot2):
        """Compare the chains. This will filter out all residues in the chain
        that do not have a base center computed.

        Parameters
        ----------
        corr_id : int
            The correspondence id to use.
        centers1 : list
            List of numpy.array of the centers for first chain.
        centers2 : list
            List of numpy.array of the centers for second chain.
        rot1 : list
            List of numpy.array of the rotation matrices for first chain.
        rot2 : list
            List of numpy.array of the rotation matrices for second chain.

        Returns
        -------
        data : (float, int)
            A tuple of the discrepancy and then number of nucleotides used in
            the discrepancy.
        """

        self.logger.info("Comparing %i pairs of residues for %s, %s" % (len(centers1), name1, name2))
        disc = matrix_discrepancy(centers1, rot1, centers2, rot2)

        if np.isnan(disc):
            raise core.InvalidState("NaN for discrepancy")

        return disc, len(centers1)


    def info(self, chain_id):
        """Load the required information about a chain. Since we want to use
        the results of this loader for the NR stages we use the same data as
        was in the IFE's the given chain is a part of.

        Parameters
        ----------
        chain_id : int
            The chain id to look up.

        Returns
        -------
        ife_info : dict
            A dict with a 'chain_name', 'chain_id', `pdb`, `model`, `ife_id`,
            `sym_op`, 'alt_id', and `name` keys.
        """

        with self.session() as session:
            query = session.query(mod.ChainInfo.chain_name,
                                  mod.ChainInfo.chain_id,
                                  mod.IfeInfo.pdb_id.label('pdb'),
                                  mod.IfeInfo.model,
                                  mod.IfeInfo.ife_id,
                                  ).\
                join(mod.IfeChains,
                     mod.IfeChains.chain_id == mod.ChainInfo.chain_id).\
                join(mod.IfeInfo,
                     mod.IfeInfo.ife_id == mod.IfeChains.ife_id).\
                filter(mod.IfeInfo.new_style == 1).\
                filter(mod.ChainInfo.chain_id == chain_id)

        if not query.count():
            raise core.InvalidState("Could not load chain with id %s" %
                                    chain_id)
        ife = ut.row2dict(query.first())

        with self.session() as session:
            query = session.query(mod.UnitInfo.sym_op,
                                  mod.UnitInfo.alt_id,
                                  ).\
                join(mod.ChainInfo,
                     (mod.ChainInfo.pdb_id == mod.UnitInfo.pdb_id) &
                     (mod.ChainInfo.chain_name == mod.UnitInfo.chain)).\
                join(mod.UnitCenters,
                     mod.UnitCenters.unit_id == mod.UnitInfo.unit_id).\
                join(mod.UnitRotations,
                     mod.UnitRotations.unit_id == mod.UnitInfo.unit_id).\
                filter(mod.ChainInfo.chain_id == chain_id).\
                distinct()

            if not query.count():
                raise core.InvalidState("Could not get info for chain %s" %
                                        chain_id)

            ife['sym_op'] = pick(['1_555', 'P_1'], 'sym_op', query)
            ife['alt_id'] = pick([None, 'A', 'B'], 'alt_id', query)
            ife['name'] = ife['ife_id'] + '+' + ife['sym_op']
            return ife


    def __correspondence_query__(self, chain1, chain2):
        """Create a query for correspondences between the two chains. This only
        checks in the given direction.

        Parameters
        ----------
        chain1 : int
            The first chain id.
        chain2 : int
            The second chain id.

        Returns
        -------
        corr_id : int
            The correspondence id if there is an alignment between the two
            chains.
        """

        with self.session() as session:
            info = mod.CorrespondenceInfo
            mapping1 = aliased(mod.ExpSeqChainMapping)
            mapping2 = aliased(mod.ExpSeqChainMapping)
            query = session.query(info.correspondence_id).\
                join(mapping1, mapping1.exp_seq_id == info.exp_seq_id_1).\
                join(mapping2, mapping2.exp_seq_id == info.exp_seq_id_2).\
                filter(mapping1.chain_id == chain1).\
                filter(mapping2.chain_id == chain2).\
                filter(info.good_alignment == 1)

            result = query.first()
            if result:
                return result.correspondence_id
            return None


    def corr_id(self, chain_id1, chain_id2):
        """Given two chain ids, load the correspondence id between them. This
        will raise an exception if these chains have not been aligned, or if
        there is more than one alignment between these chains. The chain ids
        should be the ids used in the database.

        Parameters
        ----------
        chain_id1 : int
            First chain id.
        chain_id2 : int
            Second chain id.

        Raises
        ------
        core.Skip
            If there is no alignment between the two chains

        Returns
        -------
        corr_id : int
            The correspondence id for the alignment between the two chains.
        """

        self.logger.debug("corr_id: chain_id1: %s" % chain_id1)
        self.logger.debug("corr_id: chain_id2: %s" % chain_id2)

        corr_id = self.__correspondence_query__(chain_id1, chain_id2)
        if corr_id is None:
            corr_id = self.__correspondence_query__(chain_id2, chain_id1)

        if corr_id is None:
            #raise core.Skip("No good correspondence between %s, %s" %
            #                (chain_id1, chain_id2))
            self.logger.warning("No good correspondence between %s, %s" % 
                                (chain_id1, chain_id2))
        return corr_id


    def __check_matrices__(self, table, info):
        """Check the that there are entries for the given info dict in the
        given table.

        Parameters
        ----------
        table : Table
            The table to look up in
        info : dict
            The info dict to use.

        Returns
        -------
        has_entries : bool
            True if there are entries in the table.
        """

        with self.session() as session:
            query = session.query(table).\
                join(mod.UnitInfo,
                     mod.UnitInfo.unit_id == table.unit_id).\
                filter(mod.UnitInfo.pdb_id == info['pdb']).\
                filter(mod.UnitInfo.chain == info['chain_name']).\
                filter(mod.UnitInfo.model == info['model']).\
                filter(mod.UnitInfo.sym_op == info['sym_op']).\
                limit(1)

            return bool(query.count())


    def has_matrices(self, info):
        """Check if the given info has all the required matrices. This will
        check in the database for entries in the unit_centers and
        unit_rotations for the given chain.

        Parameters
        ----------
        info : dict
            The info dict to check.

        Returns
        -------
        valid : bool
            True if the given chain has all required matrices.
        """

        return self.__check_matrices__(mod.UnitCenters, info) and \
            self.__check_matrices__(mod.UnitRotations, info)


    def entry(self, info1, info2, corr_id):
        """Compute the discrepancy between two given chains. The info
        dictonaries should be from the `Loader.info` method. This will produce
        the discrepancy in both orderings, first to second and then second to
        first. The resulting list will always have those two elements.

        Parameters
        ----------
        info1 : dict
            The first chain to use.
        info2 : dict
            The second chain to use
        corr_id : dict
            The correspondence id.

        Returns
        -------
        entries : list
            A list of dictonaries with the discrepancies betweeen these chains.
            The dictonaries will have keys `chain_id_1`, `chain_id_2`,
            `model_1`, `model_2`, `correspondence_id`, `discrepancy` and
            `num_nucleotides`.
        """

        self.logger.debug("entry: info1: %s" % info1)
        self.logger.debug("entry: info2: %s" % info2)
        self.logger.debug("entry: corr_id: %s" % corr_id)

        if not self.has_matrices(info1):
            self.logger.warning("Missing matrix data for %s", info1['name'])
            return []

        if not self.has_matrices(info2):
            self.logger.warning("Missing matrix data for %s", info2['name'])
            return []

        pickledata = self.pickledata(corr_id, info1, info2)
        if len(filter(lambda m: len(m), pickledata)) != len(pickledata):
            self.logger.warning("Did not load all data for %s, %s",
                                info1['name'], info2['name'])
            #return []

        if len(pickledata[0]) < 3:
            self.logger.warning("Not enough centers for pair: %s, %s" %
            #raise core.Skip("Not enough centers for pair: %s, %s" %
                            (info1['chain_id'], info2['chain_id']))

        try:
            pdisc, plength = self.discrepancy(corr_id, info1['name'], info2['name'], *pickledata)
        except Exception as err:
            self.logger.warning("Could not compute discrepancy for %s %s, using magic values instead" %
                              (info1['name'], info2['name']))
            pdisc = -1
            plength = 0

        pcompare = {
            'chain_id_1': info1['chain_id'],
            'chain_id_2': info2['chain_id'],
            'model_1': info1['model'],
            'model_2': info2['model'],
            'correspondence_id': corr_id,
            'discrepancy': float(pdisc),
            'num_nucleotides': plength,
        }

        preversed = dict(pcompare)
        preversed['chain_id_1'] = pcompare['chain_id_2']
        preversed['chain_id_2'] = pcompare['chain_id_1']
        preversed['model_1'] = pcompare['model_2']
        preversed['model_2'] = pcompare['model_1']

        p2data = self.pd2(corr_id, info1, info2)
        if len(filter(lambda m: len(m), p2data)) != len(p2data):
            self.logger.warning("Did not load all data for %s, %s",
                                info1['name'], info2['name'])
            #return []

        if len(p2data[0]) < 3:
            self.logger.warning("pd2: p2data[0] = %s" % p2data[0])
            self.logger.warning("Not enough centers for pair: %s, %s" %
                                (info1['chain_id'], info2['chain_id']))

        try:
            p2disc, p2length = self.discrepancy(corr_id, info1['name'], info2['name'], *p2data)
        except Exception as err:
            self.logger.warning("Could not compute discrepancy for %s %s, using magic values instead" %
                              (info1['name'], info2['name']))
            p2disc = -1
            p2length = 0

        pd2c = {
            'chain_id_1': info1['chain_id'],
            'chain_id_2': info2['chain_id'],
            'model_1': info1['model'],
            'model_2': info2['model'],
            'correspondence_id': corr_id,
            'discrepancy': float(p2disc),
            'num_nucleotides': p2length,
        }

        pd2r = dict(pcompare)
        pd2r['chain_id_1'] = pd2c['chain_id_2']
        pd2r['chain_id_2'] = pd2c['chain_id_1']
        pd2r['model_1'] = pd2c['model_2']
        pd2r['model_2'] = pd2c['model_1']

        self.logger.info("IFE1/IFE2: %s / %s : Discrepancies/Length (pickle/revised): %s / %s : %s / %s" % (info1['name'], info2['name'], pcompare['discrepancy'], pcompare['num_nucleotides'], pd2c['discrepancy'], pd2c['num_nucleotides']))

        return [
            #compare,
            #reversed,
            #pcompare,
            #preversed
            pd2c,
            pd2r
        ]


    def data(self, entry, **kwargs):
        """Compute all chain to chain similarity data. This will get all
        corresponding chains to chain alignment for all chains in this pdb and
        determine the geometric similarity for the chains, if the alignment is
        a good one.

        Parameters
        ----------
        pair : (int, int)
            The pair of chain ids to compute data for

        Returns
        -------
        data : list
            The discrepancies of comparing the first to second as well as the
            second to the first chains.
        """

        self.logger.info("data: entry: %s" % str(entry))

        chain1, candidates = entry
        #chain1, seconds = entry

        info1 = self.info(chain1)

        sim = mod.ChainChainSimilarity

        with self.session() as session:
            query = session.query(sim).\
                filter(or_(and_(sim.chain_id_1==entry[0],sim.chain_id_2.in_(entry[1])),
                           and_(sim.chain_id_2==entry[0],sim.chain_id_1.in_(entry[1]))))

        knowns = []
        seconds = []

        for r in query:
            self.logger.info("data: known: (%s, %s)" % (r.chain_id_1,r.chain_id_2))
            knowns.append((r.chain_id_1,r.chain_id_2))        

        for chain in candidates:
            if ((chain1, chain)) in knowns:
                self.logger.info("data: already have discrepancy for (%s, %s)" % (chain1, chain))
                continue

            self.logger.info("data: adding %s to list of pending calculations" % chain)
            seconds.append(chain)

        for chain2 in seconds:
            if chain2 == chain1:
                continue

            entries = [] 
            info2 = self.info(chain2)
            corr_id = self.corr_id(chain1, chain2)
            self.logger.info("data: chain1: %s // chain2: %s // corr_id: %s" % (chain1, chain2, corr_id))
            if corr_id is not None:
                entries = self.entry(info1, info2, corr_id)
                #entries.append(self.entry(info1, info2, corr_id))

            if entries is not None:
                for e in entries:
                    self.logger.info("data: Entry to load: %s" % e)
                    yield mod.ChainChainSimilarity(**e)

