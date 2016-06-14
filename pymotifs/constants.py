"""String to use when joining to IFE ids to build a new ID"""
IFE_SEPERATOR = '+'

"""Min number of base pairs for a chain to be structured."""
STRUCTURED_BP_COUNT = 5

"""Min number of bp/nt for a chain to be structured."""
STRUCTURED_BP_PER_NT = 0.5

"""Min ration of external/internal cWW to join structured IFEs"""
IFE_EXTERNAL_INTERNAL_FRACTION = 0.6

"""PDBS used when bootstrapping the database"""
BOOTSTRAPPING_PDBS = (
    "124D",
    "157D",
    "1A34",
    "1AQ3",
    "1CGM",
    "1DUH",
    "1E4P",
    "1EIY",
    "1EKD",
    "1ET4",
    "1F5H",
    "1F5U",
    "1FAT",
    "1FCW",
    "1FEU",
    "1FG0",
    "1FJG",
    "1G59",
    "1GID",
    "1GRZ",
    "1I9K",
    "1IBK",
    "1J5E",
    "1KOG",
    "1MDG",
    "1S72",
    "1UTD",
    "1VY4",
    "1WMQ",
    "1X8W",
    "2G32",
    "2HOJ",
    "2HOK",
    "2HOL",
    "2HOM",
    "2HOO",
    "2IL9",
    "2MKN",
    "2QQP",
    "2UUA",
    "3CPW",
    "3CW5",
    "3GPQ",
    "3J9M",
    "3T4B",
    "4A3G",
    "4A3J",
    "4CS1",
    "4FTE",
    "4MCE",
    "4MGM",
    "4MGN",
    "4NGG",
    "4NMG",
    "4OAU",
    "4OQ8",
    "4OQ9",
    "4PMI",
    "4Q0B",
    "4R3I",
    "4TUE",
    "4V42",
    "4V4Q",
    "4V6F",
    "4V6M",
    "4V6R",
    "4V7R",
    "4V7W",
    "4V88",
    "4V8G",
    "4V8H",
    "4V8I",
    "4V9K",
    "4V9O",
    "4V9Q",
    "4X4N",
    "4YBB",
    "5AJ3",
)

"""Max allowed discrepancy between chains for NR grouping"""
NR_DISCREPANCY_CUTOFF = 0.4

"""Min percent increase of length to change representative"""
NR_LENGTH_PERCENT_INCREASE = 0.5

"""Min percent increase of bp count to change representative"""
NR_BP_PERCENT_INCREASE = 0.5

"""Length cutoff before being matched as small"""
CORRESPONDENCE_SMALL_CUTOFF = 36

"""Length cutoff before being matched as huge"""
CORRESPONDENCE_HUGE_CUTOFF = 2000

"""Set of pairs that must be joined by into a equivelance class"""
EQUIVELANT_PAIRS = set([
    ('1S72|0', '1FG0|A'),
    ('1S72|0', '1FFZ|A'),
])

LONG_RANGE = 3

"""NCBI Taxon id for synthetic constructs"""
SYNTHENIC_SPECIES_ID = 32630

"""Min size for groups that must have a homogenous species"""
NR_MIN_HOMOGENEOUS_SIZE = 70
