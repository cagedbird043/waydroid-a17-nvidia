#!/usr/bin/env python3
"""Extract the certificate accepted by KernelSU kernel/manager/apk_sign.c."""
import hashlib
import pathlib
import struct
import sys


def certificate(path):
    data = pathlib.Path(path).read_bytes()
    total = len(data)

    def read(pos, size, end):
        if pos < 0 or pos > end or size > end - pos:
            raise ValueError('out-of-bounds read')
        return data[pos:pos + size], pos + size

    def number(pos, fmt, end):
        raw, pos = read(pos, struct.calcsize(fmt), end)
        return struct.unpack(fmt, raw)[0], pos

    def prefixed(pos, end):
        size, pos = number(pos, '<I', end)
        if size > 0x7fffffff or size > end - pos:
            raise ValueError('invalid length prefix')
        return pos, pos + size

    for comment in range(65536):
        pos = total - comment - 2
        size, _ = number(pos, '<H', total)
        if size == comment:
            magic, _ = number(pos - 20, '<I', total)
            if magic == 0x06054b50:
                eocd = pos - 20
                break
    else:
        raise ValueError('missing EOCD')
    if eocd >= 20 and number(eocd - 20, '<I', total)[0] == 0x07064b50:
        raise ValueError('ZIP64 rejected')
    cd_size, pos = number(eocd + 12, '<I', total)
    cd, _ = number(pos, '<I', total)
    if cd > eocd or cd_size != eocd - cd or cd < 32:
        raise ValueError('invalid central directory')
    pairs_end = cd - 24
    block_size, pos = number(pairs_end, '<Q', cd)
    magic, _ = read(pos, 16, cd)
    if magic != b'APK Sig Block 42' or not 24 <= block_size <= min(0x7fffffff - 8, cd - 8):
        raise ValueError('invalid signing block')
    head_size, pos = number(cd - block_size - 8, '<Q', pairs_end)
    if head_size != block_size:
        raise ValueError('mismatched signing block sizes')
    certificates = []
    while pos < pairs_end:
        size, pos = number(pos, '<Q', pairs_end)
        if not 4 <= size <= min(0x7fffffff, pairs_end - pos):
            raise ValueError('invalid pair')
        pair_end = pos + size
        ident, pos = number(pos, '<I', pair_end)
        if ident == 0x7109871a:
            pos, signers_end = prefixed(pos, pair_end)
            pos, signer_end = prefixed(pos, signers_end)
            pos, signed_data_end = prefixed(pos, signer_end)
            pos, digests_end = prefixed(pos, signed_data_end)
            pos, certs_end = prefixed(digests_end, signed_data_end)
            size, pos = number(pos, '<I', certs_end)
            if size > min(1024, certs_end - pos):
                raise ValueError('certificate exceeds kernel limit')
            cert, _ = read(pos, size, certs_end)
            certificates.append((size, hashlib.sha256(cert).hexdigest()))
        elif ident != 0x42726577:
            raise ValueError(f'kernel rejects signature block ID {ident:#x}')
        pos = pair_end
    if len(certificates) != 1:
        raise ValueError('kernel requires exactly one v2 block')
    return certificates[0]


if __name__ == '__main__':
    for path in sys.argv[1:]:
        size, digest = certificate(path)
        print(f'{path}\nKSU_EXPECTED_SIZE=0x{size:04x}\nKSU_EXPECTED_HASH={digest}')
