import os
import unittest as ut

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from fr3d.cif.reader import Cif

import pymotifs.models as models
from pymotifs.config import load as config_loader

CONFIG = config_loader('conf/test.json', )
engine = create_engine(CONFIG['db']['uri'])
models.reflect(engine)
Session = sessionmaker(bind=engine)


def which(program):
    """A utility function to check if we have an executable.

    :program: The program name to search for.
    :return: Path of the executable or None if it does not exist.
    """

    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    fpath, fname = os.path.split(program)
    if fpath:
        if is_exe(program):
            return program
    else:
        for path in os.environ["PATH"].split(os.pathsep):
            path = path.strip('"')
            exe_file = os.path.join(path, program)
            if is_exe(exe_file):
                return exe_file

    return None


skip_without_matlab = pytest.mark.skipif(which('matlab'))


class StageTest(ut.TestCase):
    loader_class = None

    def setUp(self):
        os.chdir(CONFIG['locations']['base'])
        if self.loader_class:
            self.loader = self.loader_class(CONFIG, Session)


class QueryUtilTest(ut.TestCase):
    query_class = None

    def setUp(self):
        if self.query_class:
            self.db_obj = self.query_class(Session)


class CifStageTest(StageTest):
    filename = None

    @classmethod
    def setUpClass(cls):
        if cls.filename:
            with open(cls.filename, 'rb') as raw:
                cls.cif = Cif(raw)
                cls.structure = cls.cif.structure()
        else:
            cls.cif = None
            cls.structure = None

    def setUp(self):
        super(CifStageTest, self).setUp()
        self.structure = self.__class__.structure
        self.cif = self.__class__.cif
