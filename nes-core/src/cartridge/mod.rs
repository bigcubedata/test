//! 卡带:iNES / NES 2.0 解析与 Mapper 分派。
//!
//! Mapper 只做地址翻译与寄存器逻辑,不持有 ROM 数据;`Cartridge` 负责真正的
//! 存储访问。这样 mapper 可以整体 serde,ROM 大块数据不进即时存档。

mod mapper;
mod mmc1;
mod mmc3;

pub use mapper::{ChrTarget, Mapper, MapperImpl, PrgTarget, PrgWrite};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Mirroring {
    Horizontal,
    Vertical,
    SingleA,
    SingleB,
    FourScreen,
}

#[derive(Debug)]
pub enum RomError {
    BadMagic,
    Truncated,
    UnsupportedMapper(u16),
}

impl std::fmt::Display for RomError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RomError::BadMagic => write!(f, "不是 iNES/NES 2.0 文件(缺少 NES<1A> 魔数)"),
            RomError::Truncated => write!(f, "文件长度与头声明不符(被截断?)"),
            RomError::UnsupportedMapper(n) => write!(f, "mapper {n} 尚未支持"),
        }
    }
}

impl std::error::Error for RomError {}

/// 解析后的头信息,供外壳展示与调试。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RomInfo {
    pub mapper: u16,
    pub submapper: u8,
    pub prg_rom_len: usize,
    pub chr_rom_len: usize,
    pub chr_ram_len: usize,
    pub prg_ram_len: usize,
    pub battery: bool,
    pub four_screen: bool,
    pub nes2: bool,
    pub pal_hint: bool,
}

#[derive(Serialize, Deserialize)]
pub struct Cartridge {
    pub info: RomInfo,
    // ROM 大块数据不进存档:load_state 时从当前实例回填。
    #[serde(skip)]
    pub prg_rom: Vec<u8>,
    #[serde(skip)]
    pub chr_rom: Vec<u8>,
    /// 校验存档与当前 ROM 匹配。
    pub rom_hash: u64,
    pub chr_ram: Vec<u8>,
    pub prg_ram: Vec<u8>,
    /// 电池档自上次取走后是否被写过。
    pub prg_ram_dirty: bool,
    /// 四屏卡的额外 2KB VRAM。
    pub ext_vram: Vec<u8>,
    pub mapper: Mapper,
}

fn fnv1a(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

impl Cartridge {
    pub fn parse(rom: &[u8]) -> Result<Cartridge, RomError> {
        if rom.len() < 16 || &rom[0..4] != b"NES\x1a" {
            return Err(RomError::BadMagic);
        }
        let nes2 = rom[7] & 0x0C == 0x08;
        let mut prg_units = rom[4] as usize; // 16KB 单位
        let mut chr_units = rom[5] as usize; // 8KB 单位
        let f6 = rom[6];
        let f7 = rom[7];
        let mut mapper = ((f6 >> 4) as u16) | ((f7 & 0xF0) as u16);
        let mut submapper = 0u8;
        let mut prg_ram_len = 8 * 1024;
        let mut chr_ram_len = 0usize;
        let mut pal_hint = false;
        if nes2 {
            mapper |= ((rom[8] & 0x0F) as u16) << 8;
            submapper = rom[8] >> 4;
            prg_units |= ((rom[9] & 0x0F) as usize) << 8;
            chr_units |= ((rom[9] >> 4) as usize) << 8;
            let ram_shift = rom[10] & 0x0F;
            let nvram_shift = rom[10] >> 4;
            prg_ram_len = 0;
            if ram_shift > 0 {
                prg_ram_len += 64usize << ram_shift;
            }
            if nvram_shift > 0 {
                prg_ram_len += 64usize << nvram_shift;
            }
            if prg_ram_len == 0 {
                prg_ram_len = 8 * 1024; // 容错:不少 NES2.0 头忘填
            }
            let cshift = rom[11] & 0x0F;
            if cshift > 0 {
                chr_ram_len = 64usize << cshift;
            }
            pal_hint = rom[12] & 0x03 == 1;
        } else {
            // 老 iNES 脏头:字节 12-15 有垃圾时高 nibble 不可信
            if rom[12] | rom[13] | rom[14] | rom[15] != 0 {
                mapper &= 0x0F;
            }
        }
        let battery = f6 & 0x02 != 0;
        let trainer = f6 & 0x04 != 0;
        let four_screen = f6 & 0x08 != 0;
        let mut mirroring = if four_screen {
            Mirroring::FourScreen
        } else if f6 & 0x01 != 0 {
            Mirroring::Vertical
        } else {
            Mirroring::Horizontal
        };
        // AxROM 之类单屏卡的头镜像位无意义,由 mapper 自己接管
        let mut offset = 16 + if trainer { 512 } else { 0 };
        let prg_len = prg_units * 16 * 1024;
        let chr_len = chr_units * 8 * 1024;
        if rom.len() < offset + prg_len + chr_len {
            return Err(RomError::Truncated);
        }
        let prg_rom = rom[offset..offset + prg_len].to_vec();
        offset += prg_len;
        let chr_rom = rom[offset..offset + chr_len].to_vec();
        if chr_len == 0 && chr_ram_len == 0 {
            chr_ram_len = 8 * 1024;
        }
        let rom_hash = fnv1a(rom);
        if mirroring == Mirroring::FourScreen && mapper == 7 {
            mirroring = Mirroring::SingleA;
        }
        let mapper_impl = Mapper::new(mapper, submapper, prg_len, chr_len.max(chr_ram_len), mirroring)?;
        let info = RomInfo {
            mapper,
            submapper,
            prg_rom_len: prg_len,
            chr_rom_len: chr_len,
            chr_ram_len,
            prg_ram_len,
            battery,
            four_screen,
            nes2,
            pal_hint,
        };
        Ok(Cartridge {
            info,
            prg_rom,
            chr_rom,
            rom_hash,
            chr_ram: vec![0; chr_ram_len],
            prg_ram: vec![0; prg_ram_len],
            prg_ram_dirty: false,
            ext_vram: if four_screen { vec![0; 2048] } else { Vec::new() },
            mapper: mapper_impl,
        })
    }

    /// CPU $4020-$FFFF 读。None = open bus。
    pub fn cpu_read(&mut self, addr: u16) -> Option<u8> {
        match self.mapper.cpu_map(addr) {
            PrgTarget::Rom(i) => Some(self.prg_rom[i % self.prg_rom.len().max(1)]),
            PrgTarget::Ram(i) => {
                if self.prg_ram.is_empty() {
                    None
                } else {
                    let len = self.prg_ram.len();
                    Some(self.prg_ram[i % len])
                }
            }
            PrgTarget::Value(v) => Some(v),
            PrgTarget::None => None,
        }
    }

    /// 侧效应无关的读(调试/trace 用)。
    pub fn cpu_peek(&self, addr: u16) -> Option<u8> {
        match self.mapper.cpu_peek(addr) {
            PrgTarget::Rom(i) => Some(self.prg_rom[i % self.prg_rom.len().max(1)]),
            PrgTarget::Ram(i) => {
                if self.prg_ram.is_empty() {
                    None
                } else {
                    let len = self.prg_ram.len();
                    Some(self.prg_ram[i % len])
                }
            }
            PrgTarget::Value(v) => Some(v),
            PrgTarget::None => None,
        }
    }

    pub fn cpu_write(&mut self, addr: u16, val: u8) {
        // 总线冲突卡需要"当前映射到该地址的 ROM 字节"
        let rom_at = if addr >= 0x8000 {
            self.cpu_peek(addr).unwrap_or(val)
        } else {
            val
        };
        match self.mapper.cpu_write(addr, val, rom_at) {
            PrgWrite::Handled => {}
            PrgWrite::Ram(i) => {
                if !self.prg_ram.is_empty() {
                    let len = self.prg_ram.len();
                    self.prg_ram[i % len] = val;
                    self.prg_ram_dirty = true;
                }
            }
        }
    }

    /// 归一化:mapper 返回 Rom 但卡上只有 CHR RAM 时落到 RAM。
    fn chr_resolve(&mut self, addr: u16) -> (bool, usize) {
        match self.mapper.ppu_map(addr) {
            ChrTarget::Rom(i) => {
                if self.chr_rom.is_empty() {
                    (true, i)
                } else {
                    (false, i)
                }
            }
            ChrTarget::Ram(i) => (true, i),
        }
    }

    /// PPU $0000-$1FFF 读(pattern 区)。
    pub fn chr_read(&mut self, addr: u16) -> u8 {
        let (is_ram, i) = self.chr_resolve(addr);
        let mem = if is_ram { &self.chr_ram } else { &self.chr_rom };
        if mem.is_empty() {
            0
        } else {
            mem[i % mem.len()]
        }
    }

    pub fn chr_write(&mut self, addr: u16, val: u8) {
        let (is_ram, i) = self.chr_resolve(addr);
        if is_ram && !self.chr_ram.is_empty() {
            let len = self.chr_ram.len();
            self.chr_ram[i % len] = val;
        }
    }

    pub fn mirroring(&self) -> Mirroring {
        self.mapper.mirroring()
    }
}
