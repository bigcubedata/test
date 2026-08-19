//! 2C02 NTSC 调色板(64 色)与三路强调位派生的 512 色表。

use std::sync::OnceLock;

/// nesdev 社区标准 2C02 NTSC 参考调色板。
const BASE: [u32; 64] = [
    0x666666, 0x002A88, 0x1412A7, 0x3B00A4, 0x5C007E, 0x6E0040, 0x6C0600, 0x561D00,
    0x333500, 0x0B4800, 0x005200, 0x004F08, 0x00404D, 0x000000, 0x000000, 0x000000,
    0xADADAD, 0x155FD9, 0x4240FF, 0x7527FE, 0xA01ACC, 0xB71E7B, 0xB53120, 0x994E00,
    0x6B6D00, 0x388700, 0x0C9300, 0x008F32, 0x007C8D, 0x000000, 0x000000, 0x000000,
    0xFFFEFF, 0x64B0FF, 0x9290FF, 0xC676FF, 0xF36AFF, 0xFE6ECC, 0xFE8170, 0xEA9E22,
    0xBCBE00, 0x88D800, 0x5CE430, 0x45E082, 0x48CDDE, 0x4F4F4F, 0x000000, 0x000000,
    0xFFFEFF, 0xC0DFFF, 0xD3D2FF, 0xE8C8FF, 0xFBC2FF, 0xFEC4EA, 0xFECCC5, 0xF7D8A5,
    0xE4E594, 0xCFEF96, 0xBDF4AB, 0xB3F3CC, 0xB5EBF2, 0xB8B8B8, 0x000000, 0x000000,
];

fn table() -> &'static [[u8; 3]; 512] {
    static TABLE: OnceLock<Box<[[u8; 3]; 512]>> = OnceLock::new();
    TABLE.get_or_init(|| {
        let mut t = Box::new([[0u8; 3]; 512]);
        for emph in 0..8u16 {
            for i in 0..64u16 {
                let c = BASE[i as usize];
                let mut r = ((c >> 16) & 0xFF) as f32;
                let mut g = ((c >> 8) & 0xFF) as f32;
                let mut b = (c & 0xFF) as f32;
                // 强调位使另外两个通道衰减(近似硬件)
                const ATT: f32 = 0.746;
                if emph & 1 != 0 {
                    g *= ATT;
                    b *= ATT;
                }
                if emph & 2 != 0 {
                    r *= ATT;
                    b *= ATT;
                }
                if emph & 4 != 0 {
                    r *= ATT;
                    g *= ATT;
                }
                t[(emph * 64 + i) as usize] = [r as u8, g as u8, b as u8];
            }
        }
        t
    })
}

/// `idx9` = 强调位(bit6-8)| 调色板索引(bit0-5)。
pub fn rgb_for(idx9: u16) -> [u8; 3] {
    table()[(idx9 & 0x1FF) as usize]
}
