import os
import shutil
from pathlib import Path
from typing import Dict

from .chalk.runner import Chalk
from .utils.bin import sha256
from .utils.log import get_logger
from .utils.validate import (
    ArtifactInfo,
    validate_chalk_report,
    validate_extracted_chalk,
    validate_virtual_chalk,
)

logger = get_logger()


def test_codeowners(tmp_data_dir: Path, chalk: Chalk):
    file_path = Path(__file__).parent / "data" / "codeowners" / "raw1"
    artifact_info: Dict[str, ArtifactInfo] = {}
    shutil.copy(file_path / "foo", tmp_data_dir)
    shutil.copy(file_path / "CODEOWNERS", tmp_data_dir)
    shutil.copy(file_path / "helloworld.py", tmp_data_dir)
    os.makedirs(tmp_data_dir / ".git")
    artifact_info[str(tmp_data_dir / "helloworld.py")] = ArtifactInfo(
        type="python", hash=sha256(file_path / "helloworld.py")
    )

    # chalk reports generated by insertion, json array that has one element
    chalk_reports = chalk.insert(artifact=tmp_data_dir / "helloworld.py", virtual=True)
    assert len(chalk_reports) == 1
    chalk_report = chalk_reports[0]
    assert chalk_report["_CHALKS"][0]["CODE_OWNERS"] == "@test\n\nfoo @test2 @test3\n"
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
    validate_virtual_chalk(
        tmp_data_dir=tmp_data_dir, artifact_map=artifact_info, virtual=True
    )
