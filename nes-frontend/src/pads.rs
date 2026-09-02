//! 通用手柄(gilrs):双人槽位分配、热插拔、按键与摇杆/方向帽映射、
//! **按键学习**(F9)与原始码自定义映射。
//!
//! gilrs 底层:Linux = evdev/udev,Windows = XInput,macOS = IOKit;自带
//! SDL_GameControllerDB 映射。但大量山寨/老式 USB 手柄不在库里(或 GUID 与库
//! 里另一款撞车),gilrs 只能给出 `Button::Unknown` + 原始码,方向键还常以
//! 方向帽轴(DPadX/DPadY)上报——表现就是"只有 Start 对、其余错位或无效"。
//! 因此:
//!   1. 默认映射同时接受命名按键、方向帽轴、左摇杆,以及 Linux evdev 原始码兜底;
//!   2. F9 进入学习:按提示依次按 A B SELECT START 上 下 左 右(再按 F9 跳过一项),
//!      任何按键/轴都按原始码记录,按手柄名保存到 ~/.rnes-padmap.txt,下次自动套用;
//!   3. NES_PAD_DEBUG=1 打印每个原始事件,便于排查;
//!   4. 仍可用 SDL_GAMECONTROLLERCONFIG 注入 SDL 映射串(gilrs 原生支持)。

use gilrs::{Axis, Button, EventType, GamepadId, Gilrs};
use nes_core::Buttons;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{Duration, Instant};

const DEADZONE: f32 = 0.5;
const NAMES: [&str; 8] = ["A", "B", "SELECT", "START", "UP", "DOWN", "LEFT", "RIGHT"];
const BITS: [Buttons; 8] = [
    Buttons::A,
    Buttons::B,
    Buttons::SELECT,
    Buttons::START,
    Buttons::UP,
    Buttons::DOWN,
    Buttons::LEFT,
    Buttons::RIGHT,
];

/// 一个绑定:按键原始码,或轴原始码 + 方向(true = 正向)
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Bind {
    Btn(u32),
    Axis(u32, bool),
}

/// 学习得到的自定义映射(按 NES 键序)
#[derive(Clone, Default, Debug, PartialEq)]
pub struct PadMap {
    binds: [Option<Bind>; 8],
}

impl PadMap {
    fn serialize(&self) -> String {
        let mut parts = Vec::new();
        for (i, b) in self.binds.iter().enumerate() {
            let v = match b {
                Some(Bind::Btn(c)) => format!("b:{c}"),
                Some(Bind::Axis(c, true)) => format!("a:{c}+"),
                Some(Bind::Axis(c, false)) => format!("a:{c}-"),
                None => "-".to_string(),
            };
            parts.push(format!("{}={}", NAMES[i].to_lowercase(), v));
        }
        parts.join(" ")
    }

    fn parse(s: &str) -> Option<PadMap> {
        let mut m = PadMap::default();
        let mut any = false;
        for kv in s.split_whitespace() {
            let (k, v) = kv.split_once('=')?;
            let idx = NAMES.iter().position(|n| n.eq_ignore_ascii_case(k))?;
            m.binds[idx] = parse_bind(v);
            any = true;
        }
        any.then_some(m)
    }

    /// 事件按此映射产生的按键变化:返回 (位, 是否按下) 列表
    fn apply(&self, ev: &EventType, out: &mut Buttons) -> bool {
        let mut hit = false;
        match ev {
            EventType::ButtonPressed(_, code) | EventType::ButtonReleased(_, code) => {
                let pressed = matches!(ev, EventType::ButtonPressed(..));
                let c = code.into_u32();
                for (i, b) in self.binds.iter().enumerate() {
                    if *b == Some(Bind::Btn(c)) {
                        out.set(BITS[i], pressed);
                        hit = true;
                    }
                }
            }
            EventType::AxisChanged(_, v, code) => {
                let c = code.into_u32();
                for (i, b) in self.binds.iter().enumerate() {
                    if let Some(Bind::Axis(bc, pos)) = b {
                        if *bc == c {
                            let on = if *pos { *v > DEADZONE } else { *v < -DEADZONE };
                            out.set(BITS[i], on);
                            hit = true;
                        }
                    }
                }
            }
            _ => {}
        }
        hit
    }
}

fn parse_bind(v: &str) -> Option<Bind> {
    if v == "-" {
        return None;
    }
    let (kind, rest) = v.split_once(':')?;
    match kind {
        "b" => rest.parse().ok().map(Bind::Btn),
        "a" => {
            let (num, sign) = rest.split_at(rest.len().checked_sub(1)?);
            let code: u32 = num.parse().ok()?;
            match sign {
                "+" => Some(Bind::Axis(code, true)),
                "-" => Some(Bind::Axis(code, false)),
                _ => None,
            }
        }
        _ => None,
    }
}

#[derive(Default, Clone, Copy)]
struct SlotState {
    buttons: Buttons,
    axis: Buttons,
    custom: Buttons,
}

impl SlotState {
    fn merged(self) -> Buttons {
        Buttons(self.buttons.0 | self.axis.0 | self.custom.0)
    }
}

struct Learn {
    id: Option<GamepadId>,
    step: usize,
    map: PadMap,
    cooldown: Instant,
    hold_axis: Option<u32>,
}

pub struct GilrsPads {
    gilrs: Option<Gilrs>,
    assign: [Option<GamepadId>; 2],
    slots: [SlotState; 2],
    /// 各槽位生效的自定义映射(None = 默认映射)
    custom: [Option<PadMap>; 2],
    /// 按手柄名保存的映射库
    maps: HashMap<String, PadMap>,
    learn: Option<Learn>,
    debug: bool,
    status_dirty: bool,
}

fn map_button(b: Button) -> Option<Buttons> {
    match b {
        // 物理布局:右侧(East/PS ○)= NES A;下/左(South ✕ / West □)= NES B
        Button::East | Button::North => Some(Buttons::A),
        Button::South | Button::West => Some(Buttons::B),
        Button::Start => Some(Buttons::START),
        Button::Select => Some(Buttons::SELECT),
        Button::DPadUp => Some(Buttons::UP),
        Button::DPadDown => Some(Buttons::DOWN),
        Button::DPadLeft => Some(Buttons::LEFT),
        Button::DPadRight => Some(Buttons::RIGHT),
        _ => None,
    }
}

/// 无映射手柄兜底(Linux evdev 键码;其他平台原始码含义不定,交给学习模式)
#[cfg(target_os = "linux")]
fn map_raw(code: u32) -> Option<Buttons> {
    match code {
        305 | 307 => Some(Buttons::A),   // BTN_EAST / BTN_NORTH
        304 | 308 => Some(Buttons::B),   // BTN_SOUTH / BTN_WEST
        314 => Some(Buttons::SELECT),    // BTN_SELECT
        315 => Some(Buttons::START),     // BTN_START
        544 => Some(Buttons::UP),        // BTN_DPAD_*
        545 => Some(Buttons::DOWN),
        546 => Some(Buttons::LEFT),
        547 => Some(Buttons::RIGHT),
        // 老式 joystick 类手柄:BTN_TRIGGER/THUMB/THUMB2/TOP 与 BASE3/BASE4
        289 | 291 => Some(Buttons::A),
        288 | 290 => Some(Buttons::B),
        296 => Some(Buttons::SELECT),
        297 => Some(Buttons::START),
        _ => None,
    }
}

#[cfg(not(target_os = "linux"))]
fn map_raw(_code: u32) -> Option<Buttons> {
    None
}

/// Windows WGI 原始控制器(D-Input 手柄,无 SDL 条目时 gilrs 只有按序号猜的
/// Xbox 序默认映射):原始码 = 类别<<16 | 序号(0 按键 / 1 轴 / 2 方向帽)。
/// 面键取两大家族的交集——PS 序(△○✕□ = 0123,北通/多数国产手柄)与
/// Xbox 序(ABXY = 0123)里,序号 1 都是右键 = NES A,序号 0/2/3 归 NES B;
/// 8/9 = Select/Start。这样两大家族的 A/B/Start 不学习也对。
fn map_wgi_raw_button(code: u32) -> Option<Buttons> {
    if code >> 16 != 0 {
        return None;
    }
    match code & 0xFFFF {
        1 => Some(Buttons::A),
        0 | 2 | 3 => Some(Buttons::B),
        8 => Some(Buttons::SELECT),
        9 => Some(Buttons::START),
        _ => None,
    }
}

/// WGI 方向帽:Switch 类轴码,偶数 = X(左 -1 / 右 +1),奇数 = Y(上 -1 / 下 +1)
fn wgi_switch_axis(code: u32) -> Option<bool> {
    if code >> 16 != 2 {
        return None;
    }
    Some(code & 1 == 1)
}

fn map_path() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("NES_PAD_MAP_FILE") {
        return Some(PathBuf::from(p));
    }
    let home = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE"))?;
    Some(PathBuf::from(home).join(".rnes-padmap.txt"))
}

fn load_maps() -> HashMap<String, PadMap> {
    let mut out = HashMap::new();
    let Some(p) = map_path() else { return out };
    let Ok(text) = std::fs::read_to_string(&p) else { return out };
    for line in text.lines() {
        let Some((name, rest)) = line.split_once('\t') else { continue };
        if let Some(m) = PadMap::parse(rest) {
            out.insert(name.to_string(), m);
        }
    }
    if !out.is_empty() {
        println!("已载入手柄映射 {}(共 {} 条)", p.display(), out.len());
    }
    out
}

fn save_maps(maps: &HashMap<String, PadMap>) {
    let Some(p) = map_path() else { return };
    let mut text = String::from("# rnes 手柄映射:手柄名<TAB>键=绑定(b:按键码 / a:轴码±),F9 重新学习\n");
    let mut names: Vec<&String> = maps.keys().collect();
    names.sort();
    for n in names {
        text.push_str(&format!("{}\t{}\n", n, maps[n].serialize()));
    }
    match std::fs::write(&p, text) {
        Ok(()) => println!("手柄映射已保存到 {}", p.display()),
        Err(e) => eprintln!("手柄映射保存失败({e})"),
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
            custom: [None, None],
            maps: load_maps(),
            learn: None,
            debug: std::env::var_os("NES_PAD_DEBUG").is_some(),
            status_dirty: false,
        };
        if let Some(g) = &pads.gilrs {
            let ids: Vec<GamepadId> = g.gamepads().map(|(id, _)| id).collect();
            for id in ids {
                pads.claim(id);
            }
        }
        println!("手柄提示:若按键错位/无效,按 F9 进入按键学习(依次按 A B SELECT START 上 下 左 右)");
        pads
    }

    /// gilrs 对该手柄只有默认映射(无 SDL 条目)——Windows 下即 WGI 原始控制器
    fn driver_mapped(&self, id: GamepadId) -> bool {
        self.gilrs
            .as_ref()
            .map(|g| g.gamepad(id).mapping_source() == gilrs::MappingSource::Driver)
            .unwrap_or(false)
    }

    fn pad_name(&self, id: GamepadId) -> String {
        self.gilrs
            .as_ref()
            .map(|g| g.gamepad(id).name().to_string())
            .unwrap_or_default()
    }

    fn claim(&mut self, id: GamepadId) -> Option<usize> {
        if let Some(i) = self.assign.iter().position(|s| *s == Some(id)) {
            return Some(i);
        }
        if let Some(i) = self.assign.iter().position(|s| s.is_none()) {
            self.assign[i] = Some(id);
            let name = self.pad_name(id);
            self.custom[i] = self.maps.get(&name).cloned();
            println!(
                "手柄 {} → P{}{}",
                id,
                i + 1,
                if self.custom[i].is_some() { "(套用已保存的自定义映射)" } else { "" }
            );
            return Some(i);
        }
        None
    }

    fn release(&mut self, id: GamepadId) {
        if let Some(i) = self.assign.iter().position(|s| *s == Some(id)) {
            self.assign[i] = None;
            self.slots[i] = SlotState::default();
            self.custom[i] = None;
            println!("手柄 {} 断开,P{} 释放", id, i + 1);
        }
    }

    /// F9:未在学习则开始;学习中则跳过当前项
    pub fn learn_key(&mut self) {
        match &mut self.learn {
            None => {
                self.learn = Some(Learn {
                    id: None,
                    step: 0,
                    map: PadMap::default(),
                    cooldown: Instant::now(),
                    hold_axis: None,
                });
                println!("手柄学习开始:请在手柄上依次按 {}(F9 跳过一项)", NAMES.join(" "));
            }
            Some(l) => {
                println!("跳过 {}", NAMES[l.step]);
                l.step += 1;
                l.cooldown = Instant::now();
            }
        }
        self.status_dirty = true;
        self.finish_learn_if_done();
    }

    fn finish_learn_if_done(&mut self) {
        let done = self.learn.as_ref().map(|l| l.step >= 8).unwrap_or(false);
        if !done {
            return;
        }
        let l = self.learn.take().unwrap();
        self.status_dirty = true;
        let Some(id) = l.id else {
            println!("手柄学习结束:未收到任何手柄输入,未保存");
            return;
        };
        let name = self.pad_name(id);
        println!("手柄学习完成 [{}]:{}", name, l.map.serialize());
        self.maps.insert(name, l.map.clone());
        save_maps(&self.maps);
        if let Some(slot) = self.claim(id) {
            self.custom[slot] = Some(l.map);
            self.slots[slot] = SlotState::default();
        }
    }

    /// 学习中的提示文本(供窗口标题显示);None = 未在学习
    pub fn learn_status(&self) -> Option<String> {
        self.learn.as_ref().map(|l| {
            format!(
                "手柄学习 {}/8:请按 [{}](F9 跳过)",
                l.step + 1,
                NAMES.get(l.step).copied().unwrap_or("?")
            )
        })
    }

    /// 标题是否需要刷新(学习开始/推进/结束时为真,读后清零)
    pub fn take_status_dirty(&mut self) -> bool {
        std::mem::take(&mut self.status_dirty)
    }

    fn learn_event(&mut self, id: GamepadId, ev: &EventType) -> bool {
        let Some(l) = &mut self.learn else { return false };
        if l.cooldown.elapsed() < Duration::from_millis(250) {
            return true;
        }
        let bind = match ev {
            EventType::ButtonPressed(_, code) => Some(Bind::Btn(code.into_u32())),
            EventType::AxisChanged(_, v, code) => {
                let c = code.into_u32();
                if l.hold_axis == Some(c) {
                    if v.abs() < 0.3 {
                        l.hold_axis = None;
                    }
                    return true;
                }
                if v.abs() > 0.6 {
                    l.hold_axis = Some(c);
                    Some(Bind::Axis(c, *v > 0.0))
                } else {
                    None
                }
            }
            _ => None,
        };
        let Some(b) = bind else { return true };
        l.id.get_or_insert(id);
        if l.id != Some(id) {
            return true; // 只学第一只发声的手柄
        }
        println!("  {} ← {:?}", NAMES[l.step], b);
        l.map.binds[l.step] = Some(b);
        l.step += 1;
        l.cooldown = Instant::now();
        self.status_dirty = true;
        self.finish_learn_if_done();
        true
    }

    pub fn poll(&mut self) {
        let Some(gilrs) = &mut self.gilrs else { return };
        let mut events = Vec::new();
        while let Some(ev) = gilrs.next_event() {
            events.push(ev);
        }
        for ev in events {
            if self.debug {
                println!("[pad {}] {:?}", ev.id, ev.event);
            }
            match ev.event {
                EventType::Connected => {
                    self.claim(ev.id);
                    continue;
                }
                EventType::Disconnected => {
                    self.release(ev.id);
                    continue;
                }
                _ => {}
            }
            if self.learn.is_some() && self.learn_event(ev.id, &ev.event) {
                continue;
            }
            let Some(slot) = self.claim(ev.id) else { continue };
            // 自定义映射优先(原始码),命中即不再走默认
            if let Some(m) = &self.custom[slot] {
                let mut c = self.slots[slot].custom;
                if m.apply(&ev.event, &mut c) {
                    self.slots[slot].custom = c;
                    continue;
                }
            }
            let wgi_raw = cfg!(target_os = "windows") && self.driver_mapped(ev.id);
            match ev.event {
                EventType::ButtonPressed(b, code) | EventType::ButtonReleased(b, code) => {
                    let pressed = matches!(ev.event, EventType::ButtonPressed(..));
                    let raw = code.into_u32();
                    let target = if wgi_raw { map_wgi_raw_button(raw) } else { None };
                    let target = target.or_else(|| map_button(b)).or_else(|| map_raw(raw));
                    if let Some(target) = target {
                        self.slots[slot].buttons.set(target, pressed);
                    }
                }
                EventType::AxisChanged(axis, v, code) => {
                    let a = &mut self.slots[slot].axis;
                    if wgi_raw {
                        if let Some(is_y) = wgi_switch_axis(code.into_u32()) {
                            if is_y {
                                a.set(Buttons::UP, v < -DEADZONE);
                                a.set(Buttons::DOWN, v > DEADZONE);
                            } else {
                                a.set(Buttons::LEFT, v < -DEADZONE);
                                a.set(Buttons::RIGHT, v > DEADZONE);
                            }
                            continue;
                        }
                    }
                    match axis {
                        Axis::LeftStickX | Axis::DPadX => {
                            a.set(Buttons::LEFT, v < -DEADZONE);
                            a.set(Buttons::RIGHT, v > DEADZONE);
                        }
                        Axis::LeftStickY | Axis::DPadY => {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn padmap_roundtrip() {
        let mut m = PadMap::default();
        m.binds[0] = Some(Bind::Btn(305));
        m.binds[1] = Some(Bind::Btn(304));
        m.binds[3] = Some(Bind::Btn(315));
        m.binds[4] = Some(Bind::Axis(17, false));
        m.binds[5] = Some(Bind::Axis(17, true));
        let s = m.serialize();
        assert_eq!(
            s,
            "a=b:305 b=b:304 select=- start=b:315 up=a:17- down=a:17+ left=- right=-"
        );
        assert_eq!(PadMap::parse(&s).unwrap(), m);
    }

    #[test]
    fn wgi_raw_codes() {
        // 类别<<16 | 序号:按键 0-3 面键,8/9 Select/Start;方向帽 Switch 类
        assert_eq!(map_wgi_raw_button(1), Some(Buttons::A));
        assert_eq!(map_wgi_raw_button(2), Some(Buttons::B));
        assert_eq!(map_wgi_raw_button(0), Some(Buttons::B));
        assert_eq!(map_wgi_raw_button(8), Some(Buttons::SELECT));
        assert_eq!(map_wgi_raw_button(9), Some(Buttons::START));
        assert_eq!(map_wgi_raw_button(4), None);
        assert_eq!(map_wgi_raw_button(0x10000), None); // 轴不是按键
        assert_eq!(wgi_switch_axis(0x20000), Some(false));
        assert_eq!(wgi_switch_axis(0x20001), Some(true));
        assert_eq!(wgi_switch_axis(0x10001), None);
    }

    #[test]
    fn parse_bind_forms() {
        assert_eq!(parse_bind("b:9"), Some(Bind::Btn(9)));
        assert_eq!(parse_bind("a:16+"), Some(Bind::Axis(16, true)));
        assert_eq!(parse_bind("a:16-"), Some(Bind::Axis(16, false)));
        assert_eq!(parse_bind("-"), None);
        assert_eq!(parse_bind("x:1"), None);
    }
}
