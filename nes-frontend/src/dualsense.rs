//! PS5 DualSense 专用 HID 驱动(hidapi)。
//!
//! 为什么需要:Windows 的 gilrs 走 XInput,看不见 DualSense;macOS 的 IOKit
//! 后端对其支持也不稳。此路径直接解析 HID 输入报文,USB 与蓝牙都覆盖:
//!   - USB:        report 0x01,64 字节,按键区在 [8..11)
//!   - 蓝牙基础:   report 0x01,~10 字节,按键区在 [5..8)(配对后默认模式)
//!   - 蓝牙增强:   report 0x31,78 字节,整体较 USB 偏移 +1
//!
//! Linux 上内核 hid-playstation + gilrs 已覆盖 DualSense,默认关闭本路径
//! 以免双路输入;老内核可用 NES_DUALSENSE_HID=1 强制启用(注意 hidraw 权限,
//! 见 README 的 udev 规则)。

use hidapi::{HidApi, HidDevice};
use nes_core::Buttons;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const SONY_VID: u16 = 0x054C;
const DUALSENSE_PIDS: [u16; 2] = [0x0CE6, 0x0DF2]; // DualSense / DualSense Edge

pub struct DualSense {
    shared: Arc<Mutex<[Buttons; 2]>>,
}

fn runtime_enabled() -> bool {
    if std::env::var_os("NES_DUALSENSE_HID").is_some() {
        return true;
    }
    cfg!(any(windows, target_os = "macos"))
}

fn parse_report(buf: &[u8], n: usize) -> Option<Buttons> {
    if n < 10 {
        return None;
    }
    let (stick_off, btn_off) = match (buf[0], n) {
        (0x01, len) if len >= 32 => (1usize, 8usize), // USB 完整报文
        (0x01, _) => (1, 5),                          // 蓝牙基础报文
        (0x31, _) => (2, 9),                          // 蓝牙增强报文
        _ => return None,
    };
    if btn_off + 1 >= n {
        return None;
    }
    let b1 = buf[btn_off];
    let b2 = buf[btn_off + 1];
    let mut out = Buttons::default();
    // 面键:○/△ → A,✕/□ → B(对齐 NES 物理布局)
    out.set(Buttons::A, b1 & 0x40 != 0 || b1 & 0x80 != 0);
    out.set(Buttons::B, b1 & 0x20 != 0 || b1 & 0x10 != 0);
    out.set(Buttons::SELECT, b2 & 0x10 != 0); // Create
    out.set(Buttons::START, b2 & 0x20 != 0); // Options
    // 方向帽:0=上 顺时针至 7=左上,8=松开
    match b1 & 0x0F {
        0 => out.insert(Buttons::UP),
        1 => {
            out.insert(Buttons::UP);
            out.insert(Buttons::RIGHT);
        }
        2 => out.insert(Buttons::RIGHT),
        3 => {
            out.insert(Buttons::DOWN);
            out.insert(Buttons::RIGHT);
        }
        4 => out.insert(Buttons::DOWN),
        5 => {
            out.insert(Buttons::DOWN);
            out.insert(Buttons::LEFT);
        }
        6 => out.insert(Buttons::LEFT),
        7 => {
            out.insert(Buttons::UP);
            out.insert(Buttons::LEFT);
        }
        _ => {}
    }
    // 左摇杆(0..255,中心 128;Y 向下为正)
    let lx = buf[stick_off];
    let ly = buf[stick_off + 1];
    if lx < 64 {
        out.insert(Buttons::LEFT);
    }
    if lx > 192 {
        out.insert(Buttons::RIGHT);
    }
    if ly < 64 {
        out.insert(Buttons::UP);
    }
    if ly > 192 {
        out.insert(Buttons::DOWN);
    }
    Some(out)
}

impl DualSense {
    pub fn start() -> DualSense {
        let shared: Arc<Mutex<[Buttons; 2]>> = Arc::new(Mutex::new([Buttons::default(); 2]));
        if runtime_enabled() {
            let shared2 = shared.clone();
            std::thread::Builder::new()
                .name("dualsense-hid".into())
                .spawn(move || manager(shared2))
                .ok();
        }
        DualSense { shared }
    }

    pub fn player(&self, i: usize) -> Buttons {
        self.shared.lock().unwrap()[i.min(1)]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn neutral(buf: &mut [u8], stick_off: usize, btn_off: usize) {
        buf[stick_off] = 128;
        buf[stick_off + 1] = 128;
        buf[stick_off + 2] = 128;
        buf[stick_off + 3] = 128;
        buf[btn_off] = 0x08; // 方向帽松开
    }

    #[test]
    fn usb_report_face_and_hat() {
        let mut buf = [0u8; 64];
        buf[0] = 0x01;
        neutral(&mut buf, 1, 8);
        buf[8] = 0x08 | 0x40; // ○
        let b = parse_report(&buf, 64).unwrap();
        assert_eq!(b.0, Buttons::A.0);
        buf[8] = 0x20 | 0x08; // ✕
        assert_eq!(parse_report(&buf, 64).unwrap().0, Buttons::B.0);
        buf[8] = 6; // 帽=左
        assert_eq!(parse_report(&buf, 64).unwrap().0, Buttons::LEFT.0);
        buf[8] = 0x08;
        buf[9] = 0x30; // Create+Options
        assert_eq!(
            parse_report(&buf, 64).unwrap().0,
            Buttons::SELECT.0 | Buttons::START.0
        );
    }

    #[test]
    fn usb_left_stick() {
        let mut buf = [0u8; 64];
        buf[0] = 0x01;
        neutral(&mut buf, 1, 8);
        buf[1] = 10; // 左推
        buf[2] = 250; // 下推
        let b = parse_report(&buf, 64).unwrap();
        assert_eq!(b.0, Buttons::LEFT.0 | Buttons::DOWN.0);
    }

    #[test]
    fn bt_simple_report() {
        let mut buf = [0u8; 10];
        buf[0] = 0x01;
        neutral(&mut buf, 1, 5);
        buf[5] = 0x08 | 0x80; // △ → A
        assert_eq!(parse_report(&buf, 10).unwrap().0, Buttons::A.0);
    }

    #[test]
    fn bt_enhanced_report() {
        let mut buf = [0u8; 78];
        buf[0] = 0x31;
        neutral(&mut buf, 2, 9);
        buf[9] = 0; // 帽=上
        assert_eq!(parse_report(&buf, 78).unwrap().0, Buttons::UP.0);
    }
}

fn manager(shared: Arc<Mutex<[Buttons; 2]>>) {
    let mut api = match HidApi::new() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("DualSense HID 初始化失败({e})");
            return;
        }
    };
    let mut open: [Option<(String, HidDevice)>; 2] = [None, None];
    let mut last_scan = Instant::now() - Duration::from_secs(10);
    loop {
        // 周期性扫描热插拔
        if last_scan.elapsed() > Duration::from_secs(2) {
            last_scan = Instant::now();
            let _ = api.refresh_devices();
            let infos: Vec<(String, u16)> = api
                .device_list()
                .filter(|d| {
                    d.vendor_id() == SONY_VID && DUALSENSE_PIDS.contains(&d.product_id())
                })
                .map(|d| (d.path().to_string_lossy().into_owned(), d.product_id()))
                .collect();
            for (path, _pid) in infos {
                let already = open
                    .iter()
                    .flatten()
                    .any(|(p, _)| *p == path);
                if already {
                    continue;
                }
                if let Some(slot) = open.iter().position(|s| s.is_none()) {
                    match api.open_path(std::ffi::CString::new(path.clone()).unwrap().as_c_str()) {
                        Ok(dev) => {
                            println!("DualSense → P{slot_n}", slot_n = slot + 1);
                            open[slot] = Some((path, dev));
                        }
                        Err(e) => eprintln!("DualSense 打开失败({e});Linux 请检查 hidraw 权限"),
                    }
                }
            }
        }
        // 非阻塞排空各设备报文
        for slot in 0..2 {
            let mut dead = false;
            if let Some((_, dev)) = &open[slot] {
                let mut buf = [0u8; 96];
                loop {
                    match dev.read_timeout(&mut buf, 0) {
                        Ok(0) => break,
                        Ok(n) => {
                            if let Some(b) = parse_report(&buf, n) {
                                shared.lock().unwrap()[slot] = b;
                            }
                        }
                        Err(_) => {
                            dead = true;
                            break;
                        }
                    }
                }
            }
            if dead {
                println!("DualSense 断开,P{} 释放", slot + 1);
                open[slot] = None;
                shared.lock().unwrap()[slot] = Buttons::default();
            }
        }
        std::thread::sleep(Duration::from_millis(4));
    }
}
