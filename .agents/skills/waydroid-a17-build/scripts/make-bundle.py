#!/usr/bin/env python3
"""Assemble a native bundle from a previous one plus this workspace's fresh builds, then pin it.

    make-bundle.py --base nvidia/build/native-a17-rc11 --out nvidia/build/native-a17-nvenc \
        --release v0.2.0-rc11-a17-nvenc --note "NVENC Codec2 encoders" \
        [--service src/out/.../android.hardware.media.c2@1.2-service-nvprolapse]

Paths are relative to the workspace (the parent of this repository, or $WAYDROID_A17_WS).
Without --service the base bundle's service is kept (pass 1 of the two-pass service build).

Copies, per ABI (x86_64 -> lib64, x86 -> lib):
  build/nv-rm-rust/<triple>/release/libnv_bionic_native.so  -> payload/vendor_extra/<lib>/
  build/nvk-<target>/.../libvulkan_nouveau.so               -> payload/vendor_extra/<lib>/
  build/nvrm-<target>/ (EGL, GLES, gallium, stripped)       -> payload/vendor{,_extra}/<lib>/...
  nvidia-prolapse/media/out/android/nvc2-xmlgen             -> gate/bin/android/
and refuses to continue when nvrm was not linked against the Rust library being shipped: the release gate
checks `nvrm_rust_sha256` against the payload, so rebuild nvrm after every Rust RM change
(rebuild-native.sh does all of these).
"""
import argparse, hashlib, json, os, shutil, subprocess, sys

ABIS = (  # target, payload lib dir, record abi, rust triple
    ('android', 'lib64', 'x86_64', 'x86_64-linux-android'),
    ('android32', 'lib', 'x86', 'i686-linux-android'),
)
NVRM = {'libEGL_nvrm.so': 'src/egl', 'libGLESv1_CM_nvrm.so': 'src/mesa/glapi/es1api',
        'libGLESv2_nvrm.so': 'src/mesa/glapi/es2api', 'libgallium_dri_nvrm.so': 'src/gallium/targets/dri'}
SVC = 'payload/odm/bin/hw/android.hardware.media.c2@1.2-service-nvprolapse'


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    ws = os.environ.get('WAYDROID_A17_WS') or os.path.dirname(repo)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--base', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--release', required=True)
    ap.add_argument('--note', required=True, help='appended to the record component description')
    ap.add_argument('--service', help='Soong-installed (stripped) Codec2 service binary')
    a = ap.parse_args()
    W = f'{ws}/nvidia/waydroid-nvidia'
    base, out = os.path.join(ws, a.base), os.path.join(ws, a.out)
    strip = f'{W}/build/hwcomposer-work/ndk/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'

    rec_old = json.load(open(f'{base}/BUILD-RECORD.json'))
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(base, out, symlinks=True)
    d = json.load(open(f'{out}/BUILD-RECORD.json'))
    commit = subprocess.check_output(['git', '-C', W, 'rev-parse', 'HEAD'], text=True).strip()
    for target, lib, abi, triple in ABIS:
        rust = f'{W}/build/nv-rm-rust/{triple}/release/libnv_bionic_native.so'
        nvrm = f'{W}/build/nvrm-{target}'
        r = json.load(open(f'{nvrm}/nvrm-build.json'))
        if r['rust']['sha256'] != sha(rust):
            sys.exit(f'{target}: nvrm was linked against Rust RM {r["rust"]["sha256"][:12]}, the build tree has '
                     f'{sha(rust)[:12]}; run rebuild-native.sh')
        if r['driver_source_dirty']:
            sys.exit(f'{target}: nvrm was built from a dirty tree; commit first and rebuild')
        shutil.copy2(rust, f'{out}/payload/vendor_extra/{lib}/libnv_bionic_native.so')
        shutil.copy2(f'{W}/build/nvk-{target}/src/nouveau/vulkan/libvulkan_nouveau.so',
                     f'{out}/payload/vendor_extra/{lib}/libvulkan_nouveau.so')
        d['nvk_builds'][target]['build_metadata'] = json.load(open(f'{W}/build/nvk-{target}/rust-build.json'))
        for name, sub in NVRM.items():
            src = f'{nvrm}/{sub}/{name}'
            if r['artifacts'][name]['sha256'] != sha(src):
                sys.exit(f'{src} differs from its nvrm-build.json')
            rel = f'payload/vendor_extra/{lib}/{name}' if name.startswith('libgallium') else f'payload/vendor/{lib}/egl/{name}'
            subprocess.run([strip, '--strip-debug', '-o', f'{out}/{rel}', src], check=True)
        d['nvrm_rust_sha256'][abi] = r['rust']['sha256']
        d['nvrm_builds'][abi] = {k: r.get(k) for k in ('driver_source_head', 'driver_source_dirty', 'mesa_pin', 'rust_profile')}
    shutil.copy2(f'{W}/nvidia-prolapse/media/out/android/nvc2-xmlgen', f'{out}/gate/bin/android/nvc2-xmlgen')
    if a.service:
        shutil.copy2(os.path.join(ws, a.service), f'{out}/{SVC}')
        os.chmod(f'{out}/{SVC}', 0o755)

    d['previous_release'] = {'release': rec_old['release'], 'build_record_sha256': sha(f'{base}/BUILD-RECORD.json')}
    d['release'] = a.release
    d['component'] = d['component'] + '; ' + a.note
    d['nvk_source_commit'] = commit
    d['local_build'] = {'commit': commit, 'note': a.note,
                        'codec2_service': 'Soong output of the A17 tree' if a.service else 'kept from ' + rec_old['release']}
    for p in d['files']:
        d['files'][p] = sha(f'{out}/{p}')
    open(f'{out}/BUILD-RECORD.json', 'w').write(json.dumps(d, indent=2) + '\n')
    lines = []
    for root, _, files in os.walk(out):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), out)
            if rel != 'SHA256SUMS.native':
                lines.append(f'{sha(os.path.join(out, rel))}  {rel}')
    open(f'{out}/SHA256SUMS.native', 'w').write('\n'.join(sorted(lines, key=lambda l: l.split('  ', 1)[1])) + '\n')
    subprocess.run([sys.executable, '-c', f"import sys; sys.path.insert(0, {W + '/packaging/native'!r}); "
                    f"import release_gate as g; r = g.verify_bundle({out!r}); print('verify ok', r['release'], len(r['files']))"],
                   check=True)

    pin = f'{ws}/nvidia/product/vendor/nvidia-prolapse/native-bundle.json'
    p = json.load(open(pin))
    p.update(path=a.out, build_record_sha256=sha(f'{out}/BUILD-RECORD.json'), release=a.release, nvk_commit=commit)
    open(pin, 'w').write(json.dumps(p, indent=2) + '\n')
    print('pinned', a.release, p['build_record_sha256'])


if __name__ == '__main__':
    main()
