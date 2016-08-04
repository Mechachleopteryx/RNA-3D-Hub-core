"""This is a module to find the species assignments that look suspicious. The
goal is to produce a report that PDB can use to fix these sorts of issues.
"""
import re
import operator as op
import itertools as it
import collections as coll

from pymotifs import models as mod

from pymotifs.utils import row2dict


HEADERS = [
    'PDB ID',
    'Chain',
    'Species',
    'Problem',
]

BAD_SPECIES = re.compile('^\w+ sp\..*$')


def assignments(maker, **kwargs):
    with maker() as session:
        exp = mod.ExpSeqInfo
        exp_mapping = mod.ExpSeqChainMapping
        chains = mod.ChainInfo
        species = mod.SpeciesMapping
        chain_species = mod.ChainSpecies
        query = session.query(exp.length,
                              exp.exp_seq_id,
                              chains.pdb_id,
                              chains.chain_name,
                              chains.chain_id.label('id'),
                              species.species_name,
                              species.species_id,
                              ).\
            join(exp_mapping, exp_mapping.exp_seq_id == exp.exp_seq_id).\
            outerjoin(chains, chains.chain_id == exp_mapping.chain_id).\
            outerjoin(chain_species,
                      chain_species.chain_id == exp_mapping.chain_id).\
            outerjoin(species, species.species_id == chain_species.species_id)

        return [row2dict(result) for result in query]


def empty_problem(chain):
    return {
        'PDB ID': chain['pdb_id'],
        'Chain': chain['chain_name'],
        'Species': chain['species_name'],
        'Problem': [],
    }


def unnnamed_species(data):
    if not data['species_name'] and data['species_id'] is not None:
        return 'Unnamed species'
    return None


def unlikely_species(data):
    if data['species_name'] and re.match(BAD_SPECIES, data['species_name']):
        return 'Unlikely species name'
    return None


def conflicting_species(chains):
    species = set(c['species_name'] for c in chains)
    species -= set([None, 'synthetic construct'])
    if len(species) > 1:
        return 'Multiple species assigned to this sequence'
    return None


def check_individual(data, problems):
    checkers = [unlikely_species, unnnamed_species]
    for chain in data:
        for checker in checkers:
            problem = checker(chain)
            if problem:
                if chain['id'] not in problems:
                    problems[chain['id']] = empty_problem(chain)
                problems[chain['id']]['Problem'].append(problem)
    return problems


def check_aggregate(data, problems):
    key = op.itemgetter('exp_seq_id')
    aggregate = it.groupby(sorted(data, key=key), key)
    checkers = [conflicting_species]
    for seq_id, chains in aggregate:
        chains = list(chains)
        for checker in checkers:
            problem = checker(chains)
            if problem:
                for chain in chains:
                    if chain['id'] not in problems:
                        problems[chain['id']] = empty_problem(chain)
                    problems[chain['id']]['Problem'].append(problem)
    return problems


def suspicious(data):
    problems = {}
    problems = check_individual(data, problems)
    problems = check_aggregate(data, problems)
    problems = problems.values()

    for entry in problems:
        entry['Problem'] = '; '.join(entry['Problem'])

    return problems


def report(maker, **kwargs):
    current = assignments(maker, **kwargs)
    return suspicious(current)
