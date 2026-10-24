#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh >&2

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [output.json]" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import platform
import shlex
import subprocess
import sys
import tempfile

root = pathlib.Path.cwd()
output = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else None

def capture(*args):
    return subprocess.check_output(args, text=True).strip()

started = datetime.datetime.now(datetime.timezone.utc).isoformat()
commit = capture('git', 'rev-parse', 'HEAD')
status = capture('git', 'status', '--porcelain')
embedding_ref = os.environ.get('SNAPAI_BENCHMARK_EMBEDDING_REF')
if embedding_ref:
    embedding_ref = capture('git', 'rev-parse', '--verify', '--end-of-options', embedding_ref)
dirty_hash = hashlib.sha256(subprocess.check_output(['git', 'diff', '--binary', 'HEAD']))
for name in sorted(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z']).split(b'\0')):
    if not name:
        continue
    path = root / os.fsdecode(name)
    if path.is_file() and path.resolve() != output:
        dirty_hash.update(name + b'\0' + path.read_bytes() + b'\0')

with tempfile.TemporaryDirectory(prefix='snapai-roadmap-benchmark-') as temporary:
    snapshot = pathlib.Path(temporary)
    sources = sorted(root.glob('Sources/SnapAILogic/*.swift'))
    sources.append(root / 'Tests/Performance/RoadmapBenchmarks.swift')
    source_hash = hashlib.sha256()
    copied = []
    for source in sources:
        relative = source.relative_to(root)
        data = source.read_bytes()
        if embedding_ref and source.name == "HistoryEmbeddingSearch.swift":
            data = subprocess.check_output(["git", "show", embedding_ref + ":Sources/SnapAILogic/HistoryEmbeddingSearch.swift"])
        source_hash.update(str(relative).encode() + b'\0' + data + b'\0')
        destination = snapshot / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        copied.append(str(destination))
    binary = snapshot / 'roadmap-benchmark'
    flags = ['-O', '-parse-as-library', '-package-name', 'SnapAI']
    libraries = ['-framework', 'AppKit', '-framework', 'Carbon', '-framework', 'ApplicationServices',
                 '-framework', 'ServiceManagement', '-framework', 'Vision', '-framework', 'NaturalLanguage', '-lsqlite3']
    subprocess.run(['swiftc', *flags, *copied, '-o', str(binary), *libraries], check=True)
    environment = dict(os.environ, SNAPAI_LOGIC_TESTS='1')
    measurements = json.loads(subprocess.check_output([str(binary)], env=environment, text=True))
    result = {
        'metadata': {
            'started_at_utc': started,
            'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'commit': commit,
            'working_tree_dirty': bool(status),
            'dirty_tree_sha256': dirty_hash.hexdigest(),
            'dirty_tree_hash_definition': 'git diff --binary HEAD plus sorted untracked path/content; excludes output path',
            'compiled_sources_sha256': source_hash.hexdigest(),
            'compiled_sources': [str(source.relative_to(root)) for source in sources],
            'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'build_configuration': 'release-optimized standalone swiftc -O; not an App bundle build',
            'build_command': ['swiftc', *flags, 'Sources/SnapAILogic/*.swift', 'Tests/Performance/RoadmapBenchmarks.swift', '-o', '<temporary>/roadmap-benchmark', *libraries],
            'history_embedding_source_ref': embedding_ref,
            'requested_samples': int(os.environ.get('SNAPAI_BENCHMARK_SAMPLES', '30')),
            'source_isolation': 'copied source snapshot compiled outside working tree and SwiftPM build directories',
            'command': shlex.join(['scripts/benchmark-roadmap.sh', *sys.argv[1:]]),
            'swift_version': capture('swiftc', '--version'),
            'xcode_version': capture('xcodebuild', '-version'),
            'developer_dir': os.environ.get('DEVELOPER_DIR', capture('xcode-select', '-p')),
            'macos': capture('sw_vers'),
            'architecture': platform.machine(),
            'hardware_model': capture('sysctl', '-n', 'hw.model'),
            'cpu': capture('sysctl', '-n', 'machdep.cpu.brand_string'),
            'logical_cpu_count': os.cpu_count(),
            'memory_bytes': int(capture('sysctl', '-n', 'hw.memsize')),
        },
        **measurements,
    }
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(encoded)
    print(encoded, end='')
PY
