let m_src = null;
let m_src_offset = 0;
let m_dst = null;
let m_dst_offset = 0;
let m_size = 0;
let m_bits = 0;
let m_crc = 0;

function read_dword(a, b) {
    let c = a.charCodeAt(b) << 24;
    c |= a.charCodeAt(b + 1) << 16;
    c |= a.charCodeAt(b + 2) << 8;
    return c |= a.charCodeAt(b + 3)
}

function next_bit() {
    let a = m_bits & 1;
    m_bits >>>= 1;
    0 == m_bits && (
        m_bits = read_dword(m_src, m_src_offset),
        m_src_offset -= 4,
        m_crc ^= m_bits,
        a = m_bits & 1,
        m_bits = - 2147483648 | m_bits >>> 1
    );
    return a
}

function read_bits(a) {
    let b;
    for (b = 0, c = 0; c < a; c += 1)
        b |= next_bit() << a - 1 - c;
    return b
}

function copy_literal(a, b) {
    a = read_bits(a) + b + 1;
    for (b = 0; b < a; b += 1) {
        m_dst[m_dst_offset] = read_bits(8);
        --m_dst_offset;
    }
    m_size -= a
}

function copy_reference(a, b) {
    a = read_bits(a);
    for (let c = 0; c < b; c += 1) {
        m_dst[m_dst_offset] = m_dst[m_dst_offset + a];
        --m_dst_offset;
    }
    m_size -= b
}

function uncompress(a) {
    m_src = a;
    m_src_offset = a.length - 4;
    m_size = read_dword(m_src, m_src_offset);
    m_src_offset -= 4;
    m_crc = read_dword(m_src, m_src_offset);
    m_src_offset -= 4;
    m_bits = read_dword(m_src, m_src_offset);
    m_src_offset -= 4;
    m_crc ^= m_bits;
    m_dst = new Uint8Array(m_size);
    for (m_dst_offset = m_size - 1; 0 < m_size;) {
        if (next_bit()) {
            switch (read_bits(2)) {
                case 3:
                    copy_literal(8, 8);
                    break;
                case 2:
                    copy_reference(12, read_bits(8) + 1);
                    break;
                case 1:
                    copy_reference(10, 4);
                    break;
                case 0:
                    copy_reference(9, 3)
            }
        } else {
            next_bit() ? copy_reference(8, 2) : copy_literal(3, 0);
        }
    }
    return m_dst
}

exports.uncompress = uncompress;
