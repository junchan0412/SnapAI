#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -lt 2 ] || { [ "$1" != --prepare ] && [ "$1" != --run ]; }; then
  echo 'usage: scripts/benchmark-window-latency.sh --prepare BUILD_DIR' >&2
  echo '       SNAPAI_WINDOW_BENCH_SAMPLES=30 scripts/benchmark-window-latency.sh --run BUILD_DIR OUTPUT.json' >&2
  exit 2
fi
if [ "$1" = --prepare ]; then
  [ "$#" -eq 2 ] || exit 2
  source scripts/configure-swift-toolchain.sh >&2
else
  [ "$#" -eq 3 ] || exit 2
fi

python3 - "$@" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import platform
import plistlib
import shlex
import shutil
import subprocess
import sys

root = pathlib.Path.cwd()
mode = sys.argv[1]
build = pathlib.Path(sys.argv[2]).resolve()
bundle = build / 'SnapAIWindowLatency.app'
binary = bundle / 'Contents/MacOS/SnapAIWindowLatency'
metadata_path = build / 'build-metadata.json'

def capture(*args):
    return subprocess.check_output(args, text=True).strip()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

if mode == '--prepare':
    if build.exists():
        raise SystemExit('BUILD_DIR must not exist; use a new path to preserve prior compiled evidence')
    frameworks = sorted((root / '.build/artifacts/sparkle').glob('**/Sparkle.framework'))
    if not frameworks:
        raise SystemExit('Sparkle.framework missing; resolve the normal app dependencies before preparing this benchmark')
    sparkle = frameworks[0]
    build.mkdir(parents=True)
    sources = sorted(root.glob('Sources/SnapAILogic/*.swift'))
    sources += [p for p in sorted(root.glob('Sources/SnapAI/*.swift')) if p.name not in ('main.swift', 'AppPreview.swift')]
    sources += [root / 'Tests/Performance/WindowLatencyBenchmarks.swift']
    source_hash = hashlib.sha256()
    manifest = []
    for source in sources:
        relative = source.relative_to(root)
        data = source.read_bytes()
        destination = build / 'source' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        source_hash.update(str(relative).encode() + b'\0' + data + b'\0')
        manifest.append({'path': str(relative), 'sha256': hashlib.sha256(data).hexdigest()})
    logic = sorted((build / 'source/Sources/SnapAILogic').glob('*.swift'))
    app = sorted((build / 'source/Sources/SnapAI').glob('*.swift'))
    libraries = ['-framework', 'AppKit', '-framework', 'SwiftUI', '-framework', 'Carbon',
                 '-framework', 'ApplicationServices', '-framework', 'ServiceManagement',
                 '-framework', 'Vision', '-framework', 'NaturalLanguage', '-lsqlite3']
    logic_command = ['swiftc', '-O', '-whole-module-optimization', '-parse-as-library', '-package-name', 'snapai',
                     '-module-name', 'SnapAILogic', '-emit-module', '-emit-module-path', str(build / 'SnapAILogic.swiftmodule'),
                     '-emit-object', *map(str, logic), '-o', str(build / 'SnapAILogic.o'), *libraries]
    binary.parent.mkdir(parents=True)
    app_command = ['swiftc', '-O', '-parse-as-library', '-package-name', 'snapai', '-I', str(build),
                   '-F', str(sparkle.parent), *map(str, app),
                   str(build / 'source/Tests/Performance/WindowLatencyBenchmarks.swift'),
                   str(build / 'SnapAILogic.o'), '-o', str(binary), *libraries,
                   '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks']
    started = now()
    subprocess.run(logic_command, check=True)
    subprocess.run(app_command, check=True)
    resources = bundle / 'Contents/Resources'
    resources.mkdir(parents=True)
    resource_manifest = []
    for localization in sorted((root / 'Sources/SnapAI/Resources').glob('*.lproj')):
        shutil.copytree(localization, resources / localization.name)
        for file in sorted(localization.rglob('*')):
            if file.is_file():
                resource_manifest.append({'path': str(file.relative_to(root)), 'sha256': sha(file)})
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.snapai.window-latency', 'CFBundleName': 'SnapAI Window Latency',
        'CFBundleExecutable': binary.name, 'CFBundlePackageType': 'APPL',
        'NSPrincipalClass': 'NSApplication', 'LSMinimumSystemVersion': '14.0',
        'SnapAIBuildConfiguration': 'release-optimized-isolated-runtime-fixture',
    }))
    (bundle / 'Contents/Frameworks').mkdir()
    subprocess.run(['/usr/bin/ditto', str(sparkle), str(bundle / 'Contents/Frameworks/Sparkle.framework')], check=True)
    subprocess.run(['xcrun', 'strip', '-S', '-x', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(bundle)], check=True)
    metadata = {
        'prepared_at_utc': started, 'build_finished_at_utc': now(),
        'commit': capture('git', 'rev-parse', 'HEAD'),
        'working_tree_status': capture('git', 'status', '--porcelain'),
        'tracked_diff_sha256': hashlib.sha256(subprocess.check_output(['git', 'diff', '--binary', 'HEAD'])).hexdigest(),
        'compiled_sources_sha256': source_hash.hexdigest(), 'compiled_sources': manifest,
        'compiled_sources_hash_definition': 'sorted logic sources, sorted app sources excluding main/AppPreview, then runner; relative path NUL content NUL',
        'localized_resources': resource_manifest, 'binary_sha256': sha(binary),
        'build_configuration': 'swiftc -O, logic whole-module-optimization; real app controllers and views, isolated entry point; no DEBUG or preview macro; not distribution package',
        'build_commands': [logic_command, app_command],
        'swift_version': capture('swiftc', '--version'), 'xcode_version': capture('xcodebuild', '-version'),
        'developer_dir': os.environ.get('DEVELOPER_DIR', capture('xcode-select', '-p')),
        'script_sha256': sha(root / 'scripts/benchmark-window-latency.sh'),
        'sparkle_framework_binary_sha256': sha(sparkle / 'Sparkle'),
        'source_isolation': 'all compiled Swift source bytes copied into retained BUILD_DIR/source before compilation',
    }
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print('Prepared ' + str(build))
    print('Run serially on an unlocked desktop: SNAPAI_WINDOW_BENCH_SAMPLES=30 scripts/benchmark-window-latency.sh --run ' + shlex.quote(str(build)) + ' OUTPUT.json')
else:
    count = int(os.environ.get('SNAPAI_WINDOW_BENCH_SAMPLES', '30'))
    if not 1 <= count <= 100:
        raise SystemExit('SNAPAI_WINDOW_BENCH_SAMPLES must be 1..100')
    output = pathlib.Path(sys.argv[3]).resolve()
    metadata = json.loads(metadata_path.read_text())
    if sha(binary) != metadata['binary_sha256']:
        raise SystemExit('Compiled binary hash changed; prepare a new build directory')
    run = build / ('run-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    run.mkdir()
    fixtures = run / 'fixtures'
    fixtures.mkdir()
    raw = run / 'samples.json'
    command = ['/usr/bin/open', '-n', '-W', '--env', 'SNAPAI_LOGIC_TESTS=1',
               '--stdout', str(run / 'stdout.log'), '--stderr', str(run / 'stderr.log'),
               str(bundle), '--args', str(raw), str(fixtures), str(count)]
    started = now()
    try:
        subprocess.run(command, check=True, timeout=180)
    except subprocess.TimeoutExpired:
        raise SystemExit('Fixture exceeded 180 seconds; retained diagnostics in ' + str(run))
    if not raw.is_file():
        print((run / 'stderr.log').read_text() if (run / 'stderr.log').exists() else '', file=sys.stderr)
        raise SystemExit('No samples written; inspect ' + str(run))
    result = {
        'metadata': {**metadata, 'started_at_utc': started, 'finished_at_utc': now(),
                     'run_command': command, 'requested_samples': count, 'raw_results_path': str(raw),
                     'macos': capture('sw_vers'), 'architecture': platform.machine(),
                     'hardware_model': capture('sysctl', '-n', 'hw.model'),
                     'cpu': capture('sysctl', '-n', 'machdep.cpu.brand_string'),
                     'logical_cpu_count': os.cpu_count(), 'memory_bytes': int(capture('sysctl', '-n', 'hw.memsize'))},
        **json.loads(raw.read_text()),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'groups': result['groups'], 'output': str(output)}, ensure_ascii=False, indent=2))
    if result['status'] != 'PASS':
        raise SystemExit(1)
PY
