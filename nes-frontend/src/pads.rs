//! 通用手柄(gilrs):双人槽位分配、热插拔、按键与左摇杆映射。
//!
//! gilrs 底层:Linux = evdev/udev(内核 hid-playstation 驱动下,DualSense 的
//! USB 与蓝牙都在此路径覆盖),Windows = XInput(Xbox 类 USB 手柄),
//! macOS = IOKit。自带 SDL_GameControllerDB 映射,普通 USB 手柄开箱即用;
//! 自定义映射可通过环境变量 SDL_GAMECONTROLLERCONFIG 注入。

use gilrs::{Axis, Button, EventType, GamepadId, Gilrs};
use nes_core::Buttons;

const DEADZONE: f32 = 0.5;

#[derive(Default, Clone, Copy)]
struct SlotState {
    buttons: Buttons,
    axis: Buttons,
}

impl SlotState {
    fn merged(self) -> Buttons {
        Buttons(self.buttons.0 | self.axis.0)
    }
}

pub struct GilrsPads {
    gilrs: Option<Gilrs>,
    assign: [Option<GamepadId>; 2],
    slots: [SlotState; 2],
}

fn map_button(b: Button) -> Option<Buttons> {
    match b {
        // 物理布局:右侧(East/PS ○)= NES A;下/左(South ✕ / West □)= NES B
        Button::East => Some(Buttons::A),
        Button::South | Button::West => Some(Buttons::B),
        Button::North => Some(Buttons::A),
        Button::Start => Some(Buttons::START),
        Button::Select => Some(Buttons::SELECT),
        Button::DPadUp => Some(Buttons::UP),
        Button::DPadDown => Some(Buttons::DOWN),
        Button::DPadLeft => Some(Buttons::LEFT),
        Button::DPadRight => Some(Buttons::RIGHT),
        _ => None,
    }
}

impl GilrsPads {
    pub fn new() -> GilrsPads {
        let gilrs = match Gilrs::new() {
            Ok(g) => {
                for (id, pad) in g.gamepads() {
                    println!("手柄: {}({})", pad.name(), id);
                }
                Some(g)
            }
            Err(e) => {
                eprintln!("通用手柄初始化失败({e}),键盘仍可用");
                None
            }
        };
        let mut pads = GilrsPads {
            gilrs,
            assign: [None; 2],
            slots: [SlotState::default(); 2],
        };
        // 启动前已连接的手柄按枚举顺序占槽
        if let Some(g) = &pads.gilrs {
            let ids: Vec<GamepadId> = g.gamepads().map(|(id, _)| id).collect();
            for id in ids {
                pads.claim(id);
            }
        }
        pads
    }

    fn claim(&mut self, id: GamepadId) -> Option<usize> {
        if let Some(i) = self.assign.iter().position(|s| *s == Some(id)) {
            return Some(i);
        }
        if let Some(i) = self.assign.iter().position(|s| s.is_none()) {
            self.assign[i] = Some(id);
            println!("手柄 {} → P{}", id, i + 1);
            return Some(i);
        }
        None
    }

    fn release(&mut self, id: GamepadId) {
        if let Some(i) = self.assign.iter().position(|s| *s == Some(id)) {
            self.assign[i] = None;
            self.slots[i] = SlotState::default();
            println!("手柄 {} 断开,P{} 释放", id, i + 1);
        }
    }

    pub fn poll(&mut self) {
        let Some(gilrs) = &mut self.gilrs else { return };
        // 先收集事件,再统一处理,避开借用冲突
        let mut events = Vec::new();
        while let Some(ev) = gilrs.next_event() {
            events.push(ev);
        }
        for ev in events {
            match ev.event {
                EventType::Connected => {
                    self.claim(ev.id);
                }
                EventType::Disconnected => {
                    self.release(ev.id);
                }
                EventType::ButtonPressed(b, _) | EventType::ButtonReleased(b, _) => {
                    let pressed = matches!(ev.event, EventType::ButtonPressed(..));
                    let (Some(slot), Some(target)) = (self.claim(ev.id), map_button(b)) else {
                        continue;
                    };
                    self.slots[slot].buttons.set(target, pressed);
                }
                EventType::AxisChanged(axis, v, _) => {
                    let Some(slot) = self.claim(ev.id) else { continue };
                    let a = &mut self.slots[slot].axis;
                    match axis {
                        Axis::LeftStickX => {
                            a.set(Buttons::LEFT, v < -DEADZONE);
                            a.set(Buttons::RIGHT, v > DEADZONE);
                        }
                        Axis::LeftStickY => {
                            a.set(Buttons::DOWN, v < -DEADZONE);
                            a.set(Buttons::UP, v > DEADZONE);
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }
    }

    pub fn player(&self, i: usize) -> Buttons {
        self.slots[i.min(1)].merged()
    }
}
