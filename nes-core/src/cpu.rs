//! 2A03 中的 6502 内核:全部 256 个操作码,微操作级周期精确。
//!
//! 每次 `Nes::read`/`Nes::write` 恰好消耗一个 CPU 周期(内部推进 PPU×3/APU×1),
//! 指令实现按真实总线访问序列书写,dummy read/write 一律照做。
//! 中断在指令末尾轮询,轮询值取倒数第二个周期的线电平(tick 里维护 prev_*)。

use crate::nes::Nes;
use serde::{Deserialize, Serialize};

pub const C: u8 = 0x01;
pub const Z: u8 = 0x02;
pub const I: u8 = 0x04;
pub const D: u8 = 0x08;
pub const B: u8 = 0x10;
pub const U: u8 = 0x20;
pub const V: u8 = 0x40;
pub const N: u8 = 0x80;

#[derive(Serialize, Deserialize)]
pub struct Cpu {
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub sp: u8,
    pub p: u8,
    pub pc: u16,
    pub jammed: bool,
    // ---- 中断线路与采样 ----
    /// PPU NMI 输出的当前电平
    pub nmi_line: bool,
    /// NMI 下降沿锁存(被服务后清除)
    pub nmi_pending: bool,
    /// 上一周期开始时的锁存值(末周期轮询用)
    pub prev_nmi_pending: bool,
    /// IRQ 线当前电平(APU 帧计数 ∨ DMC ∨ mapper)
    pub irq_line: bool,
    pub prev_irq_line: bool,
    take_nmi: bool,
    take_irq: bool,
    /// CLI/SEI/PLP:本条指令的轮询用修改前的 I
    i_delay: Option<bool>,
    /// 分支指令已自行轮询
    polled: bool,
}

impl Default for Cpu {
    fn default() -> Cpu {
        Cpu {
            a: 0,
            x: 0,
            y: 0,
            sp: 0x00, // 复位序列 -3 → $FD
            p: 0x24,
            pc: 0,
            jammed: false,
            nmi_line: false,
            nmi_pending: false,
            prev_nmi_pending: false,
            irq_line: false,
            prev_irq_line: false,
            take_nmi: false,
            take_irq: false,
            i_delay: None,
            polled: false,
        }
    }
}

impl Nes {
    // ---------- 基本访问 ----------

    fn fetch8(&mut self) -> u8 {
        let v = self.read(self.cpu.pc);
        self.cpu.pc = self.cpu.pc.wrapping_add(1);
        v
    }

    fn fetch16(&mut self) -> u16 {
        let lo = self.fetch8() as u16;
        let hi = self.fetch8() as u16;
        hi << 8 | lo
    }

    fn push(&mut self, v: u8) {
        self.write(0x0100 | self.cpu.sp as u16, v);
        self.cpu.sp = self.cpu.sp.wrapping_sub(1);
    }

    fn pull(&mut self) -> u8 {
        self.cpu.sp = self.cpu.sp.wrapping_add(1);
        self.read(0x0100 | self.cpu.sp as u16)
    }

    fn set_zn(&mut self, v: u8) {
        self.cpu.p = (self.cpu.p & !(Z | N)) | if v == 0 { Z } else { 0 } | (v & N);
    }

    fn set_flag(&mut self, f: u8, on: bool) {
        if on {
            self.cpu.p |= f;
        } else {
            self.cpu.p &= !f;
        }
    }

    // ---------- 寻址模式(内含规定的 dummy 访问)----------

    fn am_zp(&mut self) -> u16 {
        self.fetch8() as u16
    }

    fn am_zpx(&mut self) -> u16 {
        let z = self.fetch8();
        self.read(z as u16); // dummy
        z.wrapping_add(self.cpu.x) as u16
    }

    fn am_zpy(&mut self) -> u16 {
        let z = self.fetch8();
        self.read(z as u16); // dummy
        z.wrapping_add(self.cpu.y) as u16
    }

    fn am_abs(&mut self) -> u16 {
        self.fetch16()
    }

    /// 读类指令:仅页跨越时在错误地址 dummy read。
    fn am_abs_idx_read(&mut self, idx: u8) -> u16 {
        let base = self.fetch16();
        let eff = base.wrapping_add(idx as u16);
        if base & 0xFF00 != eff & 0xFF00 {
            self.read(base & 0xFF00 | eff & 0x00FF); // dummy
        }
        eff
    }

    /// 写/RMW 类指令:总是先在部分求和地址 dummy read。
    fn am_abs_idx_write(&mut self, idx: u8) -> u16 {
        let base = self.fetch16();
        let eff = base.wrapping_add(idx as u16);
        self.read(base & 0xFF00 | eff & 0x00FF); // dummy
        eff
    }

    fn am_izx(&mut self) -> u16 {
        let z = self.fetch8();
        self.read(z as u16); // dummy
        let p = z.wrapping_add(self.cpu.x);
        let lo = self.read(p as u16) as u16;
        let hi = self.read(p.wrapping_add(1) as u16) as u16;
        hi << 8 | lo
    }

    fn am_izy_read(&mut self) -> u16 {
        let z = self.fetch8();
        let lo = self.read(z as u16) as u16;
        let hi = self.read(z.wrapping_add(1) as u16) as u16;
        let base = hi << 8 | lo;
        let eff = base.wrapping_add(self.cpu.y as u16);
        if base & 0xFF00 != eff & 0xFF00 {
            self.read(base & 0xFF00 | eff & 0x00FF); // dummy
        }
        eff
    }

    fn am_izy_write(&mut self) -> u16 {
        let z = self.fetch8();
        let lo = self.read(z as u16) as u16;
        let hi = self.read(z.wrapping_add(1) as u16) as u16;
        let base = hi << 8 | lo;
        let eff = base.wrapping_add(self.cpu.y as u16);
        self.read(base & 0xFF00 | eff & 0x00FF); // dummy
        eff
    }

    /// 读-修改-写:read, dummy write 原值, write 新值。
    fn rmw(&mut self, addr: u16, f: impl FnOnce(&mut Nes, u8) -> u8) -> u8 {
        let v = self.read(addr);
        self.write(addr, v); // dummy write
        let nv = f(self, v);
        self.write(addr, nv);
        nv
    }

    // ---------- ALU ----------

    fn adc(&mut self, v: u8) {
        let a = self.cpu.a;
        let sum = a as u16 + v as u16 + (self.cpu.p & C) as u16;
        let r = sum as u8;
        self.set_flag(C, sum > 0xFF);
        self.set_flag(V, (a ^ r) & (v ^ r) & 0x80 != 0);
        self.cpu.a = r;
        self.set_zn(r);
    }

    fn sbc(&mut self, v: u8) {
        self.adc(!v); // 2A03 无 BCD,SBC 即按位取反的 ADC
    }

    fn cmp_op(&mut self, reg: u8, v: u8) {
        let r = reg.wrapping_sub(v);
        self.set_flag(C, reg >= v);
        self.set_zn(r);
    }

    fn asl_v(&mut self, v: u8) -> u8 {
        self.set_flag(C, v & 0x80 != 0);
        let r = v << 1;
        self.set_zn(r);
        r
    }

    fn lsr_v(&mut self, v: u8) -> u8 {
        self.set_flag(C, v & 1 != 0);
        let r = v >> 1;
        self.set_zn(r);
        r
    }

    fn rol_v(&mut self, v: u8) -> u8 {
        let c = self.cpu.p & C;
        self.set_flag(C, v & 0x80 != 0);
        let r = v << 1 | c;
        self.set_zn(r);
        r
    }

    fn ror_v(&mut self, v: u8) -> u8 {
        let c = self.cpu.p & C;
        self.set_flag(C, v & 1 != 0);
        let r = v >> 1 | c << 7;
        self.set_zn(r);
        r
    }

    // ---------- 中断 ----------

    /// 末周期轮询:用倒数第二周期的线状态决定下一指令前是否进中断。
    fn poll_interrupts(&mut self) {
        let i_flag = match self.cpu.i_delay.take() {
            Some(old) => old,
            None => self.cpu.p & I != 0,
        };
        self.cpu.take_nmi = self.cpu.prev_nmi_pending;
        self.cpu.take_irq = self.cpu.prev_irq_line && !i_flag;
    }

    /// IRQ/NMI 进入序列(7 周期,BRK 另走)。
    fn interrupt_sequence(&mut self) {
        self.read(self.cpu.pc); // dummy
        self.read(self.cpu.pc); // dummy
        self.push((self.cpu.pc >> 8) as u8);
        self.push(self.cpu.pc as u8);
        // 向量决策点:NMI 可劫持 IRQ
        let nmi = self.cpu.nmi_pending;
        self.push(self.cpu.p & !B | U);
        self.cpu.p |= I;
        let vec = if nmi { 0xFFFA } else { 0xFFFE };
        if nmi {
            self.cpu.nmi_pending = false;
        }
        let lo = self.read(vec) as u16;
        let hi = self.read(vec + 1) as u16;
        self.cpu.pc = hi << 8 | lo;
    }

    /// 复位:7 周期,SP -= 3,置 I。
    pub(crate) fn cpu_reset(&mut self) {
        for _ in 0..5 {
            self.tick();
        }
        self.cpu.sp = self.cpu.sp.wrapping_sub(3);
        self.cpu.p |= I;
        let lo = self.read(0xFFFC) as u16;
        let hi = self.read(0xFFFD) as u16;
        self.cpu.pc = hi << 8 | lo;
        self.cpu.nmi_pending = false;
        self.cpu.take_nmi = false;
        self.cpu.take_irq = false;
    }

    // ---------- 指令循环 ----------

    /// 执行一条指令(或服务一次中断),返回消耗前的 PC(trace 用)。
    pub fn step_instruction(&mut self) {
        if self.cpu.jammed {
            self.tick();
            return;
        }
        // 中断序列末尾不轮询:handler 的第一条指令总会先执行
        if self.cpu.take_nmi {
            self.cpu.take_nmi = false;
            self.cpu.take_irq = false;
            self.interrupt_sequence();
            return;
        }
        if self.cpu.take_irq {
            self.cpu.take_irq = false;
            self.interrupt_sequence();
            return;
        }
        self.cpu.polled = false;
        let op = self.fetch8();
        self.exec(op);
        if !self.cpu.polled {
            self.poll_interrupts();
        }
    }

    fn branch(&mut self, cond: bool) {
        let off = self.fetch8() as i8;
        if !cond {
            return;
        }
        // 硬件:非跨页的成立分支在最后周期不轮询中断(晚到的中断顺延一条指令)
        self.poll_interrupts();
        self.cpu.polled = true;
        self.read(self.cpu.pc); // dummy
        let old = self.cpu.pc;
        self.cpu.pc = old.wrapping_add(off as u16);
        if old & 0xFF00 != self.cpu.pc & 0xFF00 {
            self.read(old & 0xFF00 | self.cpu.pc & 0x00FF); // dummy
            self.poll_interrupts(); // 跨页分支按正常点轮询
        }
    }

    fn exec(&mut self, op: u8) {
        macro_rules! read_op {
            ($addr:expr, $f:ident) => {{
                let a = $addr;
                let v = self.read(a);
                self.$f(v);
            }};
        }
        macro_rules! imm_op {
            ($f:ident) => {{
                let v = self.fetch8();
                self.$f(v);
            }};
        }
        match op {
            // ---------------- 官方指令 ----------------
            // ADC
            0x69 => imm_op!(adc),
            0x65 => read_op!(self.am_zp(), adc),
            0x75 => read_op!(self.am_zpx(), adc),
            0x6D => read_op!(self.am_abs(), adc),
            0x7D => read_op!(self.am_abs_idx_read(self.cpu.x), adc),
            0x79 => read_op!(self.am_abs_idx_read(self.cpu.y), adc),
            0x61 => read_op!(self.am_izx(), adc),
            0x71 => read_op!(self.am_izy_read(), adc),
            // SBC
            0xE9 | 0xEB => imm_op!(sbc),
            0xE5 => read_op!(self.am_zp(), sbc),
            0xF5 => read_op!(self.am_zpx(), sbc),
            0xED => read_op!(self.am_abs(), sbc),
            0xFD => read_op!(self.am_abs_idx_read(self.cpu.x), sbc),
            0xF9 => read_op!(self.am_abs_idx_read(self.cpu.y), sbc),
            0xE1 => read_op!(self.am_izx(), sbc),
            0xF1 => read_op!(self.am_izy_read(), sbc),
            // AND/ORA/EOR
            0x29 => {
                let v = self.fetch8();
                self.cpu.a &= v;
                self.set_zn(self.cpu.a);
            }
            0x25 | 0x35 | 0x2D | 0x3D | 0x39 | 0x21 | 0x31 => {
                let a = self.addr_for_read(op);
                let v = self.read(a);
                self.cpu.a &= v;
                self.set_zn(self.cpu.a);
            }
            0x09 => {
                let v = self.fetch8();
                self.cpu.a |= v;
                self.set_zn(self.cpu.a);
            }
            0x05 | 0x15 | 0x0D | 0x1D | 0x19 | 0x01 | 0x11 => {
                let a = self.addr_for_read(op);
                let v = self.read(a);
                self.cpu.a |= v;
                self.set_zn(self.cpu.a);
            }
            0x49 => {
                let v = self.fetch8();
                self.cpu.a ^= v;
                self.set_zn(self.cpu.a);
            }
            0x45 | 0x55 | 0x4D | 0x5D | 0x59 | 0x41 | 0x51 => {
                let a = self.addr_for_read(op);
                let v = self.read(a);
                self.cpu.a ^= v;
                self.set_zn(self.cpu.a);
            }
            // CMP/CPX/CPY
            0xC9 => {
                let v = self.fetch8();
                self.cmp_op(self.cpu.a, v);
            }
            0xC5 | 0xD5 | 0xCD | 0xDD | 0xD9 | 0xC1 | 0xD1 => {
                let a = self.addr_for_read(op);
                let v = self.read(a);
                self.cmp_op(self.cpu.a, v);
            }
            0xE0 => {
                let v = self.fetch8();
                self.cmp_op(self.cpu.x, v);
            }
            0xE4 => {
                let a = self.am_zp();
                let v = self.read(a);
                self.cmp_op(self.cpu.x, v);
            }
            0xEC => {
                let a = self.am_abs();
                let v = self.read(a);
                self.cmp_op(self.cpu.x, v);
            }
            0xC0 => {
                let v = self.fetch8();
                self.cmp_op(self.cpu.y, v);
            }
            0xC4 => {
                let a = self.am_zp();
                let v = self.read(a);
                self.cmp_op(self.cpu.y, v);
            }
            0xCC => {
                let a = self.am_abs();
                let v = self.read(a);
                self.cmp_op(self.cpu.y, v);
            }
            // LDA/LDX/LDY
            0xA9 => {
                self.cpu.a = self.fetch8();
                self.set_zn(self.cpu.a);
            }
            0xA5 | 0xB5 | 0xAD | 0xBD | 0xB9 | 0xA1 | 0xB1 => {
                let a = self.addr_for_read(op);
                self.cpu.a = self.read(a);
                self.set_zn(self.cpu.a);
            }
            0xA2 => {
                self.cpu.x = self.fetch8();
                self.set_zn(self.cpu.x);
            }
            0xA6 => {
                let a = self.am_zp();
                self.cpu.x = self.read(a);
                self.set_zn(self.cpu.x);
            }
            0xB6 => {
                let a = self.am_zpy();
                self.cpu.x = self.read(a);
                self.set_zn(self.cpu.x);
            }
            0xAE => {
                let a = self.am_abs();
                self.cpu.x = self.read(a);
                self.set_zn(self.cpu.x);
            }
            0xBE => {
                let a = self.am_abs_idx_read(self.cpu.y);
                self.cpu.x = self.read(a);
                self.set_zn(self.cpu.x);
            }
            0xA0 => {
                self.cpu.y = self.fetch8();
                self.set_zn(self.cpu.y);
            }
            0xA4 => {
                let a = self.am_zp();
                self.cpu.y = self.read(a);
                self.set_zn(self.cpu.y);
            }
            0xB4 => {
                let a = self.am_zpx();
                self.cpu.y = self.read(a);
                self.set_zn(self.cpu.y);
            }
            0xAC => {
                let a = self.am_abs();
                self.cpu.y = self.read(a);
                self.set_zn(self.cpu.y);
            }
            0xBC => {
                let a = self.am_abs_idx_read(self.cpu.x);
                self.cpu.y = self.read(a);
                self.set_zn(self.cpu.y);
            }
            // STA/STX/STY
            0x85 => {
                let a = self.am_zp();
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x95 => {
                let a = self.am_zpx();
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x8D => {
                let a = self.am_abs();
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x9D => {
                let a = self.am_abs_idx_write(self.cpu.x);
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x99 => {
                let a = self.am_abs_idx_write(self.cpu.y);
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x81 => {
                let a = self.am_izx();
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x91 => {
                let a = self.am_izy_write();
                let v = self.cpu.a;
                self.write(a, v);
            }
            0x86 => {
                let a = self.am_zp();
                let v = self.cpu.x;
                self.write(a, v);
            }
            0x96 => {
                let a = self.am_zpy();
                let v = self.cpu.x;
                self.write(a, v);
            }
            0x8E => {
                let a = self.am_abs();
                let v = self.cpu.x;
                self.write(a, v);
            }
            0x84 => {
                let a = self.am_zp();
                let v = self.cpu.y;
                self.write(a, v);
            }
            0x94 => {
                let a = self.am_zpx();
                let v = self.cpu.y;
                self.write(a, v);
            }
            0x8C => {
                let a = self.am_abs();
                let v = self.cpu.y;
                self.write(a, v);
            }
            // 移位(累加器与内存)
            0x0A => {
                self.read(self.cpu.pc); // dummy
                self.cpu.a = self.asl_v(self.cpu.a);
            }
            0x06 | 0x16 | 0x0E | 0x1E => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| n.asl_v(v));
            }
            0x4A => {
                self.read(self.cpu.pc);
                self.cpu.a = self.lsr_v(self.cpu.a);
            }
            0x46 | 0x56 | 0x4E | 0x5E => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| n.lsr_v(v));
            }
            0x2A => {
                self.read(self.cpu.pc);
                self.cpu.a = self.rol_v(self.cpu.a);
            }
            0x26 | 0x36 | 0x2E | 0x3E => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| n.rol_v(v));
            }
            0x6A => {
                self.read(self.cpu.pc);
                self.cpu.a = self.ror_v(self.cpu.a);
            }
            0x66 | 0x76 | 0x6E | 0x7E => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| n.ror_v(v));
            }
            // INC/DEC
            0xE6 | 0xF6 | 0xEE | 0xFE => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| {
                    let r = v.wrapping_add(1);
                    n.set_zn(r);
                    r
                });
            }
            0xC6 | 0xD6 | 0xCE | 0xDE => {
                let a = self.addr_for_rmw(op);
                self.rmw(a, |n, v| {
                    let r = v.wrapping_sub(1);
                    n.set_zn(r);
                    r
                });
            }
            0xE8 => {
                self.read(self.cpu.pc);
                self.cpu.x = self.cpu.x.wrapping_add(1);
                self.set_zn(self.cpu.x);
            }
            0xC8 => {
                self.read(self.cpu.pc);
                self.cpu.y = self.cpu.y.wrapping_add(1);
                self.set_zn(self.cpu.y);
            }
            0xCA => {
                self.read(self.cpu.pc);
                self.cpu.x = self.cpu.x.wrapping_sub(1);
                self.set_zn(self.cpu.x);
            }
            0x88 => {
                self.read(self.cpu.pc);
                self.cpu.y = self.cpu.y.wrapping_sub(1);
                self.set_zn(self.cpu.y);
            }
            // BIT
            0x24 => {
                let a = self.am_zp();
                let v = self.read(a);
                self.set_flag(Z, self.cpu.a & v == 0);
                self.cpu.p = self.cpu.p & !(N | V) | (v & (N | V));
            }
            0x2C => {
                let a = self.am_abs();
                let v = self.read(a);
                self.set_flag(Z, self.cpu.a & v == 0);
                self.cpu.p = self.cpu.p & !(N | V) | (v & (N | V));
            }
            // 跳转与子程序
            0x4C => {
                self.cpu.pc = self.fetch16();
            }
            0x6C => {
                let ptr = self.fetch16();
                let lo = self.read(ptr) as u16;
                // 6502 bug:指针跨页取高字节回卷
                let hi_addr = ptr & 0xFF00 | (ptr as u8).wrapping_add(1) as u16;
                let hi = self.read(hi_addr) as u16;
                self.cpu.pc = hi << 8 | lo;
            }
            0x20 => {
                let lo = self.fetch8() as u16;
                self.read(0x0100 | self.cpu.sp as u16); // 内部周期
                self.push((self.cpu.pc >> 8) as u8);
                self.push(self.cpu.pc as u8);
                let hi = self.fetch8() as u16;
                self.cpu.pc = hi << 8 | lo;
            }
            0x60 => {
                self.read(self.cpu.pc); // dummy
                self.read(0x0100 | self.cpu.sp as u16); // 内部周期
                let lo = self.pull() as u16;
                let hi = self.pull() as u16;
                self.cpu.pc = hi << 8 | lo;
                self.read(self.cpu.pc); // dummy
                self.cpu.pc = self.cpu.pc.wrapping_add(1);
            }
            0x40 => {
                self.read(self.cpu.pc); // dummy
                self.read(0x0100 | self.cpu.sp as u16); // 内部周期
                let p = self.pull();
                self.cpu.p = p & !B | U;
                let lo = self.pull() as u16;
                let hi = self.pull() as u16;
                self.cpu.pc = hi << 8 | lo;
                // RTI 恢复的 I 立即生效(与 PLP 不同,无延迟)
            }
            0x00 => {
                // BRK
                self.fetch8(); // padding 字节
                self.push((self.cpu.pc >> 8) as u8);
                self.push(self.cpu.pc as u8);
                let nmi = self.cpu.nmi_pending; // NMI 劫持
                self.push(self.cpu.p | B | U);
                self.cpu.p |= I;
                let vec = if nmi { 0xFFFA } else { 0xFFFE };
                if nmi {
                    self.cpu.nmi_pending = false;
                }
                let lo = self.read(vec) as u16;
                let hi = self.read(vec + 1) as u16;
                self.cpu.pc = hi << 8 | lo;
                self.cpu.polled = true; // 中断序列末尾不轮询
            }
            // 分支
            0x10 => {
                let c = self.cpu.p & N == 0;
                self.branch(c);
            }
            0x30 => {
                let c = self.cpu.p & N != 0;
                self.branch(c);
            }
            0x50 => {
                let c = self.cpu.p & V == 0;
                self.branch(c);
            }
            0x70 => {
                let c = self.cpu.p & V != 0;
                self.branch(c);
            }
            0x90 => {
                let c = self.cpu.p & C == 0;
                self.branch(c);
            }
            0xB0 => {
                let c = self.cpu.p & C != 0;
                self.branch(c);
            }
            0xD0 => {
                let c = self.cpu.p & Z == 0;
                self.branch(c);
            }
            0xF0 => {
                let c = self.cpu.p & Z != 0;
                self.branch(c);
            }
            // 栈与传送
            0x48 => {
                self.read(self.cpu.pc);
                let v = self.cpu.a;
                self.push(v);
            }
            0x08 => {
                self.read(self.cpu.pc);
                let v = self.cpu.p | B | U;
                self.push(v);
            }
            0x68 => {
                self.read(self.cpu.pc);
                self.read(0x0100 | self.cpu.sp as u16); // 内部周期
                let v = self.pull();
                self.cpu.a = v;
                self.set_zn(v);
            }
            0x28 => {
                self.read(self.cpu.pc);
                self.read(0x0100 | self.cpu.sp as u16); // 内部周期
                let old_i = self.cpu.p & I != 0;
                let v = self.pull();
                self.cpu.p = v & !B | U;
                self.cpu.i_delay = Some(old_i); // I 变更延迟一条指令生效(轮询侧)
            }
            0xAA => {
                self.read(self.cpu.pc);
                self.cpu.x = self.cpu.a;
                self.set_zn(self.cpu.x);
            }
            0xA8 => {
                self.read(self.cpu.pc);
                self.cpu.y = self.cpu.a;
                self.set_zn(self.cpu.y);
            }
            0xBA => {
                self.read(self.cpu.pc);
                self.cpu.x = self.cpu.sp;
                self.set_zn(self.cpu.x);
            }
            0x8A => {
                self.read(self.cpu.pc);
                self.cpu.a = self.cpu.x;
                self.set_zn(self.cpu.a);
            }
            0x9A => {
                self.read(self.cpu.pc);
                self.cpu.sp = self.cpu.x;
            }
            0x98 => {
                self.read(self.cpu.pc);
                self.cpu.a = self.cpu.y;
                self.set_zn(self.cpu.a);
            }
            // 标志
            0x18 => {
                self.read(self.cpu.pc);
                self.cpu.p &= !C;
            }
            0x38 => {
                self.read(self.cpu.pc);
                self.cpu.p |= C;
            }
            0x58 => {
                self.read(self.cpu.pc);
                let old = self.cpu.p & I != 0;
                self.cpu.p &= !I;
                self.cpu.i_delay = Some(old);
            }
            0x78 => {
                self.read(self.cpu.pc);
                let old = self.cpu.p & I != 0;
                self.cpu.p |= I;
                self.cpu.i_delay = Some(old);
            }
            0xB8 => {
                self.read(self.cpu.pc);
                self.cpu.p &= !V;
            }
            0xD8 => {
                self.read(self.cpu.pc);
                self.cpu.p &= !D;
            }
            0xF8 => {
                self.read(self.cpu.pc);
                self.cpu.p |= D;
            }
            0xEA => {
                self.read(self.cpu.pc);
            }
            // ---------------- 非官方指令 ----------------
            // NOP 变体(执行真实寻址访问)
            0x1A | 0x3A | 0x5A | 0x7A | 0xDA | 0xFA => {
                self.read(self.cpu.pc);
            }
            0x80 | 0x82 | 0x89 | 0xC2 | 0xE2 => {
                self.fetch8();
            }
            0x04 | 0x44 | 0x64 => {
                let a = self.am_zp();
                self.read(a);
            }
            0x14 | 0x34 | 0x54 | 0x74 | 0xD4 | 0xF4 => {
                let a = self.am_zpx();
                self.read(a);
            }
            0x0C => {
                let a = self.am_abs();
                self.read(a);
            }
            0x1C | 0x3C | 0x5C | 0x7C | 0xDC | 0xFC => {
                let a = self.am_abs_idx_read(self.cpu.x);
                self.read(a);
            }
            // LAX
            0xA7 => {
                let a = self.am_zp();
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xB7 => {
                let a = self.am_zpy();
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xAF => {
                let a = self.am_abs();
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xBF => {
                let a = self.am_abs_idx_read(self.cpu.y);
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xA3 => {
                let a = self.am_izx();
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xB3 => {
                let a = self.am_izy_read();
                let v = self.read(a);
                self.cpu.a = v;
                self.cpu.x = v;
                self.set_zn(v);
            }
            0xAB => {
                // LXA:不稳定;blargg instr_test-v5 校准为魔数 0xFF(A=X=imm)
                let v = self.fetch8();
                let r = (self.cpu.a | 0xFF) & v;
                self.cpu.a = r;
                self.cpu.x = r;
                self.set_zn(r);
            }
            // SAX
            0x87 => {
                let a = self.am_zp();
                let v = self.cpu.a & self.cpu.x;
                self.write(a, v);
            }
            0x97 => {
                let a = self.am_zpy();
                let v = self.cpu.a & self.cpu.x;
                self.write(a, v);
            }
            0x8F => {
                let a = self.am_abs();
                let v = self.cpu.a & self.cpu.x;
                self.write(a, v);
            }
            0x83 => {
                let a = self.am_izx();
                let v = self.cpu.a & self.cpu.x;
                self.write(a, v);
            }
            // DCP = DEC + CMP
            0xC7 | 0xD7 | 0xCF | 0xDF | 0xDB | 0xC3 | 0xD3 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| {
                    let r = v.wrapping_sub(1);
                    n.set_zn(r);
                    r
                });
                self.cmp_op(self.cpu.a, r);
            }
            // ISC = INC + SBC
            0xE7 | 0xF7 | 0xEF | 0xFF | 0xFB | 0xE3 | 0xF3 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| {
                    let r = v.wrapping_add(1);
                    n.set_zn(r);
                    r
                });
                self.sbc(r);
            }
            // SLO = ASL + ORA
            0x07 | 0x17 | 0x0F | 0x1F | 0x1B | 0x03 | 0x13 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| n.asl_v(v));
                self.cpu.a |= r;
                self.set_zn(self.cpu.a);
            }
            // RLA = ROL + AND
            0x27 | 0x37 | 0x2F | 0x3F | 0x3B | 0x23 | 0x33 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| n.rol_v(v));
                self.cpu.a &= r;
                self.set_zn(self.cpu.a);
            }
            // SRE = LSR + EOR
            0x47 | 0x57 | 0x4F | 0x5F | 0x5B | 0x43 | 0x53 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| n.lsr_v(v));
                self.cpu.a ^= r;
                self.set_zn(self.cpu.a);
            }
            // RRA = ROR + ADC
            0x67 | 0x77 | 0x6F | 0x7F | 0x7B | 0x63 | 0x73 => {
                let a = self.addr_for_rmw_u(op);
                let r = self.rmw(a, |n, v| n.ror_v(v));
                self.adc(r);
            }
            // ANC/ALR/ARR/AXS/LAS/XAA
            0x0B | 0x2B => {
                let v = self.fetch8();
                self.cpu.a &= v;
                self.set_zn(self.cpu.a);
                let neg = self.cpu.a & 0x80 != 0;
                self.set_flag(C, neg);
            }
            0x4B => {
                let v = self.fetch8();
                self.cpu.a &= v;
                self.set_flag(C, self.cpu.a & 1 != 0);
                self.cpu.a >>= 1;
                self.set_zn(self.cpu.a);
            }
            0x6B => {
                let v = self.fetch8();
                let and = self.cpu.a & v;
                let r = and >> 1 | (self.cpu.p & C) << 7;
                self.cpu.a = r;
                self.set_zn(r);
                self.set_flag(C, r & 0x40 != 0);
                self.set_flag(V, (r >> 6 ^ r >> 5) & 1 != 0);
            }
            0xCB => {
                let v = self.fetch8();
                let ax = self.cpu.a & self.cpu.x;
                self.set_flag(C, ax >= v);
                self.cpu.x = ax.wrapping_sub(v);
                self.set_zn(self.cpu.x);
            }
            0xBB => {
                let a = self.am_abs_idx_read(self.cpu.y);
                let v = self.read(a) & self.cpu.sp;
                self.cpu.a = v;
                self.cpu.x = v;
                self.cpu.sp = v;
                self.set_zn(v);
            }
            0x8B => {
                // XAA:不稳定,魔数 0xEE
                let v = self.fetch8();
                self.cpu.a = (self.cpu.a | 0xEE) & self.cpu.x & v;
                self.set_zn(self.cpu.a);
            }
            // SHY/SHX/AHX/TAS:值 = 寄存器 & (基址高字节+1),跨页时地址高位被值污染
            0x9C => {
                self.sh_op(op);
            }
            0x9E => {
                self.sh_op(op);
            }
            0x9F | 0x93 => {
                self.sh_op(op);
            }
            0x9B => {
                self.cpu.sp = self.cpu.a & self.cpu.x;
                self.sh_op(op);
            }
            // JAM
            0x02 | 0x12 | 0x22 | 0x32 | 0x42 | 0x52 | 0x62 | 0x72 | 0x92 | 0xB2 | 0xD2 | 0xF2 => {
                self.read(self.cpu.pc);
                self.cpu.jammed = true;
            }
        }
    }

    /// SHY/SHX/AHX/TAS 的公共"高字节+1"写入。
    fn sh_op(&mut self, op: u8) {
        let (base, idx) = match op {
            0x9C => {
                let b = self.fetch16();
                (b, self.cpu.x)
            }
            0x93 => {
                let z = self.fetch8();
                let lo = self.read(z as u16) as u16;
                let hi = self.read(z.wrapping_add(1) as u16) as u16;
                (hi << 8 | lo, self.cpu.y)
            }
            _ => {
                let b = self.fetch16();
                (b, self.cpu.y)
            }
        };
        let eff = base.wrapping_add(idx as u16);
        self.read(base & 0xFF00 | eff & 0x00FF); // dummy
        let base_hi = (base >> 8) as u8;
        let reg = match op {
            0x9C => self.cpu.y,
            0x9E => self.cpu.x,
            _ => self.cpu.a & self.cpu.x,
        };
        let value = reg & base_hi.wrapping_add(1);
        let addr = if base & 0xFF00 != eff & 0xFF00 {
            (value as u16) << 8 | eff & 0x00FF
        } else {
            eff
        };
        self.write(addr, value);
    }

    /// 读类指令的寻址分派(按 opcode 低位模式)。
    fn addr_for_read(&mut self, op: u8) -> u16 {
        match op & 0x1F {
            0x01 => self.am_izx(),
            0x05 => self.am_zp(),
            0x0D => self.am_abs(),
            0x11 => self.am_izy_read(),
            0x15 => self.am_zpx(),
            0x19 => self.am_abs_idx_read(self.cpu.y),
            0x1D => self.am_abs_idx_read(self.cpu.x),
            _ => unreachable!(),
        }
    }

    /// 官方 RMW(ASL/LSR/ROL/ROR/INC/DEC):zp/zpx/abs/absx。
    fn addr_for_rmw(&mut self, op: u8) -> u16 {
        match op & 0x1F {
            0x06 => self.am_zp(),
            0x0E => self.am_abs(),
            0x16 => self.am_zpx(),
            0x1E => self.am_abs_idx_write(self.cpu.x),
            _ => unreachable!(),
        }
    }

    /// 非官方 RMW 组(DCP/ISC/SLO/RLA/SRE/RRA):多 izx/izy/absy 模式。
    fn addr_for_rmw_u(&mut self, op: u8) -> u16 {
        match op & 0x1F {
            0x03 => self.am_izx(),
            0x07 => self.am_zp(),
            0x0F => self.am_abs(),
            0x13 => self.am_izy_write(),
            0x17 => self.am_zpx(),
            0x1B => self.am_abs_idx_write(self.cpu.y),
            0x1F => self.am_abs_idx_write(self.cpu.x),
            _ => unreachable!(),
        }
    }
}
