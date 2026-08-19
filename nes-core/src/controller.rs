//! 标准手柄:strobe 锁存 + 串行移位读出。

use serde::{Deserialize, Serialize};

/// 按键位图。位序即硬件移位顺序:A,B,Select,Start,Up,Down,Left,Right。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Buttons(pub u8);

impl Buttons {
    pub const A: Buttons = Buttons(0x01);
    pub const B: Buttons = Buttons(0x02);
    pub const SELECT: Buttons = Buttons(0x04);
    pub const START: Buttons = Buttons(0x08);
    pub const UP: Buttons = Buttons(0x10);
    pub const DOWN: Buttons = Buttons(0x20);
    pub const LEFT: Buttons = Buttons(0x40);
    pub const RIGHT: Buttons = Buttons(0x80);

    pub fn insert(&mut self, b: Buttons) {
        self.0 |= b.0;
    }
    pub fn remove(&mut self, b: Buttons) {
        self.0 &= !b.0;
    }
    pub fn set(&mut self, b: Buttons, on: bool) {
        if on {
            self.insert(b)
        } else {
            self.remove(b)
        }
    }
}

impl std::ops::BitOr for Buttons {
    type Output = Buttons;
    fn bitor(self, rhs: Buttons) -> Buttons {
        Buttons(self.0 | rhs.0)
    }
}

#[derive(Default, Serialize, Deserialize)]
pub struct Controller {
    pub buttons: Buttons,
    strobe: bool,
    shift: u8,
}

impl Controller {
    pub fn write_strobe(&mut self, on: bool) {
        if self.strobe && !on {
            self.shift = self.buttons.0;
        }
        self.strobe = on;
    }

    /// $4016/$4017 读的 D0。高位由总线层补 open bus。
    pub fn read_bit(&mut self) -> u8 {
        if self.strobe {
            return self.buttons.0 & 1;
        }
        let bit = self.shift & 1;
        // 移空后持续返回 1(硬件行为)
        self.shift = 0x80 | (self.shift >> 1);
        bit
    }

    pub fn peek_bit(&self) -> u8 {
        if self.strobe {
            self.buttons.0 & 1
        } else {
            self.shift & 1
        }
    }
}
