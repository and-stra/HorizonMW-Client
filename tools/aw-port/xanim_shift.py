# shift a viewmodel xanim - moved from _migration\archive\mwx-debug\aw-weapons\W1.2\xanim_shift.py on 27 Nov 2026.
#!/usr/bin/env python3
"""Shift the tag_ads translation of one H1 .xab by delta along Z.

The H1 .xab stores a normal-translation channel as min/size floats plus
compressed byte offsets (value = size * byte + min).  Adding delta to the
Z minimum moves every key of that channel by delta without recompressing.

Usage: xanim_shift.py <in.xab> <out.xab> <delta_z>
"""
import struct
import sys

K_ARRAY = 8
K_STRING = 6
K_OFFSET = 9

class Stream:
    def __init__(self, data):
        self.d = data
        self.p = 0
    def u8(self):
        v = self.d[self.p]; self.p += 1; return v
    def u16(self):
        v = struct.unpack_from('<H', self.d, self.p)[0]; self.p += 2; return v
    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4; return v
    def f32(self):
        v = struct.unpack_from('<f', self.d, self.p)[0]; self.p += 4; return v
    def cstr(self):
        e = self.d.index(b'\0', self.p)
        s = self.d[self.p:e].decode('latin1')
        self.p = e + 1
        return s
    def array(self, elem_size=1):
        t = self.u8()
        if t == K_OFFSET:
            idx = self.u32(); sub = self.u32()
            raise RuntimeError(f'offset array {idx}/{sub} not supported')
        if t != K_ARRAY:
            raise RuntimeError(f'expected array, got tag {t}')
        existing = self.u8()
        if not existing:
            return None, None
        count = self.u32()
        start = self.p
        self.p += count * elem_size
        return start, count
    def string(self):
        t = self.u8()
        if t == K_OFFSET:
            idx = self.u32(); sub = self.u32()
            raise RuntimeError(f'offset string {idx}/{sub} not supported')
        if t != K_STRING:
            raise RuntimeError(f'expected string, got tag {t}')
        existing = self.u8()
        if not existing:
            return ''
        return self.cstr()

def main():
    src, dst, delta_s = sys.argv[1], sys.argv[2], sys.argv[3]
    delta = float(delta_s)
    data = bytearray(open(src, 'rb').read())
    s = Stream(bytes(data))
    start, count = s.array(0xD8)
    if count != 1:
        raise SystemExit(f'unexpected header array count {count}')
    hdr_off = start
    hdr = s.d[hdr_off:hdr_off + 0xD8]
    if len(hdr) != 0xD8:
        raise SystemExit('short header')
    data_byte_count, data_short_count, data_int_count, numframes = struct.unpack_from('<HHHH', hdr, 8)
    bone_count = hdr[17 + 9]
    notify_count = hdr[29]
    framerate = struct.unpack_from('<f', hdr, 48)[0]
    name = s.string()
    bones = [s.string() for _ in range(bone_count)]
    arrays = {}
    for key, elem in (('dataBytes', 1), ('dataShorts', 2), ('dataInts', 4),
                      ('randomDataShorts', 2), ('randomDataBytes', 1),
                      ('randomDataInts', 4)):
        st, cnt = s.array(elem)
        arrays[key] = (st, cnt)
    # indices array
    if s.p < len(s.d) and s.d[s.p] in (K_ARRAY, K_OFFSET):
        st, cnt = s.array(1)
        arrays['indices'] = (st, cnt)
    print(f'file={src}')
    print(f'name={name!r} bones={bones} frames={numframes} rate={framerate}')
    print(f'counts bytes={data_byte_count} shorts={data_short_count} ints={data_int_count} '
          f'notifies={notify_count}')
    for k, (st, cnt) in arrays.items():
        print(f'  {k}: start={st} count={cnt}')
    st, cnt = arrays['dataInts']
    if st is None or cnt != 6:
        raise SystemExit(f'expected a single 6-float dataInts min/size block, got {cnt}')
    vals = list(struct.unpack_from('<6f', data, st))
    print('min/size =', vals)
    vals[2] += delta
    struct.pack_into('<6f', data, st, *vals)
    print(f'new min/size = {vals} (delta z={delta})')
    open(dst, 'wb').write(data)
    print('wrote', dst)

if __name__ == '__main__':
    main()
