import os
import shutil
from pathlib import Path
from typing import Any, Dict

import pytest

from .chalk.runner import Chalk
from .utils.bin import sha256
from .utils.log import get_logger
from .utils.validate import (
    MAGIC,
    ArtifactInfo,
    validate_chalk_report,
    validate_extracted_chalk,
    validate_virtual_chalk,
)

logger = get_logger()

ZIPFILES = Path(__file__).parent / "data" / "zip"


@pytest.mark.parametrize(
    "test_file",
    [
        "golang",
        "misc",
        "nodejs",
        "python",
    ],
)
def test_virtual_valid(tmp_data_dir: Path, chalk: Chalk, test_file: str):
    files = os.listdir(ZIPFILES / test_file)
    artifact_info = {}
    for file in files:
        file_path = ZIPFILES / test_file / file
        shutil.copy(file_path, tmp_data_dir)

    # we are only checking the ZIP chalk mark, not any of the subchalks
    # HASH is not the file hash -- chalk does something different internally
    # do not check hashes for zip files
    artifact_info[str(tmp_data_dir / file)] = ArtifactInfo(type="ZIP", hash="")

    # chalk reports generated by insertion, json array that has one element
    chalk_reports = chalk.insert(artifact=tmp_data_dir, virtual=True)
    assert len(chalk_reports) == 1
    chalk_report = chalk_reports[0]

    # check chalk report
    validate_chalk_report(
        chalk_report=chalk_report, artifact_map=artifact_info, virtual=True
    )

    # array of json chalk objects as output, of which we are only expecting one
    extract_outputs = chalk.extract(artifact=tmp_data_dir)
    assert len(extract_outputs) == 1
    extract_output = extract_outputs[0]

    validate_extracted_chalk(
        extracted_chalk=extract_output, artifact_map=artifact_info, virtual=True
    )
    # FIXME: virtual chalks not currently validated as every subfile in zip gets chalked
    # generating too many chalks to check
    # validate_virtual_chalk(
    #     tmp_data_dir=tmp_data_dir, artifact_map=artifact_info, virtual=True
    # )


@pytest.mark.parametrize(
    "test_file",
    [
        "golang",
        "misc",
        "nodejs",
        "python",
    ],
)
def test_nonvirtual_valid(tmp_data_dir: Path, chalk: Chalk, test_file: str):
    files = os.listdir(ZIPFILES / test_file)
    artifact_info = {}
    for file in files:
        file_path = ZIPFILES / test_file / file
        shutil.copy(file_path, tmp_data_dir)

    # we are only checking the ZIP chalk mark, not any of the subchalks
    # HASH is not the file hash -- chalk does something different internally
    # do not check hashes for zip files
    artifact_info[str(tmp_data_dir / file)] = ArtifactInfo(type="ZIP", hash="")

    # chalk reports generated by insertion, json array that has one element
    chalk_reports = chalk.insert(artifact=tmp_data_dir, virtual=False)
    assert len(chalk_reports) == 1
    chalk_report = chalk_reports[0]

    # check chalk report
    validate_chalk_report(
        chalk_report=chalk_report, artifact_map=artifact_info, virtual=False
    )

    # array of json chalk objects as output, of which we are only expecting one
    extract_outputs = chalk.extract(artifact=tmp_data_dir)
    assert len(extract_outputs) == 1
    extract_output = extract_outputs[0]

    validate_extracted_chalk(
        extracted_chalk=extract_output, artifact_map=artifact_info, virtual=False
    )
    # validation here okay as we are just checking that virtual-chalk.json file doesn't exist
    validate_virtual_chalk(
        tmp_data_dir=tmp_data_dir, artifact_map=artifact_info, virtual=False
    )