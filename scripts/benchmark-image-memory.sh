#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/configure-swift-toolchain.sh >&2
if [ "$#" != 1 ]; then
  echo "usage: $0 output.json" >&2
  exit 2
fi
python3 - "$1" <<'PY'
import datetime, hashlib, json, os, pathlib, platform, subprocess, sys
root = pathlib.Path.cwd()
output = pathlib.Path(sys.argv[1]).resolve()
work = root / '.build' / ('image-memory-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
work.mkdir(parents=True)
def capture(*args):
    return subprocess.check_output(args, text=True).strip()
sources = ['Sources/SnapAILogic/ImageTextRecognition.swift', 'Tests/Performance/ImageMemoryBenchmarks.swift']
source_hashes = {}
copied = []
for name in sources:
    data = (root / name).read_bytes()
    target = work / pathlib.Path(name).name
    target.write_bytes(data)
    source_hashes[name] = hashlib.sha256(data).hexdigest()
    copied.append(str(target))
binary = work / 'image-memory-benchmark'
command = ['swiftc', '-O', '-parse-as-library', '-package-name', 'SnapAI', *copied, '-o', str(binary), '-framework', 'Vision', '-framework', 'CoreGraphics', '-framework', 'CoreText', '-framework', 'ImageIO']
subprocess.run(command, check=True)
fixture = work / 'large-image.png'
subprocess.run([str(binary), 'generate', str(fixture)], check=True)
metadata = {'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'commit': capture('git', 'rev-parse', 'HEAD'), 'working_tree_dirty': bool(capture('git', 'status', '--porcelain')),
            'source_sha256': source_hashes, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(), 'fixture_path': str(fixture),
            'build_configuration': 'standalone release-optimized swiftc -O; not App bundle', 'build_command': command,
            'swift_version': capture('swiftc', '--version'), 'macos': capture('sw_vers'),
            'hardware_model': capture('sysctl', '-n', 'hw.model'), 'cpu': capture('sysctl', '-n', 'machdep.cpu.brand_string'),
            'memory_bytes': int(capture('sysctl', '-n', 'hw.memsize')), 'architecture': platform.machine(),
            'fixture_generation': 'separate process; 6000x4000 white PNG with twelve Helvetica English text rows; no user files'}
raw = subprocess.check_output([str(binary), 'measure', str(fixture)], env=dict(os.environ, SNAPAI_LOGIC_TESTS='1'))
(work / 'measurements.json').write_bytes(raw)
metadata['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
result = {'metadata': metadata, **json.loads(raw)}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(str(output))
PY
