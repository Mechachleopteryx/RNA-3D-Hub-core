from pymotifs import core

from pymotifs.exp_seq.info import Loader as InfoLoader
from pymotifs.exp_seq.mapping import Loader as MappingLoader
from pymotifs.exp_seq.positions import Loader as PositionsLoader
from pymotifs.exp_seq.chain_mapping import Loader as ChainMappingLoader


class Loader(core.StageContainer):
    stages = set([InfoLoader, ChainMappingLoader, PositionsLoader,
                  MappingLoader])
