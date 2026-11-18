"""Build the portable count runner from an explicit allowlist."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'docs/COUNT_RUNNER.md', '.Rprofile', 'environment/runtime.R',
    'environment/setup.R', 'environment/renv.lock', 'scripts/00_check_environment.R',
    'scripts/bulk_analysis.R', 'scripts/bulk_run.R', 'scripts/run_bulk.R',
    'scripts/report/render_report.R', 'scripts/report/report.qmd',
)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='New .zip file')
    target = parser.parse_args().destination
    contents = {name: (ROOT / name).read_bytes() for name in FILES}
    with ZipFile(target, 'x', compression=ZIP_DEFLATED) as archive:
        for name, contents_bytes in contents.items():
            archive.writestr('count-runner/' + name, contents_bytes)
