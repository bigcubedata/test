//! 2A03 APU:Pulse×2 / Triangle / Noise / DMC + 帧计数器 + 非线性混音。
//!
//! 每个 CPU 周期推进一次;Pulse/Noise 的分频在内部按 2 CPU 周期一步。
//! 输出:每周期产生原始样本 → 分数步长箱式抽取到目标采样率 → 高/低通滤波。
//! 重采样比可被外壳微调(音频主时钟的动态速率控制)。

use crate::nes::Region;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

const LENGTH_TABLE: [u8; 32] = [
    10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
];

const NOISE_PERIODS: [u16; 16] = [
    4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
];

const NOISE_PERIODS_PAL: [u16; 16] = [
    4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708, 944, 1890, 3778,
];

const DMC_RATES: [u16; 16] = [
    428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54,
];

const DMC_RATES_PAL: [u16; 16] = [
    398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50,
];

const DUTY: [[u8; 8]; 4] = [
    [0, 1, 0, 0, 0, 0, 0, 0],
    [0, 1, 1, 0, 0, 0, 0, 0],
    [0, 1, 1, 1, 1, 0, 0, 0],
    [1, 0, 0, 1, 1, 1, 1, 1],
];

const TRI_SEQ: [u8; 32] = [
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
    12, 13, 14, 15,
];

fn pulse_table() -> &'static [f32; 31] {
    static T: OnceLock<[f32; 31]> = OnceLock::new();
    T.get_or_init(|| {
        let mut t = [0f32; 31];
        for (i, v) in t.iter_mut().enumerate().skip(1) {
            *v = 95.52 / (8128.0 / i as f32 + 100.0);
        }
        t
    })
}

fn tnd_table() -> &'static [f32; 203] {
    static T: OnceLock<[f32; 203]> = OnceLock::new();
    T.get_or_init(|| {
        let mut t = [0f32; 203];
        for (i, v) in t.iter_mut().enumerate().skip(1) {
            *v = 163.67 / (24329.0 / i as f32 + 100.0);
        }
        t
    })
}

// ---------------- 公共小部件 ----------------

#[derive(Default, Serialize, Deserialize)]
struct Envelope {
    start: bool,
    divider: u8,
    decay: u8,
    volume: u8, // 参数(音量 / 分频周期)
    constant: bool,
    looped: bool,
}

impl Envelope {
    fn quarter(&mut self) {
        if self.start {
            self.start = false;
            self.decay = 15;
            self.divider = self.volume;
        } else if self.divider == 0 {
            self.divider = self.volume;
            if self.decay > 0 {
                self.decay -= 1;
            } else if self.looped {
                self.decay = 15;
            }
        } else {
            self.divider -= 1;
        }
    }
    fn output(&self) -> u8 {
        if self.constant {
            self.volume
        } else {
            self.decay
        }
    }
}

// ---------------- Pulse ----------------

#[derive(Default, Serialize, Deserialize)]
struct Pulse {
    is_pulse2: bool,
    enabled: bool,
    duty: u8,
    seq_step: u8,
    timer_period: u16,
    timer: u16,
    length: u8,
    halt: bool,
    env: Envelope,
    sweep_enabled: bool,
    sweep_period: u8,
    sweep_negate: bool,
    sweep_shift: u8,
    sweep_divider: u8,
    sweep_reload: bool,
}

impl Pulse {
    fn sweep_target(&self) -> i32 {
        let change = (self.timer_period >> self.sweep_shift) as i32;
        if self.sweep_negate {
            // pulse1 一补(多减 1),pulse2 二补
            self.timer_period as i32 - change - if self.is_pulse2 { 0 } else { 1 }
        } else {
            self.timer_period as i32 + change
        }
    }

    fn muted(&self) -> bool {
        self.timer_period < 8 || (!self.sweep_negate && self.sweep_target() > 0x7FF)
    }

    fn half(&mut self) {
        // sweep
        if self.sweep_divider == 0 && self.sweep_enabled && self.sweep_shift > 0 && !self.muted() {
            let t = self.sweep_target();
            if t >= 0 {
                self.timer_period = t as u16 & 0x7FF;
            }
        }
        if self.sweep_divider == 0 || self.sweep_reload {
            self.sweep_divider = self.sweep_period;
            self.sweep_reload = false;
        } else {
            self.sweep_divider -= 1;
        }
        // length
        if !self.halt && self.length > 0 {
            self.length -= 1;
        }
    }

    /// 每 2 个 CPU 周期一步。
    fn tick_timer(&mut self) {
        if self.timer == 0 {
            self.timer = self.timer_period;
            self.seq_step = (self.seq_step + 1) & 7;
        } else {
            self.timer -= 1;
        }
    }

    fn output(&self) -> u8 {
        if !self.enabled
            || self.length == 0
            || self.muted()
            || DUTY[self.duty as usize][self.seq_step as usize] == 0
        {
            0
        } else {
            self.env.output()
        }
    }
}

// ---------------- Triangle ----------------

#[derive(Default, Serialize, Deserialize)]
struct Triangle {
    enabled: bool,
    timer_period: u16,
    timer: u16,
    length: u8,
    control: bool, // 同时是 length halt 与 linear control
    linear: u8,
    linear_reload_val: u8,
    linear_reload: bool,
    seq_step: u8,
}

impl Triangle {
    fn quarter(&mut self) {
        if self.linear_reload {
            self.linear = self.linear_reload_val;
        } else if self.linear > 0 {
            self.linear -= 1;
        }
        if !self.control {
            self.linear_reload = false;
        }
    }
    fn half(&mut self) {
        if !self.control && self.length > 0 {
            self.length -= 1;
        }
    }
    fn tick_timer(&mut self) {
        if self.timer == 0 {
            self.timer = self.timer_period;
            // 超声频段(period<2)冻结步进,避免混叠尖啸
            if self.length > 0 && self.linear > 0 && self.timer_period >= 2 {
                self.seq_step = (self.seq_step + 1) & 31;
            }
        } else {
            self.timer -= 1;
        }
    }
    fn output(&self) -> u8 {
        TRI_SEQ[self.seq_step as usize]
    }
}

// ---------------- Noise ----------------

#[derive(Serialize, Deserialize)]
struct Noise {
    enabled: bool,
    mode: bool,
    timer_period: u16,
    timer: u16,
    length: u8,
    halt: bool,
    env: Envelope,
    lfsr: u16,
}

impl Default for Noise {
    fn default() -> Noise {
        Noise {
            enabled: false,
            mode: false,
            timer_period: NOISE_PERIODS[0],
            timer: 0,
            length: 0,
            halt: false,
            env: Envelope::default(),
            lfsr: 1,
        }
    }
}

impl Noise {
    fn half(&mut self) {
        if !self.halt && self.length > 0 {
            self.length -= 1;
        }
    }
    fn tick_timer(&mut self) {
        if self.timer == 0 {
            self.timer = self.timer_period;
            let tap = if self.mode { 6 } else { 1 };
            let fb = (self.lfsr ^ self.lfsr >> tap) & 1;
            self.lfsr = self.lfsr >> 1 | fb << 14;
        } else {
            self.timer -= 1;
        }
    }
    fn output(&self) -> u8 {
        if !self.enabled || self.length == 0 || self.lfsr & 1 != 0 {
            0
        } else {
            self.env.output()
        }
    }
}

// ---------------- DMC ----------------

#[derive(Default, Serialize, Deserialize)]
pub struct Dmc {
    pub pal: bool,
    irq_enable: bool,
    pub irq_flag: bool,
    looped: bool,
    rate_index: u8,
    timer: u16,
    output_level: u8,
    addr_start: u16,
    sample_len: u16,
    pub addr_cur: u16,
    pub bytes_remaining: u16,
    pub sample_buffer: Option<u8>,
    shift: u8,
    bits_remaining: u8,
    silence: bool,
    /// CPU 侧需要执行一次取样 DMA
    pub fetch_pending: bool,
}

impl Dmc {
    fn tick_timer(&mut self) {
        if self.timer == 0 {
            let table = if self.pal { &DMC_RATES_PAL } else { &DMC_RATES };
            self.timer = table[self.rate_index as usize] - 1;
            if !self.silence {
                if self.shift & 1 != 0 {
                    if self.output_level <= 125 {
                        self.output_level += 2;
                    }
                } else if self.output_level >= 2 {
                    self.output_level -= 2;
                }
            }
            self.shift >>= 1;
            if self.bits_remaining <= 1 {
                self.bits_remaining = 8;
                match self.sample_buffer.take() {
                    Some(b) => {
                        self.shift = b;
                        self.silence = false;
                        if self.bytes_remaining > 0 {
                            self.fetch_pending = true;
                        }
                    }
                    None => self.silence = true,
                }
            } else {
                self.bits_remaining -= 1;
            }
        } else {
            self.timer -= 1;
        }
    }

    /// DMA 完成后由 CPU 侧回填。
    pub fn dma_finished(&mut self, val: u8) {
        self.sample_buffer = Some(val);
        if self.addr_cur == 0xFFFF {
            self.addr_cur = 0x8000;
        } else {
            self.addr_cur += 1;
        }
        self.bytes_remaining = self.bytes_remaining.saturating_sub(1);
        if self.bytes_remaining == 0 {
            if self.looped {
                self.restart();
            } else if self.irq_enable {
                self.irq_flag = true;
            }
        }
    }

    fn restart(&mut self) {
        self.addr_cur = self.addr_start;
        self.bytes_remaining = self.sample_len;
    }
}

// ---------------- 重采样与滤波 ----------------

#[derive(Serialize, Deserialize)]
struct Resampler {
    cycles_per_sample: f64,
    adjust: f64,
    phase: f64,
    sum: f32,
    count: u32,
    hp1_x: f32,
    hp1_y: f32,
    hp2_x: f32,
    hp2_y: f32,
    lp_y: f32,
    sample_rate: f64,
    cpu_hz: f64,
}

impl Default for Resampler {
    fn default() -> Resampler {
        let mut r = Resampler {
            cycles_per_sample: 0.0,
            adjust: 1.0,
            phase: 0.0,
            sum: 0.0,
            count: 0,
            hp1_x: 0.0,
            hp1_y: 0.0,
            hp2_x: 0.0,
            hp2_y: 0.0,
            lp_y: 0.0,
            sample_rate: 48000.0,
            cpu_hz: 1_789_772.7,
        };
        r.set_rate(48000.0);
        r
    }
}

impl Resampler {
    fn set_rate(&mut self, rate: f64) {
        self.sample_rate = rate;
        self.cycles_per_sample = self.cpu_hz / rate;
    }

    fn coef_hp(&self, cutoff: f64) -> f32 {
        let rc = 1.0 / (2.0 * std::f64::consts::PI * cutoff);
        let dt = 1.0 / self.sample_rate;
        (rc / (rc + dt)) as f32
    }

    fn coef_lp(&self, cutoff: f64) -> f32 {
        let rc = 1.0 / (2.0 * std::f64::consts::PI * cutoff);
        let dt = 1.0 / self.sample_rate;
        (dt / (rc + dt)) as f32
    }

    /// 每 CPU 周期喂一个原始样本;产出时返回 Some(i16)。
    fn push(&mut self, s: f32) -> Option<i16> {
        self.sum += s;
        self.count += 1;
        self.phase += 1.0;
        let step = self.cycles_per_sample * self.adjust;
        if self.phase < step {
            return None;
        }
        self.phase -= step;
        let avg = self.sum / self.count.max(1) as f32;
        self.sum = 0.0;
        self.count = 0;
        // 90Hz、440Hz 高通 + 14kHz 低通(一阶)
        let a1 = self.coef_hp(90.0);
        let y1 = a1 * (self.hp1_y + avg - self.hp1_x);
        self.hp1_x = avg;
        self.hp1_y = y1;
        let a2 = self.coef_hp(440.0);
        let y2 = a2 * (self.hp2_y + y1 - self.hp2_x);
        self.hp2_x = y1;
        self.hp2_y = y2;
        let al = self.coef_lp(14000.0);
        self.lp_y += al * (y2 - self.lp_y);
        Some((self.lp_y.clamp(-1.0, 1.0) * 26000.0) as i16)
    }
}

// ---------------- APU 主体 ----------------

#[derive(Serialize, Deserialize)]
pub struct Apu {
    pulse1: Pulse,
    pulse2: Pulse,
    triangle: Triangle,
    noise: Noise,
    pub dmc: Dmc,
    // 帧计数器
    fc_counter: u32, // CPU 周期计
    fc_mode5: bool,
    fc_irq_inhibit: bool,
    pub fc_irq: bool,
    fc_write_pending: Option<u8>,
    fc_write_delay: u8,
    odd_cycle: bool,
    last_4017: u8,
    resampler: Resampler,
    region: Region,
    #[serde(skip)]
    pub out: Vec<i16>,
}

impl Default for Apu {
    fn default() -> Apu {
        let mut a = Apu {
            pulse1: Pulse::default(),
            pulse2: Pulse {
                is_pulse2: true,
                ..Pulse::default()
            },
            triangle: Triangle::default(),
            noise: Noise::default(),
            dmc: Dmc::default(),
            fc_counter: 0,
            fc_mode5: false,
            fc_irq_inhibit: false,
            fc_irq: false,
            fc_write_pending: None,
            fc_write_delay: 0,
            odd_cycle: false,
            last_4017: 0,
            resampler: Resampler::default(),
            region: Region::Ntsc,
            out: Vec::new(),
        };
        a.dmc.timer = DMC_RATES[0] - 1;
        a
    }
}

impl Apu {
    pub fn irq_asserted(&self) -> bool {
        self.fc_irq || self.dmc.irq_flag
    }

    pub fn set_sample_rate(&mut self, rate: f64) {
        self.resampler.set_rate(rate);
    }

    /// 软复位(blargg apu_reset 语义):
    /// 长度计数器使能位置位、脉冲/噪声长度清零、三角形长度保留;
    /// 帧 IRQ 与 DMC IRQ 清除;$4017 以上次写入值重写。
    pub fn reset(&mut self, cpu_cycles: u64) {
        self.write(0x4015, 0, cpu_cycles);
        self.fc_irq = false;
        self.dmc.irq_flag = false;
        let last = self.last_4017;
        self.write(0x4017, last, cpu_cycles);
    }

    pub fn set_region(&mut self, region: Region) {
        self.region = region;
        self.dmc.pal = region == Region::Pal;
        self.resampler.cpu_hz = region.cpu_hz();
        let r = self.resampler.sample_rate;
        self.resampler.set_rate(r);
    }

    /// 动态速率控制:1.0 = 标称;>1 略慢消耗(缓冲偏满时用)。
    pub fn set_rate_adjust(&mut self, adjust: f64) {
        self.resampler.adjust = adjust.clamp(0.98, 1.02);
    }

    fn quarter(&mut self) {
        self.pulse1.env.quarter();
        self.pulse2.env.quarter();
        self.noise.env.quarter();
        self.triangle.quarter();
    }

    fn half(&mut self) {
        self.quarter();
        self.pulse1.half();
        self.pulse2.half();
        self.noise.half();
        self.triangle.half();
    }

    fn set_frame_irq(&mut self) {
        if !self.fc_irq_inhibit {
            self.fc_irq = true;
        }
    }

    /// 每 CPU 周期一步。返回本周期是否有 DMC 取样请求交给 CPU。
    pub fn step(&mut self, expansion: f32) {
        // $4017 写入延迟生效
        if let Some(val) = self.fc_write_pending {
            if self.fc_write_delay == 0 {
                self.fc_write_pending = None;
                self.fc_mode5 = val & 0x80 != 0;
                self.fc_counter = 0;
                if self.fc_mode5 {
                    self.half();
                }
            } else {
                self.fc_write_delay -= 1;
            }
        }

        // 帧计数器(CPU 周期表,NTSC)
        self.fc_counter += 1;
        let pal = self.region == Region::Pal;
        let (q1, h1, q2, irq0, irq1, irq2, m5h, m5w) = if pal {
            (8313, 16627, 24939, 33252, 33253, 33254, 41565, 41566)
        } else {
            (7457, 14913, 22371, 29828, 29829, 29830, 37281, 37282)
        };
        if !self.fc_mode5 {
            match self.fc_counter {
                c if c == q1 => self.quarter(),
                c if c == h1 => self.half(),
                c if c == q2 => self.quarter(),
                c if c == irq0 => self.set_frame_irq(),
                c if c == irq1 => {
                    self.half();
                    self.set_frame_irq();
                }
                c if c == irq2 => {
                    self.set_frame_irq();
                    self.fc_counter = 0;
                }
                _ => {}
            }
        } else {
            match self.fc_counter {
                c if c == q1 => self.quarter(),
                c if c == h1 => self.half(),
                c if c == q2 => self.quarter(),
                c if c == m5h => self.half(),
                c if c == m5w => self.fc_counter = 0,
                _ => {}
            }
        }

        // 分频
        self.triangle.tick_timer();
        self.dmc.tick_timer();
        if self.odd_cycle {
            self.pulse1.tick_timer();
            self.pulse2.tick_timer();
            self.noise.tick_timer();
        }
        self.odd_cycle = !self.odd_cycle;

        // 混音
        let p = pulse_table()[(self.pulse1.output() + self.pulse2.output()) as usize];
        let tnd_i = 3 * self.triangle.output() as usize
            + 2 * self.noise.output() as usize
            + self.dmc.output_level as usize;
        let tnd = tnd_table()[tnd_i];
        if let Some(s) = self.resampler.push(p + tnd + expansion) {
            self.out.push(s);
        }
    }

    // ---------------- 寄存器 ----------------

    pub fn write(&mut self, addr: u16, val: u8, cpu_cycles: u64) {
        match addr {
            0x4000 | 0x4004 => {
                let p = if addr == 0x4000 {
                    &mut self.pulse1
                } else {
                    &mut self.pulse2
                };
                p.duty = val >> 6;
                p.halt = val & 0x20 != 0;
                p.env.looped = p.halt;
                p.env.constant = val & 0x10 != 0;
                p.env.volume = val & 0x0F;
            }
            0x4001 | 0x4005 => {
                let p = if addr == 0x4001 {
                    &mut self.pulse1
                } else {
                    &mut self.pulse2
                };
                p.sweep_enabled = val & 0x80 != 0;
                p.sweep_period = val >> 4 & 7;
                p.sweep_negate = val & 0x08 != 0;
                p.sweep_shift = val & 7;
                p.sweep_reload = true;
            }
            0x4002 | 0x4006 => {
                let p = if addr == 0x4002 {
                    &mut self.pulse1
                } else {
                    &mut self.pulse2
                };
                p.timer_period = p.timer_period & 0x700 | val as u16;
            }
            0x4003 | 0x4007 => {
                let p = if addr == 0x4003 {
                    &mut self.pulse1
                } else {
                    &mut self.pulse2
                };
                p.timer_period = p.timer_period & 0xFF | ((val & 7) as u16) << 8;
                if p.enabled {
                    p.length = LENGTH_TABLE[(val >> 3) as usize];
                }
                p.seq_step = 0;
                p.env.start = true;
            }
            0x4008 => {
                self.triangle.control = val & 0x80 != 0;
                self.triangle.linear_reload_val = val & 0x7F;
            }
            0x400A => {
                self.triangle.timer_period = self.triangle.timer_period & 0x700 | val as u16;
            }
            0x400B => {
                self.triangle.timer_period =
                    self.triangle.timer_period & 0xFF | ((val & 7) as u16) << 8;
                if self.triangle.enabled {
                    self.triangle.length = LENGTH_TABLE[(val >> 3) as usize];
                }
                self.triangle.linear_reload = true;
            }
            0x400C => {
                self.noise.halt = val & 0x20 != 0;
                self.noise.env.looped = self.noise.halt;
                self.noise.env.constant = val & 0x10 != 0;
                self.noise.env.volume = val & 0x0F;
            }
            0x400E => {
                self.noise.mode = val & 0x80 != 0;
                let table = if self.region == Region::Pal {
                    &NOISE_PERIODS_PAL
                } else {
                    &NOISE_PERIODS
                };
                self.noise.timer_period = table[(val & 0x0F) as usize];
            }
            0x400F => {
                if self.noise.enabled {
                    self.noise.length = LENGTH_TABLE[(val >> 3) as usize];
                }
                self.noise.env.start = true;
            }
            0x4010 => {
                self.dmc.irq_enable = val & 0x80 != 0;
                self.dmc.looped = val & 0x40 != 0;
                self.dmc.rate_index = val & 0x0F;
                if !self.dmc.irq_enable {
                    self.dmc.irq_flag = false;
                }
            }
            0x4011 => self.dmc.output_level = val & 0x7F,
            0x4012 => self.dmc.addr_start = 0xC000 + (val as u16) * 64,
            0x4013 => self.dmc.sample_len = (val as u16) * 16 + 1,
            0x4015 => {
                self.pulse1.enabled = val & 1 != 0;
                if !self.pulse1.enabled {
                    self.pulse1.length = 0;
                }
                self.pulse2.enabled = val & 2 != 0;
                if !self.pulse2.enabled {
                    self.pulse2.length = 0;
                }
                self.triangle.enabled = val & 4 != 0;
                if !self.triangle.enabled {
                    self.triangle.length = 0;
                }
                self.noise.enabled = val & 8 != 0;
                if !self.noise.enabled {
                    self.noise.length = 0;
                }
                self.dmc.irq_flag = false;
                if val & 0x10 != 0 {
                    if self.dmc.bytes_remaining == 0 {
                        self.dmc.restart();
                        if self.dmc.sample_buffer.is_none() {
                            self.dmc.fetch_pending = true;
                        }
                    }
                } else {
                    self.dmc.bytes_remaining = 0;
                    self.dmc.fetch_pending = false;
                }
            }
            0x4017 => {
                self.last_4017 = val;
                self.fc_irq_inhibit = val & 0x40 != 0;
                if self.fc_irq_inhibit {
                    self.fc_irq = false;
                }
                self.fc_write_pending = Some(val);
                // 偶数周期写延迟 4,奇数写延迟 3(近似 blargg 观测)
                self.fc_write_delay = if cpu_cycles % 2 == 0 { 4 } else { 3 };
            }
            _ => {}
        }
    }

    pub fn read_status(&mut self, open_bus: u8) -> u8 {
        let mut v = 0u8;
        if self.pulse1.length > 0 {
            v |= 0x01;
        }
        if self.pulse2.length > 0 {
            v |= 0x02;
        }
        if self.triangle.length > 0 {
            v |= 0x04;
        }
        if self.noise.length > 0 {
            v |= 0x08;
        }
        if self.dmc.bytes_remaining > 0 {
            v |= 0x10;
        }
        if self.fc_irq {
            v |= 0x40;
        }
        if self.dmc.irq_flag {
            v |= 0x80;
        }
        self.fc_irq = false;
        v | open_bus & 0x20
    }
}
