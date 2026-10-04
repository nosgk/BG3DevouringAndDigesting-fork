"""Batch re-rig the 100 DGB belly GR2s onto the current Patch 8 skeleton.

Per file:
  1. divine: mod GR2 -> glTF (+ .bin) in the work dir
  2. python: swap every bone node's rest transform for the current-game donor's
     (by bone name) and rebuild skin.inverseBindMatrices in the same joint order
  3. divine: fixed glTF -> GR2 (work dir)
  4. python: verify by converting nothing - inspect via a second divine pass:
     fixed GR2 -> glTF, compare joints/order/transforms/verts/mesh name
  5. only if verification passes, copy the fixed GR2 over the mod asset
"""
import json, os, shutil, struct, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'build', 'dgb-fix', 'batch')
MOD_ASSETS = os.path.join(ROOT, r'DevouringAndDigesting\Generated\Public\DevouringAndDigesting\Assets\Characters\Humans')
DIVINE = os.path.join(ROOT, r'其它工具\lslib\Packed\Tools\Divine.exe')

DONORS = {
    'F': os.path.join(ROOT, 'build', 'dgb-fix', 'DGB_F_NKD_Body_A.gltf'),
    'M': os.path.join(ROOT, 'build', 'dgb-fix', 'DGB_M_NKD_Body_A.gltf'),
}
PREFIX = {'F': 'SP_DGB_F_Belly_', 'M': 'SP_DGB_M_Belly_'}
COUNT = 50


def divine(src, dst):
    r = subprocess.run([DIVINE, '-g', 'bg3', '-a', 'convert-model',
                        '-s', src, '-d', dst], capture_output=True, text=True)
    return r.returncode == 0, (r.stdout + r.stderr)


def load(gltf_path):
    g = json.load(open(gltf_path, encoding='utf-8'))
    g['_bin_path'] = gltf_path.rsplit('.', 1)[0] + '.bin'
    g['_bin'] = open(g['_bin_path'], 'rb').read()
    return g


def names_of(g):
    return [n.get('name', '') for n in g['nodes']]


def joints_of(g):
    names = names_of(g)
    return [names[j] for j in g['skins'][0]['joints']]


def read_accessor(g, idx):
    acc = g['accessors'][idx]
    bv = g['bufferViews'][acc['bufferView']]
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    comp_size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[acc['componentType']]
    comp = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}[acc['componentType']]
    ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[acc['type']]
    stride = bv.get('byteStride') or ncomp * comp_size
    out = []
    for i in range(acc['count']):
        off = base + i * stride
        out.extend(struct.unpack_from('<' + comp * ncomp, g['_bin'], off))
    return out


def node_local(n):
    if 'matrix' in n:
        m = n['matrix']
        return [m[0::4], m[1::4], m[2::4], m[3::4]]
    from math import pi
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    t = n.get('translation', [0, 0, 0])
    s = n.get('scale', [1, 1, 1])
    return [[r[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def fix_belly(gltf_path, donor):
    a = load(gltf_path)
    orig_joints = joints_of(a)
    orig_names = names_of(a)
    orig_meshes = [m.get('name') for m in a['meshes']]
    orig_verts = sum(a['accessors'][p['attributes']['POSITION']]['count']
                     for m in a['meshes'] for p in m['primitives'])

    b = load(donor)
    bn = names_of(b)
    bmap = {bn[i]: n for i, n in enumerate(b['nodes'])}

    swapped = 0
    for n in a['nodes']:
        nm = n.get('name')
        if nm and nm in bmap and 'mesh' not in n:
            src = bmap[nm]
            for k in ('translation', 'rotation', 'scale', 'matrix'):
                n.pop(k, None)
                if k in src:
                    n[k] = src[k]
            swapped += 1

    joints_a = a['skins'][0]['joints']
    name_of_a = [orig_names[j] for j in joints_a]
    b_joints_names = [bn[j] for j in b['skins'][0]['joints']]
    ibm_b = read_accessor(b, b['skins'][0]['inverseBindMatrices'])
    b_by_name = {b_joints_names[i]: ibm_b[i * 16:(i + 1) * 16] for i in range(len(b_joints_names))}

    new_ibm, unmatched = [], []
    for nm in name_of_a:
        if nm in b_by_name:
            new_ibm.extend(b_by_name[nm])
        else:
            unmatched.append(nm)
            new_ibm.extend([0.0] * 16)

    byte_len = len(new_ibm) * 4
    off = len(a['_bin'])
    off = (off + 3) & ~3
    pad = off - len(a['_bin'])
    a['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': byte_len})
    a['accessors'].append({'bufferView': len(a['bufferViews']) - 1, 'componentType': 5126,
                           'count': len(joints_a), 'type': 'MAT4'})
    a['skins'][0]['inverseBindMatrices'] = len(a['accessors']) - 1
    a['buffers'][0]['byteLength'] = off + byte_len

    open(a['_bin_path'], 'ab').write(b'\x00' * pad + struct.pack('<%df' % len(new_ibm), *new_ibm))
    json.dump({k: v for k, v in a.items() if not k.startswith('_')}, open(gltf_path, 'w'))
    return {'swapped': swapped, 'unmatched': unmatched, 'orig_joints': orig_joints,
            'orig_verts': orig_verts, 'orig_meshes': orig_meshes,
            'weight_sums': weight_sums(a)}


def weight_sums(g):
    """Per-joint-name total skin weight - order-independent rig fingerprint."""
    jnames = joints_of(g)
    sums = {}
    for m in g['meshes']:
        for p in m['primitives']:
            J = read_accessor(g, p['attributes']['JOINTS_0'])
            accw = g['accessors'][p['attributes']['WEIGHTS_0']]
            W = read_accessor(g, p['attributes']['WEIGHTS_0'])
            norm = accw.get('normalized', False)
            div = 65535.0 if norm else 1.0
            for v in range(len(J) // 4):
                for c in range(4):
                    j = J[v * 4 + c]
                    w = W[v * 4 + c] / div
                    sums[jnames[j]] = sums.get(jnames[j], 0.0) + w
    return sums


def verify(gltf_path, meta, donor):
    g = load(gltf_path)
    nv = names_of(g)
    joints = [nv[j] for j in g['skins'][0]['joints']]
    verts = sum(g['accessors'][p['attributes']['POSITION']]['count']
                for m in g['meshes'] for p in m['primitives'])
    meshes = [m.get('name') for m in g['meshes']]

    # divine's GR2 writer may canonicalise joint order; require set equality and
    # an order-independent weight fingerprint instead of raw order
    if set(joints) != set(meta['orig_joints']):
        return False, 'joint set changed'
    if verts != meta['orig_verts']:
        return False, f'vert count changed {verts} != {meta["orig_verts"]}'
    if meshes != meta['orig_meshes']:
        return False, 'mesh name changed'
    ws = weight_sums(g)
    ws0 = meta['weight_sums']
    if set(ws) != set(ws0):
        return False, 'weight joint set changed'
    for nm, w in ws0.items():
        # divine's GR2 writer quantises the 4 weights per vertex, which shifts
        # tiny amounts between a mesh's top bones (~1e-4 relative observed)
        if abs(ws.get(nm, 0.0) - w) > max(1e-2, w * 5e-4):
            return False, f'weight sum mismatch on {nm}'

    b = load(donor)
    bn = names_of(b)
    tn = {nv[i]: n for i, n in enumerate(g['nodes']) if n.get('name')}
    td = {bn[i]: n for i, n in enumerate(b['nodes']) if n.get('name')}
    for nm in joints:
        ma, mb = node_local(tn[nm]), node_local(td[nm])
        for i in range(4):
            for j in range(4):
                # GR2 quantises bone rotations (int16), so near-identity twist
                # bones lose ~1e-5 detail per component on every round trip
                if abs(ma[i][j] - mb[i][j]) > 5e-4:
                    return False, f'transform mismatch on {nm}'
    return True, f'ok ({meta.get("swapped", "?")} bones)'


def swapped_count_check(meta):
    return meta.get('swapped', '?')


def main():
    os.makedirs(WORK, exist_ok=True)
    report = []
    for sex in ('F', 'M'):
        donor = DONORS[sex]
        for i in range(1, COUNT + 1):
            stem = PREFIX[sex] + str(i)
            mod_gr2 = os.path.join(MOD_ASSETS, stem + '.GR2')
            src_gr2 = os.path.join(WORK, stem + '_src.GR2')
            src_gltf = os.path.join(WORK, stem + '_src.gltf')
            fixed_gltf = os.path.join(WORK, stem + '_fixed.gltf')
            fixed_gr2 = os.path.join(WORK, stem + '_fixed.GR2')
            ver_gltf = os.path.join(WORK, stem + '_verify.gltf')
            shutil.copyfile(mod_gr2, src_gr2)

            ok, log = divine(src_gr2, src_gltf)
            if not ok:
                report.append((stem, 'FAIL', 'divine GR2->glTF: ' + log[-200:]))
                continue
            try:
                meta = fix_belly(src_gltf, donor)
            except Exception as e:
                report.append((stem, 'FAIL', 'fix: ' + repr(e)))
                continue
            if meta['unmatched']:
                report.append((stem, 'SKIP', f'unmatched joints {meta["unmatched"][:4]}'))
                continue
            ok, log = divine(src_gltf, fixed_gr2)
            if not ok:
                report.append((stem, 'FAIL', 'divine glTF->GR2: ' + log[-200:]))
                continue
            ok2, log2 = divine(fixed_gr2, ver_gltf)
            if not ok2:
                report.append((stem, 'FAIL', 'divine verify convert: ' + log2[-200:]))
                continue
            good, why = verify(ver_gltf, meta, donor)
            if not good:
                report.append((stem, 'FAIL', 'verify: ' + why))
                continue
            shutil.copyfile(fixed_gr2, mod_gr2)
            report.append((stem, 'OK', why))
    bad = [r for r in report if r[1] != 'OK']
    print(f'done: {len(report)} files, {len(bad)} problems')
    for r in report:
        if r[1] != 'OK':
            print(' ', r)
    json.dump(report, open(os.path.join(WORK, 'report.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
