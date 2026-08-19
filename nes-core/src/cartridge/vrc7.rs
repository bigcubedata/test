//! Mapper 85:VRC7(Lagrange Point / Tiny Toon 2)。
//! 音源为 YM2413(OPLL)亚种:6 通道 2-op FM,固定音色 ROM + 1 自定义音色。
//!
//! 合成器为结构等价的简化实现(正弦查表 + 指数包络近似,49716Hz 内部采样),
//! 非逐位精确,但音色/包络/颤音行为对齐可听效果。音色表取社区芯片提取值。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::vrc::VrcIrq;
use super::Mirroring;
use serde::{Deserialize, Serialize};

/// VRC7 内置音色(社区芯片提取;patch 0 为自定义)。
const PATCHES: [[u8; 8]; 16] = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0x03, 0x21, 0x05, 0x06, 0xE8, 0x81, 0x42, 0x27],
    [0x13, 0x41, 0x14, 0x0D, 0xD8, 0xF6, 0x23, 0x12],
    [0x11, 0x11, 0x08, 0x08, 0xFA, 0xB2, 0x20, 0x12],
    [0x31, 0x61, 0x0C, 0x07, 0xA8, 0x64, 0x61, 0x27],
    [0x32, 0x21, 0x1E, 0x06, 0xE1, 0x76, 0x01, 0x28],
    [0x02, 0x01, 0x06, 0x00, 0xA3, 0xE2, 0xF4, 0xF4],
    [0x21, 0x61, 0x1D, 0x07, 0x82, 0x81, 0x11, 0x07],
    [0x23, 0x21, 0x22, 0x17, 0xA2, 0x72, 0x01, 0x17],
    [0x35, 0x11, 0x25, 0x00, 0x40, 0x73, 0x72, 0x01],
    [0xB5, 0x01, 0x0F, 0x0F, 0xA8, 0xA5, 0x51, 0x02],
    [0x17, 0xC1, 0x24, 0x07, 0xF8, 0xF8, 0x22, 0x12],
    [0x71, 0x23, 0x11, 0x06, 0x65, 0x74, 0x18, 0x16],
    [0x01, 0x02, 0xD3, 0x05, 0xC9, 0x95, 0x03, 0x02],
    [0x61, 0x63, 0x0C, 0x00, 0x94, 0xC0, 0x33, 0xF6],
    [0x21, 0x72, 0x0D, 0x00, 0xC1, 0xD5, 0x56, 0x06],
];

const MULTI: [f32; 16] = [
    0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 10.0, 12.0, 12.0, 15.0, 15.0,
];

#[derive(Clone, Copy, PartialEq, Serialize, Deserialize)]
enum EnvPhase {
    Idle,
    Attack,
    Decay,
    Sustain,
    Release,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
struct Op {
    phase: f32,
    env: f32, // 衰减量 0(最响)..1(静音)
    phase_env: EnvPhase,
    fb_prev: f32,
}

impl Default for Op {
    fn default() -> Op {
        Op {
            phase: 0.0,
            env: 1.0,
            phase_env: EnvPhase::Idle,
            fb_prev: 0.0,
        }
    }
}

#[derive(Default, Clone, Copy, Serialize, Deserialize)]
struct Channel {
    fnum: u16,
    block: u8,
    key_on: bool,
    sustain_on: bool,
    instrument: u8,
    volume: u8,
    ops: [Op; 2],
}

#[derive(Serialize, Deserialize)]
pub struct Vrc7 {
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    prg: [u8; 3],
    chr: [u8; 8],
    mirroring: Mirroring,
    irq: VrcIrq,
    // 音源
    audio_addr: u8,
    custom: [u8; 8],
    channels: [Channel; 6],
    audio_enabled: bool,
    divider: u8, // 每 36 CPU 周期一个 FM 采样
    lfo_phase: f32,
    last_out: f32,
}

impl Vrc7 {
    pub fn new(prg_len: usize, chr_len: usize) -> Vrc7 {
        Vrc7 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram: chr_len == 0,
            prg: [0; 3],
            chr: [0; 8],
            mirroring: Mirroring::Vertical,
            irq: VrcIrq::default(),
            audio_addr: 0,
            custom: [0; 8],
            channels: [Channel::default(); 6],
            audio_enabled: true,
            divider: 0,
            lfo_phase: 0.0,
            last_out: 0.0,
        }
    }

    fn patch(&self, idx: u8) -> [u8; 8] {
        if idx == 0 {
            self.custom
        } else {
            PATCHES[(idx & 0x0F) as usize]
        }
    }

    fn audio_write(&mut self, val: u8) {
        let a = self.audio_addr as usize;
        match a {
            0x00..=0x07 => self.custom[a] = val,
            0x10..=0x15 => {
                let ch = &mut self.channels[a - 0x10];
                ch.fnum = ch.fnum & 0x100 | val as u16;
            }
            0x20..=0x25 => {
                let ch = &mut self.channels[a - 0x20];
                ch.fnum = ch.fnum & 0xFF | ((val & 1) as u16) << 8;
                ch.block = val >> 1 & 7;
                ch.sustain_on = val & 0x20 != 0;
                let key = val & 0x10 != 0;
                if key && !ch.key_on {
                    for op in ch.ops.iter_mut() {
                        op.phase_env = EnvPhase::Attack;
                        op.phase = 0.0;
                    }
                }
                if !key && ch.key_on {
                    for op in ch.ops.iter_mut() {
                        op.phase_env = EnvPhase::Release;
                    }
                }
                ch.key_on = key;
            }
            0x30..=0x35 => {
                let ch = &mut self.channels[a - 0x30];
                ch.instrument = val >> 4;
                ch.volume = val & 0x0F;
            }
            _ => {}
        }
    }

    /// 速率值 → 每采样包络步进(近似指数时间)。
    fn env_rate(r: u8, fast: f32) -> f32 {
        if r == 0 {
            return 0.0;
        }
        fast * (2f32).powi(r as i32) / 32768.0
    }

    fn fm_sample(&mut self) -> f32 {
        self.lfo_phase += 6.4 / 49716.0;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= 1.0;
        }
        let vib = (self.lfo_phase * std::f32::consts::TAU).sin();
        let mut sum = 0.0f32;
        for ci in 0..6 {
            let ch = self.channels[ci];
            if ch.ops[1].phase_env == EnvPhase::Idle {
                continue;
            }
            let patch = self.patch(ch.instrument);
            let base_freq =
                ch.fnum as f32 * (1 << ch.block) as f32 * 49716.0 / (1 << 19) as f32;
            let mut out_mod = 0.0;
            for oi in 0..2 {
                let (am, _pm, _ksr, multi) = (
                    patch[oi] & 0x80 != 0,
                    patch[oi] & 0x40 != 0,
                    patch[oi] & 0x10 != 0,
                    patch[oi] & 0x0F,
                );
                let vibrato = patch[oi] & 0x40 != 0;
                let sustained = patch[oi] & 0x20 != 0;
                let freq = base_freq * MULTI[multi as usize]
                    * if vibrato { 1.0 + vib * 0.008 } else { 1.0 };
                let op = &mut self.channels[ci].ops[oi];
                op.phase += freq / 49716.0;
                if op.phase >= 1.0 {
                    op.phase -= op.phase.floor();
                }
                // 包络推进
                let ar = patch[4 + oi] >> 4;
                let dr = patch[4 + oi] & 0x0F;
                let sl = patch[6 + oi] >> 4;
                let rr = patch[6 + oi] & 0x0F;
                match op.phase_env {
                    EnvPhase::Attack => {
                        op.env -= Self::env_rate(ar, 12.0) * op.env.max(0.05);
                        if op.env <= 0.001 {
                            op.env = 0.0;
                            op.phase_env = EnvPhase::Decay;
                        }
                    }
                    EnvPhase::Decay => {
                        let target = sl as f32 / 15.0 * 0.75;
                        op.env += Self::env_rate(dr, 1.0);
                        if op.env >= target {
                            op.env = target;
                            op.phase_env = EnvPhase::Sustain;
                        }
                    }
                    EnvPhase::Sustain => {
                        if !sustained {
                            op.env += Self::env_rate(rr.max(1), 0.5);
                        }
                    }
                    EnvPhase::Release => {
                        let r = if self.channels[ci].sustain_on { 5 } else { rr.max(2) };
                        op.env += Self::env_rate(r, 1.0);
                    }
                    EnvPhase::Idle => {}
                }
                let op = &mut self.channels[ci].ops[oi];
                if op.env >= 1.0 {
                    op.env = 1.0;
                    op.phase_env = EnvPhase::Idle;
                }
                let amp = (1.0 - op.env).max(0.0).powi(2);
                let tremolo = if am { 1.0 - 0.06 * (1.0 + vib) } else { 1.0 };
                if oi == 0 {
                    // modulator,带反馈
                    let fb_bits = patch[3] & 7;
                    let fb = if fb_bits == 0 {
                        0.0
                    } else {
                        (2f32).powi(fb_bits as i32 - 7) * 4.0
                    };
                    let x = (op.phase * std::f32::consts::TAU + op.fb_prev * fb).sin();
                    out_mod = x * amp * tremolo;
                    op.fb_prev = out_mod;
                } else {
                    // carrier:音量 3dB/级
                    let vol = (10f32).powf(-(self.channels[ci].volume as f32) * 3.0 / 20.0);
                    let x = (op.phase * std::f32::consts::TAU + out_mod * 4.0).sin();
                    sum += x * amp * tremolo * vol;
                }
            }
        }
        sum / 6.0
    }
}

impl MapperImpl for Vrc7 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x2000).max(1);
        let off = addr as usize & 0x1FFF;
        let bank = match (addr >> 13) & 3 {
            0 => (self.prg[0] & 0x3F) as usize % banks,
            1 => (self.prg[1] & 0x3F) as usize % banks,
            2 => (self.prg[2] & 0x3F) as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgWrite::Handled;
        }
        // VRC7a 用 $x010,VRC7b 用 $x008:两者都接受
        let sub = (addr & 0x18 != 0) as usize;
        match (addr & 0xF000, sub) {
            (0x8000, 0) => self.prg[0] = val,
            (0x8000, 1) => self.prg[1] = val,
            (0x9000, 0) => self.prg[2] = val,
            (0x9000, 1) => {
                if addr & 0x30 == 0x10 {
                    self.audio_addr = val;
                } else {
                    self.audio_write(val);
                }
            }
            (0xA000..=0xD000, s) => {
                let slot = (((addr >> 12) - 0xA) * 2) as usize + s;
                self.chr[slot & 7] = val;
            }
            (0xE000, 0) => {
                self.mirroring = match val & 3 {
                    0 => Mirroring::Vertical,
                    1 => Mirroring::Horizontal,
                    2 => Mirroring::SingleA,
                    _ => Mirroring::SingleB,
                };
                self.audio_enabled = val & 0x40 == 0;
            }
            (0xE000, 1) => self.irq.write_latch(val),
            (0xF000, 0) => self.irq.write_control(val),
            (0xF000, 1) => self.irq.ack(),
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 10) as usize & 7;
        let banks = (self.chr_len / 0x400).max(1);
        let i = (self.chr[slot] as usize % banks) * 0x400 + (addr as usize & 0x3FF);
        if self.chr_is_ram {
            ChrTarget::Ram(i)
        } else {
            ChrTarget::Rom(i)
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn cpu_tick(&mut self) {
        self.irq.tick();
        self.divider += 1;
        if self.divider >= 36 {
            self.divider = 0;
            self.last_out = if self.audio_enabled {
                self.fm_sample()
            } else {
                0.0
            };
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq.pending
    }

    fn audio(&mut self) -> f32 {
        self.last_out * 0.5
    }
}
