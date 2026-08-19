#!/usr/bin/env python3
"""C172S 真实气动模型 → 6502 整数查找表(src/aero_tables.inc)。

浮点侧用真实公式:
  升力     L = q·S·CL,CL = CL0(襟翼) + CLa·α,到 CLmax(襟翼) 后失速跌落
  阻力     D = q·S·(CD0(襟翼) + k·CL²),k = 1/(π·e·AR),地效时诱导阻力×0.55
  推力     T = min(T_static·f(油门), η(V)·P·550/V),定距桨效率随速度
  纵向     dV/dt = g·(T-D)/W - g·sinγ         (能量交换:拉杆掉速、俯冲增速)
  航迹角   准静态:α_req = 使 L=W·(1/cosφ) 的迎角(由 CL 反解);
           γ → θ - α_req,一阶响应 τ≈1s。速度低到 CL 需求超 CLmax 时
           α_req 越限 → γ_target 大幅转负 → 掉机头/下沉 = 失速,自然涌现;
           坡度 φ 使 α_req×1/cosφ → 转弯失速速度上升,同样自然涌现
  转弯     dψ/dt = g·tanφ/V                    (真实转弯率)

标定目标(C172S POH,2550 lb):
  失速 48/46/43/40 KIAS(襟翼 0/10/20/30) · Vy≈74,海平面爬升 ≈730 fpm
  满油门平飞 ≈122-126 KIAS · 最佳滑翔 ≈68 KIAS,滑翔比 ≈9-10
整数侧是浮点侧的定点孪生(同一套表、同一套移位),先在本脚本内做 60Hz
仿真复算 POH 数字,通过后才发射 —— 汇编照抄本文件打印的移位配方。
"""
import math
import sys

# ---------------- 机体常数 ----------------
W = 2550.0          # lb
S = 174.0           # ft²
AR = 7.48
E_OSW = 0.75
K_IND = 1.0 / (math.pi * E_OSW * AR)      # 0.0568
RHO = 0.002377      # slug/ft³(海平面;起落航线高度差可忽略)
G = 32.17           # ft/s²
KT2FPS = 1.688

CLA = 0.085         # 升力线斜率 /deg
CL0 = [0.45, 0.65, 0.85, 1.00]            # 襟翼 0/10/20/30(ΔCL≈+0.55)
VS_TGT = [48.0, 46.0, 43.0, 40.0]         # 失速标定(KIAS)
CLMAX = [2.0 * W / (RHO * S * (v * KT2FPS) ** 2) for v in VS_TGT]
CD0 = [0.036, 0.048, 0.068, 0.093]        # 含固定起落架/支柱;襟翼增量
CD0_IDLE = 0.006                          # 风车桨(收油门滑翔)
P_BHP = 180.0
PFRAC = [0.045, 0.11, 0.20, 0.31, 0.43, 0.56, 0.70, 0.85, 1.00]   # 油门 0..8
T_STATIC = 520.0    # lbf 静推力(满油门)
GE_FACT = 0.55      # 地效诱导阻力系数(h < 25 ft)


def eta(v_kn):
    return min(0.78, 0.24 + 0.0048 * v_kn)


def thrust(thr, v_kn):
    p = P_BHP * PFRAC[thr]
    cap = T_STATIC * PFRAC[thr] ** 0.8
    if v_kn < 1:
        return cap
    return min(cap, eta(v_kn) * p * 550.0 / (v_kn * KT2FPS))


def cl_of(alpha_deg, f):
    """升力系数,含失速跌落(每超 1° 掉 0.05)。"""
    cl = CL0[f] + CLA * alpha_deg
    a_crit = (CLMAX[f] - CL0[f]) / CLA
    if alpha_deg > a_crit:
        cl = CLMAX[f] - 0.05 * (alpha_deg - a_crit)
    return max(cl, 0.0)


def drag(v_kn, cl, f, thr, in_ge):
    q = 0.5 * RHO * (v_kn * KT2FPS) ** 2
    cd0 = CD0[f] + (CD0_IDLE if thr == 0 else 0.0)
    ki = K_IND * (GE_FACT if in_ge else 1.0)
    return q * S * (cd0 + ki * cl * cl)


# ---------------- 浮点侧 POH 校验 ----------------

def level_cl(v_kn):
    q = 0.5 * RHO * (v_kn * KT2FPS) ** 2
    return W / (q * S)


def roc_fpm(v_kn, thr, f=0):
    t = thrust(thr, v_kn)
    d = drag(v_kn, level_cl(v_kn), f, thr, False)
    return (t - d) * v_kn * KT2FPS * 60.0 / W


def float_report():
    print("== 浮点模型 POH 校验 ==")
    print("失速(标定) :", " ".join(f"{v:.0f}" for v in VS_TGT),
          " CLmax:", " ".join(f"{c:.2f}" for c in CLMAX))
    best_v, best_roc = max(((v, roc_fpm(v, 8)) for v in range(55, 100)),
                           key=lambda t: t[1])
    print(f"Vy ≈ {best_v} KIAS,ROC ≈ {best_roc:.0f} fpm  (目标 74 / 730)")
    vmax = next(v for v in range(140, 60, -1) if roc_fpm(v, 8) > 0)
    print(f"满油门平飞 ≈ {vmax} KIAS  (目标 122-126)")
    glides = []
    for v in range(55, 95):
        cl = level_cl(v)
        d = drag(v, cl, 0, 0, False)
        glides.append((W / d, v))
    gr, gv = max(glides)
    print(f"最佳滑翔 ≈ {gv} KIAS,滑翔比 ≈ {gr:.1f}  (目标 68 / 9-10)")
    # 进近:65 KIAS 襟翼 30,1500-1700 RPM 应得 -400~-600 fpm
    for thr in (2, 3):
        v = 65.0
        t = thrust(thr, v)
        d = drag(v, level_cl(v), 3, thr, False)
        vs = (t - d) * v * KT2FPS * 60.0 / W
        print(f"进近 65kt 襟翼30 油门{thr}: VS ≈ {vs:.0f} fpm")


# ---------------- 整数表 ----------------
# 单位约定:
#   V:整数节(0..160)   θ/α:半度 hd(有符号)   γ:半度 8.8(有符号 16 位)
#   CL64:CL×64          TW/DW/SINg:g×256
# 每帧(60Hz)配方(汇编照抄):
#   CLR    = CLR64[V](平飞所需 CL64,>255 截断=远低于失速速度)
#   α_req  = (CLR - CL064[f]) × 94 >> 8   (hd;负→钳 0 以下按线性)
#   转弯:  α_req = α_req × INVC[bank] >> 8 (1/cosφ,坡度抬失速)
#   钳:    α_req ≤ crit_ai[f]+24;喇叭:α_req ≥ horn_ai[f]
#   γ_t88  = (θ_hd - α_req) << 8;γ88 += (γ_t88 - γ88) 算术>>6(τ≈1.1s)
#   CL_eff = min(CLR, CLMAX64[f]) → 诱导阻力
#   DW256  = PAR[f(+4 收油)][V>>2] + ((CL_eff²>>6) × KQ[V] >> 8)(地效 KQ×5/8)
#   TW256  = TW[thr][V>>3]
#   SINg   = (γ88 算术>>6) × 143 >> 8(≈sinγ×256)
#   dV88   = (TW - DW - SINg) × 81 >> 8;地面另加滚阻/刹车
#   dh88   = V × γ88 >> 12
#   dψ88   = RECV[V] × TANK[bank档] >> 8(bdeg)
#   d位置88 = V × sin116[ψ>>2] >> 5(ft/2)

def emit():
    lines = []
    out = lines.append
    out("; 由 tools/gen_aero.py 生成 —— C172S 真实气动整数表,勿手改")

    def table8(name, vals, per=16):
        assert all(0 <= v <= 255 for v in vals), (name, min(vals), max(vals))
        out(f"{name}:")
        for i in range(0, len(vals), per):
            out("        .byte " + ",".join(str(v) for v in vals[i:i + per]))

    VMAX = 160
    # 平飞 CL 需求(×64):64·W/(qS)
    clr = []
    for v in range(VMAX + 1):
        q = 0.5 * RHO * (max(v, 1) * KT2FPS) ** 2
        clr.append(min(255, round(64.0 * W / (q * S))))
    table8("clr_tab", clr)
    table8("cl0_tab", [round(64 * c) for c in CL0])
    table8("clmax_tab", [round(64 * c) for c in CLMAX])
    # α 反解系数:1/(CLa·2 per hd ×64) ×256 = 256/(0.085·2·64)?  CLa/hd=0.0425:
    #   α_hd = ΔCL64/(0.0425·64) = ΔCL64/2.72 → ×94>>8
    out("AREQ_K = 94              ; α_req_hd = ΔCL64×94>>8")
    # 失速警告/临界迎角(hd,含 +16 偏置前的原值→直接存 hd)
    horn = []
    crit = []
    for f in range(4):
        a_crit = (CLMAX[f] - CL0[f]) / CLA
        crit.append(round(a_crit * 2))
        horn.append(round((a_crit - 1.6) * 2))
    table8("crit_hd", crit)
    table8("horn_hd", horn)

    # 寄生阻力 PAR[f 或 f+4(收油)][V>>2]
    for fi in range(8):
        f = fi & 3
        cd0 = CD0[f] + (CD0_IDLE if fi >= 4 else 0.0)
        vals = []
        for vi in range(0, VMAX + 1, 4):
            q = 0.5 * RHO * (vi * KT2FPS) ** 2
            vals.append(min(255, round(cd0 * q * S / W * 256)))
        table8(f"par_tab{fi}", vals)
    out("par_lo:  .byte " + ",".join(f"<par_tab{i}" for i in range(8)))
    out("par_hi:  .byte " + ",".join(f">par_tab{i}" for i in range(8)))

    # 诱导:DWi256 = (CL64²>>6) × KQ[V] >> 8,KQ = 1024·k·qS/W
    kq = []
    for v in range(VMAX + 1):
        q = 0.5 * RHO * (v * KT2FPS) ** 2
        kq.append(min(255, round(1024.0 * K_IND * q * S / W)))
    table8("kq_tab", kq)

    # 推力 2D:TW256[thr][V>>3]
    for thr in range(9):
        vals = []
        for vi in range(0, VMAX + 1, 8):
            vals.append(min(255, round(thrust(thr, max(vi, 1)) / W * 256)))
        table8(f"tw_tab{thr}", vals)
    out("tw_lo:  .byte " + ",".join(f"<tw_tab{t}" for t in range(9)))
    out("tw_hi:  .byte " + ",".join(f">tw_tab{t}" for t in range(9)))

    # 转弯与坡度
    recv = [255, 255]
    for v in range(2, VMAX + 1):
        recv.append(min(255, round(2048.0 / v)))
    table8("recv_tab", recv)
    banks = [0, 10, 20, 30]
    table8("tank_tab", [round(414 * math.tan(math.radians(b))) for b in banks])
    # 1/cosφ 超 1 字节 → 存增量:α_corr = α + (α×invc_d>>8)
    table8("invc_d_tab", [round(256 / math.cos(math.radians(b))) - 256
                          for b in banks])

    # sin 表(位置推进):116×sin,ψ 高 6 位;负值按补码存
    table8("sin116", [round(116 * math.sin(2 * math.pi * i / 64)) % 256
                      for i in range(64)])
    # atan 表(跑道方位):atan(i/32) 的 bdeg(0..32 → 0..45°)
    table8("atan_tab", [round(math.degrees(math.atan(i / 32.0)) * 256 / 360)
                        for i in range(33)])
    return "\n".join(lines) + "\n"


# ---------------- 整数孪生 60Hz 仿真校验 ----------------

def asr16(x, n):
    """16 位算术右移(Python 大整数直接 >> 即算术)。"""
    return x >> n


class IntSim:
    """按发射的同一套整数配方跑 60Hz(Python 孪生 6502 管线)。"""

    def __init__(self):
        self.clr = [min(255, round(64.0 * W / (0.5 * RHO * (max(v, 1) * KT2FPS) ** 2
                    * S))) for v in range(161)]
        self.cl0 = [round(64 * c) for c in CL0]
        self.clmax = [round(64 * c) for c in CLMAX]
        self.crit = [round((CLMAX[f] - CL0[f]) / CLA * 2) for f in range(4)]
        self.horn = [round(((CLMAX[f] - CL0[f]) / CLA - 1.6) * 2) for f in range(4)]
        self.par = [[min(255, round((CD0[fi & 3] + (CD0_IDLE if fi >= 4 else 0))
                    * 0.5 * RHO * (vi * KT2FPS) ** 2 * S / W * 256))
                    for vi in range(0, 161, 4)] for fi in range(8)]
        self.kq = [min(255, round(1024.0 * K_IND * 0.5 * RHO * (v * KT2FPS) ** 2
                   * S / W)) for v in range(161)]
        self.tw = [[min(255, round(thrust(t, max(vi, 1)) / W * 256))
                    for vi in range(0, 161, 8)] for t in range(9)]
        self.invc = [round(256 / math.cos(math.radians(b))) for b in (0, 10, 20, 30)]
        self.reset()

    def reset(self):
        self.v88 = 0            # 节 8.8
        self.g88 = 0            # γ 半度 8.8(有符号)
        self.h88 = 0            # ft 8.8
        self.theta_hd = 0       # 姿态半度(有符号整数)
        self.on_ground = True
        self.horn_on = False

    def step(self, thr, flaps, bank_idx=0, brake=False):
        V = max(0, self.v88 >> 8)
        Vc = min(V, 160)
        # 平飞迎角需求(反解升力)
        dcl = self.clr[Vc] - self.cl0[flaps]        # 可为负(高速/大襟翼低头配平)
        a_req = (dcl * 94) >> 8                      # Python >> 即算术移位
        if a_req > 0:
            a_req = (a_req * self.invc[bank_idx]) >> 8   # 坡度 → 需更大迎角
        self.horn_on = (not self.on_ground) and a_req >= self.horn[flaps]
        a_req_c = max(-24, min(a_req, self.crit[flaps] + 24))
        # 航迹角一阶趋近
        if self.on_ground:
            self.g88 = 0
            if self.theta_hd >= a_req_c and V >= 45 and self.theta_hd > 0:
                self.on_ground = False
        else:
            gt88 = (self.theta_hd - a_req_c) << 8
            self.g88 += asr16(gt88 - self.g88, 6)
        # 阻力:空中 CL_eff = min(需求, CLmax);地面由姿态决定(滑跑时机翼没使劲)
        if self.on_ground:
            cl_eff = min(self.clmax[flaps],
                         self.cl0[flaps] + max(0, (self.theta_hd * 11) >> 2))
        else:
            cl_eff = (self.clr[Vc] * self.invc[bank_idx]) >> 8   # 转弯升力需求↑
            cl_eff = min(cl_eff, self.clmax[flaps])
        fi = flaps + (4 if thr == 0 else 0)
        par = self.par[fi][Vc >> 2]
        kq = self.kq[Vc]
        if self.h88 < 25 * 256 and not self.on_ground:
            kq = kq * 5 >> 3
        ind = (((cl_eff * cl_eff) >> 6) * kq) >> 8
        dw = par + ind
        if self.on_ground:
            dw += 25 if brake else 5
        tw = self.tw[thr][Vc >> 3]
        sing = (asr16(self.g88, 6) * 143) >> 8
        dv = ((tw - dw - sing) * 81) >> 8
        self.v88 = max(0, self.v88 + dv)
        if not self.on_ground:
            dh = (Vc * self.g88) >> 12
            self.h88 += dh
            if self.h88 <= 0 and self.g88 < 0:
                self.h88 = 0
                self.on_ground = True
                self.g88 = 0
        return V

    def vs_fpm(self):
        V = self.v88 >> 8
        return (V * self.g88 >> 12) * 60 * 60 / 256.0


def settle(sim, thr, flaps, theta_hd, secs, bank=0):
    """定杆开环:固定姿态积分至稳态(POH 数字即稳态)。"""
    sim.theta_hd = theta_hd
    for _ in range(60 * secs):
        sim.step(thr, flaps, bank)
    return sim.v88 >> 8, sim.vs_fpm()


def airborne(v_kn, h_ft=2000, th=4):
    s = IntSim()
    s.reset()
    s.on_ground = False
    s.v88 = v_kn << 8
    s.h88 = h_ft << 8
    s.theta_hd = th
    return s


def int_report():
    print("== 整数孪生(60Hz,开环定杆稳态)校验 ==")
    # 起飞:55 抬 10°
    sim = IntSim()
    sim.reset()
    lift_fr = None
    for fr in range(60 * 60):
        v = sim.step(8, 0)
        if sim.on_ground and v >= 55 and sim.theta_hd < 20:
            sim.theta_hd = 20          # 55 抬 10°
        if not sim.on_ground:
            lift_fr = fr
            break
    print(f"起飞:55 抬轮 10°,{lift_fr/60:.1f}s 离地于 {sim.v88>>8} kn"
          f"  (POH 滑跑 ~15-18s,离地 ~57-62)")
    # Vy:满油门定杆 9.5°(θ=19hd)
    v, vs = settle(airborne(70, 1000, 19), 8, 0, 19, 50)
    print(f"满油门 θ=9.5°:稳态 V={v},VS={vs:.0f} fpm  (Vy 目标 74/730)")
    # 满油门平飞:θ=-2°(巡航配平微低头,机翼安装角/弯度已折入 CL0)
    v, vs = settle(airborne(110, 1000, -4), 8, 0, -4, 90)
    print(f"满油门 θ=-2.0°:稳态 V={v},VS={vs:.0f} fpm  (极速目标 122-126,VS≈0)")
    # 滑翔:收油 θ=0.5°
    v, vs = settle(airborne(75, 4000, 1), 0, 0, 1, 50)
    ratio = (v * 1.688 * 60) / -vs if vs < 0 else 99
    print(f"收油 θ=0.5°:稳态 V={v},VS={vs:.0f},滑翔比≈{ratio:.1f}"
          f"  (目标 ~68kt/9-10:1)")
    # 进近:襟翼30 油门3 θ=-4°(教科书进近姿态)
    v, vs = settle(airborne(68, 2000, -8), 3, 3, -8, 50)
    print(f"襟翼30 油门3 θ=-4.0°:稳态 V={v},VS={vs:.0f} fpm"
          f"  (进近目标 ~65kt/-400~-600)")
    # 失速速度:模型自身判据(α_req ≥ α_crit)扫描;坡度对照
    s = IntSim()
    for f, tgt in ((0, 48), (1, 46), (2, 43), (3, 40)):
        vs_lvl = next(v for v in range(160, 20, -1)
                      if ((s.clr[v] - s.cl0[f]) * 94 >> 8) >= s.crit[f]) + 1
        a30 = lambda v: ((((s.clr[v] - s.cl0[f]) * 94 >> 8) * s.invc[3]) >> 8)
        vs_b30 = next(v for v in range(160, 20, -1) if a30(v) >= s.crit[f]) + 1
        print(f"失速(襟翼{f*10:2d}):平飞 {vs_lvl} kn(目标 {tgt}),"
              f"30°坡度 {vs_b30} kn(应升 ~7%)")
    # 转弯:同速同油门,30° 坡度 vs 平飞的姿态需求(带杆量)与掉高
    v0, vs0 = settle(airborne(90, 1500, 6), 6, 0, 6, 30)
    s = airborne(90, 1500, 6)
    v1, vs1 = settle(s, 6, 0, 6, 30, bank=3)
    print(f"油门6 θ=3°:直飞 V={v0}/VS={vs0:.0f};30°坡度不带杆 "
          f"V={v1}/VS={vs1:.0f}  (转弯应掉高/掉速 → 需带杆补偿)")
    # 地效:襟翼30 收油 1.5° 在 15 ft vs 500 ft 的下沉
    sg = airborne(60, 15, 3)
    for _ in range(90):
        sg.step(0, 3)
        sg.h88 = 15 << 8           # 锁高度采样瞬时下沉率
    vs_ge = sg.vs_fpm()
    sa = airborne(60, 500, 3)
    for _ in range(90):
        sa.step(0, 3)
        sa.h88 = 500 << 8
    print(f"地效验证(60kt 襟30 收油 θ=1.5°):15ft VS={vs_ge:.0f} vs "
          f"500ft VS={sa.vs_fpm():.0f}  (地效应更平缓 → 拉平飘飞)")


if __name__ == "__main__":
    float_report()
    int_report()
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as f:
            f.write(emit())
        print(f"已写出 {sys.argv[1]}")
