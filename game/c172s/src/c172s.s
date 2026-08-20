; ============================================================================
; 《C172S 五边飞行》v2 —— 座舱内视角 + 真实空气动力学(NES,NROM)
;
; 视角:Top Gun 式风挡(全景地平线随航向 X 卷动 / 地平线随俯仰移动 /
;       透视跑道 / PAPI)+ sprite-0 分屏 + 真六联仪表盘(精灵指针)。
; 物理:tools/gen_aero.py 用升力/诱导阻力/功率曲线/失速迎角/地效的真实
;       公式生成整数表(src/aero_tables.inc),整数管线经 POH 校验:
;       失速 48/46/44/41(30° 坡度 +7%),Vy≈74,极速 123,
;       进近 65kt≈-530fpm,滑翔比 ~10,地效飘飞。
; 导航:真实航向(bdeg)与二维位置(ft/2);左起落航线按几何触发,
;       转弯要真的压坡度转过 90°;教官逐段评分与讲评保留。
; ============================================================================

.segment "HEADER"
        .byte "NES", $1A
        .byte 2, 1, $01, $00
        .res 8, $00

; ---------------- 常量 ----------------

PPUCTRL_BASE   = $88

ST_TITLE       = 0
ST_GAME        = 1
ST_DEBRIEF     = 2

LEG_ROLL       = 0
LEG_UPWIND     = 1
LEG_XWIND      = 2
LEG_DWNWD      = 3
LEG_BASE       = 4
LEG_FINAL      = 5
LEG_FLARE      = 6
LEG_ROLLOUT    = 7
LEG_DONE       = 8

BTN_A          = $01
BTN_B          = $02
BTN_SEL        = $04
BTN_STA        = $08
BTN_UP         = $10
BTN_DN         = $20
BTN_LT         = $40
BTN_RT         = $80

; 航线几何(ft/2;跑道入口在原点,朝北 ψ=0,左航线在西侧)
RWY_LEN        = 1500
TRIG_XW_Y      = 2600
TRIG_DW_X      = -1900
TRIG_BA_Y      = -2600
TRIG_FI_X      = -750
ABEAM_Y        = 250

M_NONE      = 0
M_ROLL      = 1
M_UPWIND    = 2
M_XWIND     = 3
M_DWNWD     = 4
M_ABEAM     = 5
M_BASE      = 6
M_FINAL     = 7
M_FLARE     = 8
M_ROLLOUT   = 9
M_TURN      = 10
M_MYCTL     = 11
M_STALL     = 12
M_GOAROUND  = 13
M_HARD      = 14
M_OFFRWY    = 15
M_NICE      = 16
M_DEMO      = 17
M_PAUSED    = 18
M_FLAP0     = 19
M_FLAP1     = 20
M_FLAP2     = 21
M_FLAP3     = 22
M_RUDDER    = 23
M_CRAB      = 24
M_BOUNCE    = 25
M_PORP      = 26
M_NOSEW     = 27
M_SIDE      = 28
M_VFE       = 29
M_CARB      = 30
M_TWR1      = 31
M_TWR2      = 32
M_TWRGA     = 33
M_GAOK      = 34
M_WING      = 35
M_VEER      = 36

; ---------------- 零页 ----------------
.segment "ZEROPAGE"

nmi_busy:    .res 1
frame:       .res 1
game_state:  .res 1
pad:         .res 1
pad_prev:    .res 1
pad_new:     .res 1
a_hold:      .res 1
b_hold:      .res 1
buf_w:       .res 1
tmp0:        .res 1
tmp1:        .res 1
tmp2:        .res 1
tmp3:        .res 1
tmp4:        .res 1
tmp5:        .res 1
tmp6:        .res 1
tmp7:        .res 1
ptr_lo:      .res 1
ptr_hi:      .res 1
mul_lo:      .res 1
mul_hi:      .res 1
msign:       .res 1
num_lo:      .res 1
num_hi:      .res 1

; --- 飞行状态 ---
v88_lo:      .res 1             ; 空速 节 8.8
v88_hi:      .res 1
vint:        .res 1             ; 空速整数 0..160
theta:       .res 1             ; 俯仰姿态 半度 有符号 -16..+36
g88_lo:      .res 1             ; 航迹角 半度 8.8 有符号
g88_hi:      .res 1
h_fr:        .res 1             ; 高度 ft 8.8(24 位)
h_lo:        .res 1
h_hi:        .res 1
bank88_lo:   .res 1             ; 坡度 度 8.8 有符号(±30)
bank88_hi:   .res 1
bank_idx:    .res 1             ; |坡度| 档 0..3
psi_lo:      .res 1             ; 航向 bdeg 8.8
psi_hi:      .res 1
px_fr:       .res 1             ; 位置东 ft/2 8.8 有符号 24 位
px_lo:       .res 1
px_hi:       .res 1
py_fr:       .res 1             ; 位置北
py_lo:       .res 1
py_hi:       .res 1
thr:         .res 1
flaps:       .res 1
on_ground:   .res 1
horn_on:     .res 1
a_req:       .res 1             ; 迎角需求 半度 有符号
dh88_lo:     .res 1
dh88_hi:     .res 1
vs16_lo:     .res 1             ; VS fpm 有符号
vs16_hi:     .res 1
ldg_fpm_lo:  .res 1
ldg_fpm_hi:  .res 1
ldg_x:       .res 1

; --- 视图 ---
pan_lo:      .res 1
pan_nt:      .res 1
hl_px:       .res 1             ; 地平线屏幕行 48..79
hl_cur:      .res 1
hz_task:     .res 1             ; 待重画行计数 4..1(行 6..9)
rw_bear:     .res 1
rw_dist_lo:  .res 1
rw_dist_hi:  .res 1
rw_bucket:   .res 1             ; 0 近..4;5=远精灵;$FF 不可见
rw_col:      .res 1             ; NT 列 0..63
rw_drawn_b:  .res 1
rw_drawn_c:  .res 1
rw_drawn_r:  .res 1
rw_task:     .res 1             ; 0 闲 1 擦 2 画
rw_rel:      .res 1             ; 相对方位(有符号)
papi:        .res 1

; --- 航段 / 评分 ---
leg:         .res 1
next_turn:   .res 1
turn_phase:  .res 1             ; 0 未到 1 提示 2 玩家转弯 3 教官代打
turn_timer:  .res 1
abeam_done:  .res 1
lap:         .res 1
leg_good:    .res 1
leg_max:     .res 1
score_lo:    .res 1
score_hi:    .res 1
crashed:     .res 1
done_timer:  .res 1
msg_id:      .res 1
msg_timer:   .res 1
hud_leg_dirty: .res 1
grades_dirty:  .res 1
paused:      .res 1

; --- AI ---
ai_on:       .res 1
ai_timer:    .res 1
ai_takeover: .res 1

; --- 标题 ---
tt_lo:       .res 1
tt_hi:       .res 1
tplane_fr:   .res 1
tplane_x:    .res 1
plane_py:    .res 1
pose:        .res 1

; --- 声音 ---
eng_hi_last: .res 1
chime_note:  .res 1
chime_timer: .res 1
chime_base:  .res 1
chime_ptr:   .res 1
tri_timer:   .res 1
noise_burst: .res 1
mus_i1:      .res 1
mus_t1:      .res 1
mus_i2:      .res 1
mus_t2:      .res 1
mus_i3:      .res 1
mus_t3:      .res 1

; --- v3:大气/发动机/襟翼/地面 ---
wind_e:      .res 1             ; 风东分量(8.8 ft/2 每帧,有符号,含阵风)
wind_n:      .res 1
gust_lfsr:   .res 1
gust_t:      .res 1
rpm_lo:      .res 1             ; 定距桨转速(16 位,带惯性)
rpm_hi:      .res 1
eng_idx:     .res 1             ; 声音/音量档 0..8
flap_lo:     .res 1             ; 襟翼位置 8.8 档(电动渐变)
flap_hi:     .res 1
flap_tgt:    .res 1
flap_mov:    .res 1
steer_cmd:   .res 1             ; 地面前轮转向 -1/0/+1
pf_msg:      .res 1
stall_act:   .res 1             ; 迎角超临界(掉翼/深失速)
wd_msg:      .res 1
bounce_n:    .res 1
ldg_drift:   .res 1             ; 接地侧向漂移
crab_msg:    .res 1
carb_ok:     .res 1
ov_flag:     .res 1
ga_state:    .res 1             ; 随机复飞:0 未评估 2 已令 3 未触发 4 已完成
ga_t:        .res 1
radio_q:     .res 1
radio_t:     .res 1

; --- v3:视觉 ---
shake_x:     .res 1             ; 机体震动(有符号)
shake_fy:    .res 1
jolt_t:      .res 1
jolt_m:      .res 1
gs_phase:    .res 1             ; 地面双相闪烁
gs_t:        .res 1
grush:       .res 1             ; 低空地面扑面档 0/1/2
mch_phase:   .res 1             ; 中线行进相位
mch_t:       .res 1
rw_skew:     .res 1             ; 跑道侧偏透视(有符号 ±2)
rw_drawn_s:  .res 1
rw_att_c:    .res 1             ; 已写跑道属性起始格($FF 无)
rw_att_n:    .res 1
night_lvl:   .res 1             ; 0 白天 1 黄昏 2 夜航
cont_flag:   .res 1
fade_mode:   .res 1             ; 0 无 1 变暗 2 变亮
fade_step:   .res 1
fade_t:      .res 1
fade_next:   .res 1             ; 1 标题 2 游戏 3 讲评
fade_arg:    .res 1
pal_ptr:     .res 2
trk_t:       .res 1
trk_i:       .res 1

.segment "BSS"
ppu_buf:     .res 208
grades:      .res 6
dec_buf:     .res 5
trk_bx:      .res 48            ; 航迹采样(讲评回放图)
trk_by:      .res 48
stage:       .res 16            ; 跑道贴块行暂存(垫宽/侧偏/相位替换)
oam := $0200

; ============================================================================
.segment "CODE"

reset:
        sei
        cld
        ldx #$40
        stx $4017
        ldx #$FF
        txs
        inx
        stx $2000
        stx $2001
        stx $4010
        bit $2002
@vbl1:  bit $2002
        bpl @vbl1
        lda #0
        tax
@clr:   sta $0000,x
        sta $0300,x
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne @clr
        lda #$F8
@clro:  sta $0200,x
        inx
        bne @clro
        lda #$FF
        sta ppu_buf
@vbl2:  bit $2002
        bpl @vbl2

        lda #$0F
        sta $4015
        lda #$08
        sta $4001
        sta $4005
        lda #$00
        sta $4000
        sta $4004
        sta $400C
        lda #$80
        sta $4008
        lda #$08
        sta $4003
        sta $4007
        sta $400F

        jsr enter_title
forever:
        jmp forever

irq:    rti

; ============================================================================
; NMI
; ============================================================================
nmi:
        pha
        txa
        pha
        tya
        pha
        lda nmi_busy
        beq @go
        pla
        tay
        pla
        tax
        pla
        rti
@go:    inc nmi_busy
        bit $2002
        lda #$00
        sta $2003
        lda #$02
        sta $4014
        jsr flush_buf
        ; 风挡滚动:X = pan(= ψ·2-128),Y = 0
        lda pan_nt
        and #$01
        ora #PPUCTRL_BASE
        sta $2000
        lda pan_lo
        sta $2005
        lda #0
        sta $2005
        lda game_state
        cmp #ST_GAME
        bne @nosplit
        jsr do_split
@nosplit:
        jsr read_pads
        lda game_state
        cmp #ST_TITLE
        bne @s1
        jsr tick_title
        jmp @tickd
@s1:    cmp #ST_GAME
        bne @s2
        jsr tick_game
        jmp @tickd
@s2:    jsr tick_debrief
@tickd:
        jsr fade_tick
        jsr sound_tick
        inc frame
        lda #0
        sta nmi_busy
        pla
        tay
        pla
        tax
        pla
        rti

; sprite-0 命中(~95 行,机头罩上)后延时至 hblank,4 写切到面板(NT0 行 12)
do_split:
        ldx #0
        ldy #24
@wclr:  bit $2002
        bvc @hit0
        dex
        bne @wclr
        dey
        bne @wclr
        rts
@hit0:  ldx #0
        ldy #40
@wset:  bit $2002
        bvs @set
        dex
        bne @wset
        dey
        bne @wset
        rts
@set:   ldx #13
@d:     dex
        bne @d
        lda #$01
        sta $2006
        sec
        lda #$60
        sbc shake_fy            ; 震动:面板整体下沉 0-3px(顶部露机头罩,无损)
        sta $2005
        lda #$00
        sta $2005
        lda #$80
        sta $2006
        rts

flush_buf:
        ldx #0
@ent:   lda ppu_buf,x
        cmp #$FF
        beq @done
        sta $2006
        inx
        lda ppu_buf,x
        sta $2006
        inx
        lda ppu_buf,x
        inx
        sta tmp0
        and #$80
        beq @inc1
        lda #PPUCTRL_BASE|$04
        sta $2000
        bne @len
@inc1:  lda #PPUCTRL_BASE
        sta $2000
@len:   lda tmp0
        and #$7F
        sta tmp1
        beq @done
@dat:   lda ppu_buf,x
        sta $2007
        inx
        dec tmp1
        bne @dat
        jmp @ent
@done:  lda #$FF
        sta ppu_buf
        lda #0
        sta buf_w
        rts

read_pads:
        lda pad
        sta pad_prev
        lda #1
        sta $4016
        lda #0
        sta $4016
        ldx #8
@b:     lda $4016
        lsr a
        ror pad
        dex
        bne @b
        lda pad_prev
        eor #$FF
        and pad
        sta pad_new
        rts

; ============================================================================
; 数学
; ============================================================================

; tmp0 × tmp1 → mul_hi:mul_lo(无符号 8×8)
mul8x8:
        lda #0
        sta mul_lo
        ldx #8
@l:     lsr tmp0
        bcc @noadd
        clc
        adc tmp1
@noadd: ror a
        ror mul_lo
        dex
        bne @l
        sta mul_hi
        rts

; A(有符号)×Y(无符号)→ mul 有符号 16 位
smul_au:
        sty tmp1
        sta msign
        ora #0                  ; STA 不设标志!按 A 的符号分支
        bpl @pos
        eor #$FF
        clc
        adc #1
@pos:   sta tmp0
        jsr mul8x8
        lda msign
        bpl @rts
        sec
        lda #0
        sbc mul_lo
        sta mul_lo
        lda #0
        sbc mul_hi
        sta mul_hi
@rts:   rts

; mul 算术右移 5 / 6
shr5_s: ldx #5
        bne shrx
shr6_s: ldx #6
shrx:
@s:     lda mul_hi
        cmp #$80
        ror mul_hi
        ror mul_lo
        dex
        bne @s
        rts

; g88 算术右移 6 → A
g88_asr6:
        lda g88_hi
        sta mul_hi
        lda g88_lo
        sta mul_lo
        jsr shr6_s
        lda mul_lo
        rts

b2d16:
        ldx #0
@digit: lda #'0'
        sta dec_buf,x
@sub:   sec
        lda num_lo
        sbc pow_lo,x
        tay
        lda num_hi
        sbc pow_hi,x
        bcc @next
        sta num_hi
        sty num_lo
        inc dec_buf,x
        jmp @sub
@next:  inx
        cpx #4
        bne @digit
        lda num_lo
        clc
        adc #'0'
        sta dec_buf+4
        rts

b2d8:
        sta num_lo
        lda #0
        sta num_hi
        jmp b2d16

score_add8:
        clc
        adc score_lo
        sta score_lo
        bcc @rts
        inc score_hi
@rts:   rts

score_add16:
        clc
        lda score_lo
        adc tmp0
        sta score_lo
        lda score_hi
        adc tmp1
        sta score_hi
        rts

score_sub8:                     ; score = max(0, score - A)
        sta tmp0
        sec
        lda score_lo
        sbc tmp0
        sta score_lo
        lda score_hi
        sbc #0
        sta score_hi
        bcs @rts
        lda #0
        sta score_lo
        sta score_hi
@rts:   rts

; ============================================================================
; 真实气动物理(每帧;gen_aero.py 配方)
; ============================================================================
physics:
        lda v88_hi
        bpl @vp
        lda #0
@vp:    cmp #160
        bcc @vok
        lda #160
@vok:   sta vint

        ; ---- 定距桨转速:tgt = base[thr]+V×slp>>3,rpm += Δ>>4(惯性) ----
        lda vint
        sta tmp0
        ldx thr
        lda rpm_slp,x
        sta tmp1
        jsr mul8x8
        ldx #3
@rs:    lsr mul_hi
        ror mul_lo
        dex
        bne @rs
        ldx thr
        clc
        lda mul_lo
        adc rpm_base_lo,x
        sta tmp0
        lda mul_hi
        adc rpm_base_hi,x
        sta tmp1
        sec
        lda tmp0
        sbc rpm_lo
        sta mul_lo
        lda tmp1
        sbc rpm_hi
        sta mul_hi
        ldx #4
        jsr shrx
        clc
        lda rpm_lo
        adc mul_lo
        sta rpm_lo
        lda rpm_hi
        adc mul_hi
        sta rpm_hi
        ; 声档 = (rpm-600)>>8 钳 0..8
        sec
        lda rpm_lo
        sbc #<600
        lda rpm_hi
        sbc #>600
        bpl @ei_p
        lda #0
@ei_p:  cmp #9
        bcc @ei_ok
        lda #8
@ei_ok: sta eng_idx

        ; ---- 电动襟翼渐变(1 档 ≈1.4s)+ 电机标志 ----
        lda flap_hi
        cmp flap_tgt
        bne @fl_move
        lda flap_lo
        beq @fl_stop
        ; 同档带小数(只在收襟翼路径出现)→ 继续收
@fl_move:
        lda #1
        sta flap_mov
        lda flap_hi
        cmp flap_tgt
        bcs @fl_dn
        ; 放襟翼
        clc
        lda flap_lo
        adc #3
        sta flap_lo
        lda flap_hi
        adc #0
        sta flap_hi
        cmp flap_tgt
        bcc @fl_upd
        ; 到档:清小数
        lda #0
        sta flap_lo
        jmp @fl_upd
@fl_dn: ; 收襟翼:已在目标档内且余量将尽 → 吸附,防跨档回摆
        cmp flap_tgt
        bne @fl_dn2
        lda flap_lo
        cmp #4
        bcs @fl_dn2
        lda #0
        sta flap_lo
        jmp @fl_upd
@fl_dn2:
        sec
        lda flap_lo
        sbc #3
        sta flap_lo
        lda flap_hi
        sbc #0
        sta flap_hi
        jmp @fl_upd
@fl_stop:
        lda #0
        sta flap_mov
@fl_upd:
        ; flaps = round(flap88)
        lda flap_lo
        clc
        adc #128
        lda flap_hi
        adc #0
        cmp #4
        bcc @fl_set
        lda #3
@fl_set:
        sta flaps

        ; ---- α_req = (CLR-CL0)×94>>8,坡度 ×(1+invc_d/256) ----
        ldx vint
        lda clr_tab,x
        ldx flaps
        sec
        sbc cl0_tab,x
        bcs @dcl_pos
        ; 负(|dcl| ≤ 64)
        eor #$FF
        clc
        adc #1
        sta tmp0
        lda #94
        sta tmp1
        jsr mul8x8
        sec
        lda #0
        sbc mul_hi
        jmp @areq_set
@dcl_pos:
        sta tmp0
        lda #94
        sta tmp1
        jsr mul8x8
        ldy bank_idx
        beq @nb
        lda mul_hi
        sta tmp4
        sta tmp0
        lda invc_d_tab,y
        sta tmp1
        jsr mul8x8
        lda mul_hi
        clc
        adc tmp4
        jmp @areq_set
@nb:    lda mul_hi
@areq_set:
        sta a_req
        ; 喇叭(空中且 α_req ≥ horn);失速标志(α_req ≥ crit → 掉翼)
        ldx #0
        stx stall_act
        lda on_ground
        bne @hs
        lda a_req
        bmi @hs
        ldy flaps
        cmp crit_hd,y
        bcc @crit_no
        inc stall_act
@crit_no:
        cmp horn_hd,y
        bcc @hs
        inx
@hs:    stx horn_on
        ; 钳位 α_req ∈ [-24, crit+24]
        lda a_req
        bmi @neg_cl
        ldy flaps
        clc
        lda crit_hd,y
        adc #24
        cmp a_req
        bcs @clamp_ok
        sta a_req
        jmp @clamp_ok
@neg_cl:
        cmp #<(-24)
        bcs @clamp_ok
        lda #<(-24)
        sta a_req
@clamp_ok:

        ; ---- γ 动力学 ----
        lda on_ground
        beq @air_g
        lda #0
        sta g88_lo
        sta g88_hi
        lda theta
        bmi @gnd_done
        beq @gnd_done
        sec
        sbc #2                  ; 需 +1° 裕度才离地
        bmi @gnd_done
        cmp a_req
        bmi @gnd_done
        lda vint
        cmp #50
        bcc @gnd_done
        lda #0
        sta on_ground
        lda #2                  ; 起落架伸展:2 ft 种子
        sta h_lo
        jsr ev_liftoff
@gnd_done:
        jmp @drag
@air_g: lda theta
        sec
        sbc a_req               ; γ_t 高字节
        sta tmp4
        sec
        lda #0
        sbc g88_lo
        sta mul_lo
        lda tmp4
        sbc g88_hi
        sta mul_hi
        jsr shr6_s
        clc
        lda g88_lo
        adc mul_lo
        sta g88_lo
        lda g88_hi
        adc mul_hi
        sta g88_hi
        ; ---- 掉翼:失速中带坡度 → 坡度向内侧发散(减迎角才能改出) ----
        lda stall_act
        beq @wd_clr
        lda bank88_hi
        bmi @wd_l
        cmp #8
        bcc @wd_done
        clc
        lda bank88_lo
        adc #24
        sta bank88_lo
        lda bank88_hi
        adc #0
        cmp #38
        bcc @wd_st_r
        lda #38
@wd_st_r:
        sta bank88_hi
        jmp @wd_warn
@wd_l:  cmp #<(-8)
        bpl @wd_done
        sec
        lda bank88_lo
        sbc #24
        sta bank88_lo
        lda bank88_hi
        sbc #0
        cmp #<(-38)
        bpl @wd_st_l
        lda #<(-38)
@wd_st_l:
        sta bank88_hi
@wd_warn:
        lda wd_msg
        bne @wd_done
        inc wd_msg
        lda #M_WING
        jsr msg_set
        jmp @wd_done
@wd_clr:
        lda #0
        sta wd_msg
@wd_done:

@drag:  ; ---- CL_eff → tmp6 ----
        lda on_ground
        beq @cl_air
        lda theta
        bpl @thp
        lda #0
@thp:   sta tmp0
        lda #11
        sta tmp1
        jsr mul8x8
        lsr mul_hi
        ror mul_lo
        lsr mul_hi
        ror mul_lo
        ldx flaps
        lda cl0_tab,x
        clc
        adc mul_lo
        bcs @cl_cap
        cmp clmax_tab,x
        bcc @cl_set
@cl_cap:
        lda clmax_tab,x
        jmp @cl_set
@cl_air:
        ldx vint
        lda clr_tab,x
        ldy bank_idx
        beq @cl_chk
        sta tmp4
        sta tmp0
        lda invc_d_tab,y
        sta tmp1
        jsr mul8x8
        lda tmp4
        clc
        adc mul_hi
        bcs @cl_cap
@cl_chk:
        ldx flaps
        cmp clmax_tab,x
        bcc @cl_set
        lda clmax_tab,x
@cl_set:
        sta tmp6
        ; clsq = CL²>>6 钳 255 → tmp2
        sta tmp0
        lda tmp6
        sta tmp1
        jsr mul8x8
        lda mul_lo
        rol a
        rol a
        rol a
        and #$03
        sta tmp2
        lda mul_hi
        asl a
        asl a
        bcs @sq_cap
        ora tmp2
        sta tmp2
        bcc @sq_ok
@sq_cap:
        lda #255
        sta tmp2
@sq_ok: ; 诱导 = clsq × kq(地效 ×5/8)>>8 → tmp7
        ldx vint
        lda kq_tab,x
        sta tmp3
        lda on_ground
        bne @no_ge
        lda h_hi
        bne @no_ge
        lda h_lo
        cmp #25
        bcs @no_ge
        lda tmp3
        lsr a
        sta tmp3
        lsr a
        lsr a
        clc
        adc tmp3
        sta tmp3                ; ×(1/2+1/8)=5/8
@no_ge: lda tmp2
        sta tmp0
        lda tmp3
        sta tmp1
        jsr mul8x8
        lda mul_hi
        sta tmp7
        ; 寄生 PAR[f(+4 收油)][V>>2]
        lda flaps
        ldx thr
        bne @thr_on
        clc
        adc #4
@thr_on:
        tax
        lda par_lo,x
        sta ptr_lo
        lda par_hi,x
        sta ptr_hi
        lda vint
        lsr a
        lsr a
        tay
        lda (ptr_lo),y
        clc
        adc tmp7
        bcc @dw1
        lda #255
@dw1:   sta tmp7
        ; 地面滚阻/刹车
        lda on_ground
        beq @dw_done
        lda #5
        sta tmp4
        lda leg
        cmp #LEG_ROLLOUT
        bne @add_roll
        lda ai_on
        bne @brk
        lda pad
        and #BTN_B
        beq @add_roll
@brk:   lda #25
        sta tmp4
@add_roll:
        lda tmp7
        clc
        adc tmp4
        bcc @dw2
        lda #255
@dw2:   sta tmp7
@dw_done:
        ; ---- 推力 ----
        ldx thr
        lda tw_lo,x
        sta ptr_lo
        lda tw_hi,x
        sta ptr_hi
        lda vint
        lsr a
        lsr a
        lsr a
        tay
        lda (ptr_lo),y
        sta tmp6                ; TW
        ; ---- SINg = (γ asr6)×143>>8(有符号)→ tmp5(高字节) ----
        jsr g88_asr6
        ldy #143
        jsr smul_au
        ; d16 = TW - DW - SINg_hi(全 16 位)
        sec
        lda tmp6
        sbc tmp7
        sta tmp4
        lda #0
        sbc #0
        sta tmp5
        sec
        lda tmp4
        sbc mul_hi
        sta tmp4
        lda tmp5
        sbc #0
        bpl @sgn_fix
        ; mul_hi 为负时上面的 sbc #0 少借位:统一重算高位
@sgn_fix:
        sta tmp5
        lda mul_hi
        bpl @dv_abs
        ; 减了负数 → 高位需 +1 补偿(sbc #0 应为 sbc #$FF)
        inc tmp5
@dv_abs:
        ; |d| 钳 255 → tmp0,符号 → msign
        lda tmp5
        bmi @d_neg
        beq @d_p_small
        lda #255
        sta tmp0
        jmp @d_p_go
@d_p_small:
        lda tmp4
        sta tmp0
@d_p_go:
        lda #0
        sta msign
        jmp @dv_mul
@d_neg: sec
        lda #0
        sbc tmp4
        sta tmp0
        lda #0
        sbc tmp5
        beq @d_n_ok
        lda #255
        sta tmp0
@d_n_ok:
        lda #$80
        sta msign
@dv_mul:
        lda #81
        sta tmp1
        jsr mul8x8
        lda msign
        bmi @v_sub
        lda v88_lo
        clc
        adc mul_hi
        sta v88_lo
        bcc @v_done
        inc v88_hi
        jmp @v_done
@v_sub: lda v88_lo
        sec
        sbc mul_hi
        sta v88_lo
        bcs @v_done
        dec v88_hi
        bpl @v_done
        lda #0
        sta v88_lo
        sta v88_hi
@v_done:

        ; ---- 高度 ----
        lda on_ground
        beq @alt_go
        lda #0
        sta dh88_lo
        sta dh88_hi
        sta h_fr
        sta h_lo
        sta h_hi
        jmp @vs_disp
@alt_go:
        jsr g88_asr6
        ldy vint
        jsr smul_au
        jsr shr6_s
        lda mul_lo
        sta dh88_lo
        lda mul_hi
        sta dh88_hi
        bpl @dh_p
        lda #$FF
        bne @dh_x
@dh_p:  lda #0
@dh_x:  sta tmp0
        clc
        lda h_fr
        adc dh88_lo
        sta h_fr
        lda h_lo
        adc dh88_hi
        sta h_lo
        lda h_hi
        adc tmp0
        sta h_hi
        bmi @touch
        bne @vs_disp
        lda h_lo
        ora h_fr
        bne @vs_disp
@touch: lda g88_hi
        bpl @h_zero
        jsr ev_touchdown
@h_zero:
        lda #0
        sta h_fr
        sta h_lo
        sta h_hi
@vs_disp:
        ; VS fpm = dh88×14(×2 + ×4 + ×8)
        lda dh88_lo
        sta vs16_lo
        lda dh88_hi
        sta vs16_hi
        asl vs16_lo
        rol vs16_hi
        lda vs16_lo
        sta tmp2
        lda vs16_hi
        sta tmp3
        asl vs16_lo
        rol vs16_hi
        clc
        lda vs16_lo
        adc tmp2
        sta tmp4
        lda vs16_hi
        adc tmp3
        sta tmp5
        asl vs16_lo
        rol vs16_hi
        clc
        lda vs16_lo
        adc tmp4
        sta vs16_lo
        lda vs16_hi
        adc tmp5
        sta vs16_hi

        ; ---- 航向 ----
        lda on_ground
        beq @air_turn
        ; 地面:前轮转向(滚动中才有效)
        lda vint
        cmp #8
        bcc @pfact
        lda steer_cmd
        beq @pfact
        bmi @gs_l
        clc
        lda psi_lo
        adc #14
        sta psi_lo
        bcc @pfact
        inc psi_hi
        jmp @pfact
@gs_l:  sec
        lda psi_lo
        sbc #14
        sta psi_lo
        bcs @pfact
        dec psi_hi
        jmp @pfact
@air_turn:
        ; 转弯率 = g·tanφ/V
        lda bank_idx
        beq @pfact
        tay
        lda tank_tab,y
        sta tmp0
        ldx vint
        cpx #30
        bcs @rv
        ldx #30
@rv:    lda recv_tab,x
        sta tmp1
        jsr mul8x8
        lda bank88_hi
        bmi @turn_l
        clc
        lda psi_lo
        adc mul_hi
        sta psi_lo
        bcc @pfact
        inc psi_hi
        jmp @pfact
@turn_l:
        sec
        lda psi_lo
        sbc mul_hi
        sta psi_lo
        bcs @pfact
        dec psi_hi
@pfact: ; ---- P-factor/滑流:大功率低速左偏(真机要踩右舵) ----
        ldx thr
        lda pf_tab,x
        beq @position
        ldy vint
        cpy #12
        bcc @position           ; 静止不偏
        cpy #100
        bcs @position
        cpy #85
        bcc @pf_go
        lsr a
        beq @position
@pf_go: sta tmp0
        sec
        lda psi_lo
        sbc tmp0
        sta psi_lo
        bcs @position
        dec psi_hi

@position:
        ; ---- 位置推进:d = V×sin116>>5(ft/2 8.8) ----
        lda psi_hi
        lsr a
        lsr a
        and #$3F
        tax
        lda sin116,x
        ldy vint
        jsr smul_au
        jsr shr5_s
        lda mul_hi
        bpl @ex_p
        ldy #$FF
        bne @ex
@ex_p:  ldy #0
@ex:    clc
        lda px_fr
        adc mul_lo
        sta px_fr
        lda px_lo
        adc mul_hi
        sta px_lo
        tya
        adc px_hi
        sta px_hi
        lda psi_hi
        lsr a
        lsr a
        clc
        adc #16
        and #$3F
        tax
        lda sin116,x
        ldy vint
        jsr smul_au
        jsr shr5_s
        lda mul_hi
        bpl @ny_p
        ldy #$FF
        bne @ny
@ny_p:  ldy #0
@ny:    clc
        lda py_fr
        adc mul_lo
        sta py_fr
        lda py_lo
        adc mul_hi
        sta py_lo
        tya
        adc py_hi
        sta py_hi

        ; ---- 风漂移(仅空中;地速 = 空速矢量 + 风矢量) ----
        lda on_ground
        bne @gust_upd
        lda wind_e
        bpl @we_p
        ldy #$FF
        bne @we_x
@we_p:  ldy #0
@we_x:  clc
        adc px_fr
        sta px_fr
        tya
        adc px_lo
        sta px_lo
        tya
        adc px_hi
        sta px_hi
        lda wind_n
        bpl @wn_p
        ldy #$FF
        bne @wn_x
@wn_p:  ldy #0
@wn_x:  clc
        adc py_fr
        sta py_fr
        tya
        adc py_lo
        sta py_lo
        tya
        adc py_hi
        sta py_hi
@gust_upd:
        ; ---- 阵风:每 32 帧 LFSR 换档;低空(<256ft)垂直扰动 ----
        lda frame
        and #$1F
        bne @gust_done
        lda gust_lfsr
        asl a
        bcc @lf_x
        eor #$1D
@lf_x:  sta gust_lfsr
        and #$03
        cmp #3
        bcc @g_idx
        lda #1
@g_idx: tax
        lda wind_e_tab,x
        sta wind_e
        lda wind_n_tab,x
        sta wind_n
        lda on_ground
        bne @gust_done
        lda h_hi
        bne @gust_done
        lda gust_lfsr
        and #$04
        beq @gv_dn
        clc
        lda g88_lo
        adc #12
        sta g88_lo
        bcc @gust_done
        inc g88_hi
        jmp @gust_done
@gv_dn: sec
        lda g88_lo
        sbc #12
        sta g88_lo
        bcs @gust_done
        dec g88_hi
@gust_done:
        rts

; ---------------- 事件 ----------------
ev_liftoff:
        lda #LEG_UPWIND
        sta leg
        jsr on_leg_enter
        rts

ev_touchdown:
        lda #1
        sta on_ground
        sec
        lda #0
        sbc vs16_lo
        sta ldg_fpm_lo
        lda #0
        sbc vs16_hi
        sta ldg_fpm_hi
        ; 接地侧向漂移 = |V·sinψ + 风东|(8.8 ft/2 每帧,钳 255)
        lda psi_hi
        lsr a
        lsr a
        and #$3F
        tax
        lda sin116,x
        ldy vint
        jsr smul_au
        jsr shr5_s
        lda wind_e
        bpl @dw_p
        ldy #$FF
        bne @dw_x
@dw_p:  ldy #0
@dw_x:  clc
        adc mul_lo
        sta tmp0
        tya
        adc mul_hi
        sta tmp1
        bpl @dr_abs
        sec
        lda #0
        sbc tmp0
        sta tmp0
        lda #0
        sbc tmp1
        sta tmp1
@dr_abs:
        lda tmp1
        beq @dr_lo
        lda #255
        bne @dr_st
@dr_lo: lda tmp0
@dr_st: sta ldg_drift
        lda #0
        sta g88_lo
        sta g88_hi
        sta bank88_lo
        sta bank88_hi
        ; |x| → ldg_x(钳 255)
        lda px_hi
        bmi @xn
        bne @far
        lda px_lo
        jmp @xg
@xn:    sec
        lda #0
        sbc px_lo
        tax
        lda #0
        sbc px_hi
        bne @far
        txa
        jmp @xg
@far:   lda #255
@xg:    sta ldg_x
        ; 机体冲击震动
        ldx #1
        lda ldg_fpm_hi
        bne @j_big
        lda ldg_fpm_lo
        cmp #250
        bcc @j_go
        inx
        bne @j_go
@j_big: ldx #3
@j_go:  stx jolt_m
        lda #8
        sta jolt_t
        ; FINAL 之前触地 = 起飞回落:场内回 ROLL 不评分,场外坠毁
        lda leg
        cmp #LEG_FINAL
        bcs @real_ldg
        jsr on_runway_chk
        bcc @off_j
        lda #LEG_ROLL
        sta leg
        rts
@off_j: jmp @off
@real_ldg:
        jsr on_runway_chk
        bcs @on
        jmp @off
@on:    ; ≥700 fpm → 硬着陆坠机
        lda ldg_fpm_hi
        cmp #>700
        bcc @hard_no
        bne @hard
        lda ldg_fpm_lo
        cmp #<700
        bcc @hard_no
@hard:  lda #M_HARD
        jsr msg_set
        jmp @crash_common
@hard_no:
        ; 400-699 fpm → 弹跳(能量回弹;三连跳 = 海豚跳坠机)
        lda ldg_fpm_hi
        cmp #>400
        bcc @stick
        bne @bounce
        lda ldg_fpm_lo
        cmp #<400
        bcc @stick
@bounce:
        inc bounce_n
        lda bounce_n
        cmp #3
        bcs @porpoise
        lda #0
        sta on_ground
        lda ldg_fpm_lo
        asl a
        sta g88_lo
        lda ldg_fpm_hi
        rol a
        sta g88_hi
        cmp #>1400
        bcc @b_ok
        bne @b_cap
        lda g88_lo
        cmp #<1400
        bcc @b_ok
@b_cap: lda #>1400
        sta g88_hi
        lda #<1400
        sta g88_lo
@b_ok:  sec
        lda v88_hi
        sbc #3
        sta v88_hi
        bpl @b_v
        lda #0
        sta v88_hi
        sta v88_lo
@b_v:   lda #3
        sta jolt_m
        lda #12
        sta jolt_t
        lda #8
        sta noise_burst
        lda #8
        sta tri_timer
        lda #100
        jsr score_sub8
        lda #M_BOUNCE
        jsr msg_set
        rts
@porpoise:
        lda #M_PORP
        jsr msg_set
        jmp @crash_common
@stick: lda #LEG_ROLLOUT
        sta leg
        lda #2
        sta theta
        lda #10
        sta noise_burst
        lda #12
        sta tri_timer
        jsr grade_landing
        jsr on_leg_enter
        ; 无视塔台复飞令着陆 → 重罚
        lda ga_state
        cmp #2
        bne @rts2
        lda #200
        jsr score_sub8
        lda #200
        jsr score_sub8
@rts2:  rts
@off:   lda #M_OFFRWY
        jsr msg_set
@crash_common:
        lda #1
        sta crashed
        lda #150
        sta done_timer
        lda #'E'
        sta grades+5
        lda #1
        sta grades_dirty
        lda #14
        sta noise_burst
        lda #3
        sta jolt_m
        lda #20
        sta jolt_t
        lda #LEG_ROLLOUT
        sta leg
        rts

; C=1:在跑道带内(|x|≤30=60ft 半宽 且 0 ≤ y < RWY_LEN);用 ldg_x
on_runway_chk:
        lda ldg_x
        cmp #31
        bcs @no
        lda py_hi
        bmi @no
        cmp #>RWY_LEN
        bcc @yes
        bne @no
        lda py_lo
        cmp #<RWY_LEN
        bcs @no
@yes:   sec
        rts
@no:    clc
        rts

; 接地评分:fpm 档(<150 A <250 B <400 C)+ 姿态/弹跳/侧载封顶 + 中线奖励
grade_landing:
        ldx #0
@lp:    lda ldg_fpm_hi
        cmp ldg_thr_hi,x
        bcc @got
        bne @nx
        lda ldg_fpm_lo
        cmp ldg_thr_lo,x
        bcc @got
@nx:    inx
        cpx #4
        bne @lp
        dex                     ; ≥400 已走弹跳路径,理论不可达
@got:   lda #0
        sta tmp5                ; 覆盖提示消息
        ; 前轮先着(θ<+1°)→ 至少 D
        lda theta
        cmp #2
        bpl @nw_ok
        cpx #3
        bcs @nw_m
        ldx #3
@nw_m:  lda #M_NOSEW
        sta tmp5
        lda #100
        jsr score_sub8
@nw_ok: ; 弹跳史 → 至少 C
        lda bounce_n
        beq @b_done
        cpx #2
        bcs @b_done
        ldx #2
@b_done:
        ; 侧向漂移:≥20 侧载(至少 C),≥10 小罚
        lda ldg_drift
        cmp #20
        bcc @dr_sm
        cpx #2
        bcs @dr_m
        ldx #2
@dr_m:  lda tmp5
        bne @dr_done
        lda #M_SIDE
        sta tmp5
        jmp @dr_done
@dr_sm: cmp #10
        bcc @dr_done
        lda #100
        jsr score_sub8
@dr_done:
        txa
        pha
        clc
        adc #'A'
        sta grades+5
        lda #1
        sta grades_dirty
        pla
        asl a
        tax
        lda ldg_score,x
        sta tmp0
        lda ldg_score+1,x
        sta tmp1
        jsr score_add16
        lda ldg_x
        cmp #9
        bcs @cl_done
        lda #<300
        sta tmp0
        lda #>300
        sta tmp1
        jsr score_add16
@cl_done:
        lda tmp5
        beq @m_nice
        jsr msg_set
        jmp @snd
@m_nice:
        lda ldg_fpm_hi
        bne @m2
        lda ldg_fpm_lo
        cmp #150
        bcs @m2
        lda bounce_n
        bne @m2
        lda #M_NICE
        jsr msg_set
        jmp @snd
@m2:    lda #M_ROLLOUT
        jsr msg_set
@snd:   ldy #CH_OK
        jsr chime_start
        rts

; ============================================================================
; 标题
; ============================================================================
enter_title:
        lda #0
        sta $2000
        sta $2001
        bit $2002
        lda #ST_TITLE
        sta game_state
        lda #0
        sta night_lvl           ; 标题总是白天
        sta shake_x
        sta shake_fy
        jsr load_palettes
        jsr draw_title
        lda #0
        sta tt_lo
        sta tt_hi
        sta tplane_fr
        sta pan_lo
        sta pan_nt
        lda #40
        sta tplane_x
        lda #0
        sta mus_i1
        sta mus_i2
        sta mus_i3
        lda #1
        sta mus_t1
        sta mus_t2
        sta mus_t3
        lda #$FF
        sta chime_ptr
        sta ppu_buf
        lda #0
        sta buf_w
        ; 藏所有精灵
        ldx #0
        lda #$F8
@ho:    sta oam,x
        inx
        inx
        inx
        inx
        bne @ho
        lda #$1E
        sta $2001
        lda #PPUCTRL_BASE
        sta $2000
        rts

tick_title:
        lda pad_new
        and #BTN_STA
        beq @nostart
        lda #0
        jmp start_game
@nostart:
        inc tt_lo
        bne @t1
        inc tt_hi
@t1:    lda tt_hi
        cmp #3
        bcc @blink
        lda #1
        jmp start_game
@blink: lda tt_lo
        and #$1F
        bne @plane
        ldy buf_w
        lda #$22
        sta ppu_buf,y
        iny
        lda #$8A
        sta ppu_buf,y
        iny
        lda #11
        sta ppu_buf,y
        iny
        lda tt_lo
        and #$20
        beq @showtxt
        ldx #0
@sp:    lda #' '
        sta ppu_buf,y
        iny
        inx
        cpx #11
        bne @sp
        beq @fin
@showtxt:
        ldx #0
@st:    lda str_press,x
        sta ppu_buf,y
        iny
        inx
        cpx #11
        bne @st
@fin:   lda #$FF
        sta ppu_buf,y
        sty buf_w
@plane: lda tplane_fr
        clc
        adc #160
        sta tplane_fr
        bcc @nx
        inc tplane_x
@nx:    lda #192
        sta plane_py
        lda #0
        sta pose
        lda tplane_x
        jsr draw_plane_at
        rts

start_game:
        sta fade_arg
        lda #2
        jmp fade_begin

; ============================================================================
; 进入游戏
; ============================================================================
enter_game:
        lda #0
        sta $2000
        sta $2001
        bit $2002
        lda #ST_GAME
        sta game_state
        jsr load_palettes
        jsr draw_cockpit_static

        ; 状态清零 + 初始位置(入口内 100ft,朝北)
        lda #0
        sta v88_lo
        sta v88_hi
        sta vint
        sta theta
        sta g88_lo
        sta g88_hi
        sta h_fr
        sta h_lo
        sta h_hi
        sta bank88_lo
        sta bank88_hi
        sta bank_idx
        sta psi_lo
        sta psi_hi
        sta thr
        sta flaps
        sta horn_on
        sta px_fr
        sta px_lo
        sta px_hi
        sta py_fr
        sta lap
        sta crashed
        sta paused
        sta next_turn
        sta turn_phase
        sta abeam_done
        sta leg_good
        sta leg_max
        sta done_timer
        sta a_hold
        sta b_hold
        sta ai_timer
        sta ai_takeover
        sta eng_hi_last
        sta hz_task
        sta rw_task
        ; --- v3 状态 ---
        sta flap_lo
        sta flap_hi
        sta flap_tgt
        sta flap_mov
        sta steer_cmd
        sta pf_msg
        sta stall_act
        sta wd_msg
        sta bounce_n
        sta ldg_drift
        sta crab_msg
        sta carb_ok
        sta ga_state
        sta ga_t
        sta radio_q
        sta radio_t
        sta shake_x
        sta shake_fy
        sta jolt_t
        sta jolt_m
        sta gs_phase
        sta gs_t
        sta mch_phase
        sta mch_t
        sta rw_skew
        sta trk_t
        sta trk_i
        lda #$FF
        sta rw_drawn_s
        sta rw_att_c
        lda #2
        sta grush               ; 地面滑跑 = 贴地纹理
        lda #<700
        sta rpm_lo
        lda #>700
        sta rpm_hi
        ; 阵风种子:演示恒定(录像可复现),玩家随机
        lda ai_on
        beq @seed_p
        lda #$5A
        bne @seed_s
@seed_p:
        lda frame
        ora #$01
@seed_s:
        sta gust_lfsr
        ldx #1
        lda wind_e_tab,x
        sta wind_e
        lda wind_n_tab,x
        sta wind_n
        ; 续飞(黄昏/夜航圈)保留总分与昼夜档
        lda cont_flag
        bne @keep_score
        lda #0
        sta score_lo
        sta score_hi
        sta night_lvl
@keep_score:
        lda #0
        sta cont_flag
        lda #50
        sta py_lo
        lda #0
        sta py_hi
        lda #1
        sta on_ground
        lda #LEG_ROLL
        sta leg
        lda #64
        sta hl_px
        sta hl_cur
        lda #$FF
        sta rw_bucket
        sta rw_drawn_b
        sta chime_ptr
        sta ppu_buf
        lda #0
        sta buf_w
        lda #'-'
        ldx #5
@g:     sta grades,x
        dex
        bpl @g
        lda #1
        sta hud_leg_dirty
        sta grades_dirty
        lda #M_ROLL
        jsr msg_set
        jsr pan_update

        ; sprite-0(机头罩上,88 行;不透明行 95-96)
        lda #88
        sta oam
        lda #$00
        sta oam+1
        lda #$20
        sta oam+2
        lda #16
        sta oam+3
        ; Vne 红线(空速表盘 160kt 位置的固定红标)
        lda #102
        sta oam+84
        lda #$50
        sta oam+85
        lda #$00
        sta oam+86
        lda #12
        sta oam+87

        lda #$1E
        sta $2001
        lda #PPUCTRL_BASE
        sta $2000
        rts

; ============================================================================
; 游戏主逻辑
; ============================================================================
tick_game:
        lda crashed
        beq @alive
        dec done_timer
        bne @rts0
        lda #3
        jmp fade_begin
@alive: lda leg
        cmp #LEG_DONE
        bne @notdone
        dec done_timer
        bne @rts0
        lda #3
        jmp fade_begin
@rts0:  rts
@notdone:
        lda ai_on
        bne @ai_mode
        lda pad_new
        and #BTN_STA
        beq @nopau
        lda paused
        eor #1
        sta paused
        beq @nopau
        lda #M_PAUSED
        jsr msg_set
@nopau: lda paused
        beq @player
        rts
@ai_mode:
        lda pad_new
        and #BTN_STA
        beq @chk_o
        lda #0
        jmp start_game
@chk_o: lda pad_new
        and #BTN_A|BTN_B|BTN_SEL
        beq @ai_go
        lda #1
        jmp fade_begin
@ai_go: jsr ai_tick
        jmp @common
@player:
        jsr apply_input
        lda ai_takeover
        beq @common
        jsr ai_turn_ctl
@common:
        jsr bank_update
        jsr physics
        jsr legs_tick
        jsr shake_upd
        lda frame
        and #$07
        bne @noslow
        jsr slow_tick
@noslow:
        jsr hud_tick            ; 小写手在前,view 的护栏据实决策
        jsr view_tick
        jsr game_sprites
        rts

; ---------------- 输入 ----------------
apply_input:
        ; A/B 油门(按住连发)
        lda pad
        and #BTN_A
        beq @a_off
        inc a_hold
        lda pad_new
        and #BTN_A
        bne @a_do
        lda a_hold
        cmp #12
        bcc @a_end
        lda #0
        sta a_hold
@a_do:  lda thr
        cmp #8
        bcs @a_end
        inc thr
@a_end: jmp @b
@a_off: lda #0
        sta a_hold
@b:     lda pad
        and #BTN_B
        beq @b_off
        inc b_hold
        lda pad_new
        and #BTN_B
        bne @b_do
        lda b_hold
        cmp #12
        bcc @b_end
        lda #0
        sta b_hold
@b_do:  lda thr
        beq @b_end
        dec thr
@b_end: jmp @pitch
@b_off: lda #0
        sta b_hold
@pitch: ; UP/DOWN 按住每 4 帧 ±1 半度(7.5°/s)
        lda frame
        and #$03
        bne @sel
        lda pad
        and #BTN_UP
        beq @p_dn
        lda theta
        cmp #36
        bcs @sel
        inc theta
        bne @sel
@p_dn:  lda pad
        and #BTN_DN
        beq @sel
        lda theta
        cmp #<(-16)
        beq @sel
        dec theta
@sel:   lda pad_new
        and #BTN_SEL
        beq @roll
        lda flap_tgt
        clc
        adc #1
        and #3
        sta flap_tgt
        ; Vfe:>85 kt 放襟翼 → 警告 + 扣分(照样放,后果自负)
        beq @fl_msg             ; 收回(→0)不限速
        lda vint
        cmp #86
        bcc @fl_msg
        lda #M_VFE
        jsr msg_set
        lda #100
        jsr score_sub8
        ldy #CH_WARN
        jsr chime_start
        jmp @roll
@fl_msg:
        lda flap_tgt
        clc
        adc #M_FLAP0
        jsr msg_set
        ldy #CH_BLIP
        jsr chime_start
@roll:  ; 地面:LEFT/RIGHT = 前轮转向(修 P-factor);空中 = 压坡度
        lda on_ground
        beq @air_roll
        lda #0
        sta steer_cmd
        lda pad
        and #BTN_LT
        beq @gs_r
        lda #$FF
        sta steer_cmd
@gs_r:  lda pad
        and #BTN_RT
        beq @gs_c
        lda #1
        sta steer_cmd
@gs_c:  jsr roll_center
        rts
@air_roll:
        lda #0
        sta steer_cmd
        lda ai_takeover
        bne @rts
        lda pad
        and #BTN_LT
        beq @r_r
        jsr roll_left
        rts
@r_r:   lda pad
        and #BTN_RT
        beq @r_c
        jsr roll_right
        rts
@r_c:   jsr roll_center
@rts:   rts

; 坡度控制:按住 ±9°/s,松手 5°/s 回中
roll_left:
        sec
        lda bank88_lo
        sbc #40
        sta bank88_lo
        lda bank88_hi
        sbc #0
        sta bank88_hi
        ; 钳 -30
        cmp #<(-30)
        bpl @rts
        lda #<(-30)
        sta bank88_hi
        lda #0
        sta bank88_lo
@rts:   rts

roll_right:
        clc
        lda bank88_lo
        adc #40
        sta bank88_lo
        lda bank88_hi
        adc #0
        sta bank88_hi
        cmp #30
        bmi @rts
        lda #30
        sta bank88_hi
        lda #0
        sta bank88_lo
@rts:   rts

roll_center:
        lda bank88_hi
        bmi @neg
        ora bank88_lo
        beq @rts
        sec
        lda bank88_lo
        sbc #64
        sta bank88_lo
        lda bank88_hi
        sbc #0
        sta bank88_hi
        bpl @rts
        lda #0
        sta bank88_lo
        sta bank88_hi
        rts
@neg:   clc
        lda bank88_lo
        adc #64
        sta bank88_lo
        lda bank88_hi
        adc #0
        sta bank88_hi
        bmi @rts
        lda #0
        sta bank88_lo
        sta bank88_hi
@rts:   rts

; 机体震动:失速抖振(迎角驱动)+ 接地/弹跳冲击
shake_upd:
        lda #0
        sta shake_x
        sta shake_fy
        lda horn_on
        beq @jolt
        lda frame
        and #$02
        beq @bx_n
        lda #1
        bne @bx_s
@bx_n:  lda #$FF
@bx_s:  sta shake_x
        lda frame
        and #$01
        sta shake_fy
@jolt:  lda jolt_t
        beq @rts
        dec jolt_t
        lda jolt_m
        sta shake_fy
        lda frame
        and #$02
        beq @j_n
        lda jolt_m
        bne @j_s
@j_n:   sec
        lda #0
        sbc jolt_m
@j_s:   sta shake_x
@rts:   rts

; |bank| → bank_idx(0/1/2/3 ≈ 0/10/20/30°)
bank_update:
        lda bank88_hi
        bpl @abs_ok
        eor #$FF
        clc
        adc #1
@abs_ok:
        ldx #0
        cmp #5
        bcc @set
        inx
        cmp #15
        bcc @set
        inx
        cmp #25
        bcc @set
        inx
@set:   stx bank_idx
        rts

; ============================================================================
; 自动驾驶(演示)/ 教官代打:姿态飞行法
; ============================================================================
ai_tick:
        inc ai_timer
        ; 地面:自动"踩舵"对准跑道航向(修 P-factor)
        lda on_ground
        beq @in_air
        ldx #0
        lda psi_hi
        beq @st_set
        cmp #128
        bcs @st_r
        ldx #$FF
        bne @st_set
@st_r:  ldx #1
@st_set:
        stx steer_cmd
@in_air:
        ; 转弯:提示窗一到就开始压坡度
        lda turn_phase
        cmp #1
        bne @not_start
        lda #2
        sta turn_phase
        lda #200
        jsr score_add8
        lda #100
        jsr score_add8
        lda #M_NONE
        sta msg_id
        jsr msg_clear
@not_start:
        lda turn_phase
        cmp #2
        bcc @wings
        jsr ai_turn_ctl
        jmp @trim
@wings: lda leg
        cmp #LEG_FINAL
        beq @loc
        cmp #LEG_FLARE
        beq @loc
        ; 直线段航向保持:浅坡度修掉 P-factor/风致偏航
        ldx leg
        lda psi_hi
        sec
        sbc leg_hdg,x
        cmp #$80
        bcs @h_r
        cmp #2
        bcc @h_lvl
        jsr roll_left10
        jmp @trim
@h_r:   cmp #$FF
        beq @h_lvl
        jsr roll_right10
        jmp @trim
@h_lvl: jsr roll_center
        jmp @trim
@loc:   jsr ai_localizer
@trim:  ; 慢配平(每 64 帧)
        lda ai_timer
        and #$3F
        beq @do_trim
        rts
@do_trim:
        ldx leg
        ; 油门/襟翼趋近表值
        lda ai_thr_tab,x
        cmp #$FF
        beq @thr_ok
        cmp thr
        beq @thr_ok
        bcc @thr_dn
        inc thr
        bne @thr_ok
@thr_dn:
        dec thr
@thr_ok:
        lda ai_flap_tab,x
        cmp flap_tgt
        beq @flap_ok
        bcc @flap_dn
        inc flap_tgt
        bne @flap_ok
@flap_dn:
        dec flap_tgt
@flap_ok:
        ; 分航段俯仰策略(跳板避免远分支)
        lda leg
        cmp #LEG_ROLL
        bne @n_roll
        lda vint
        cmp #55
        bcc @rts1
        lda #20
        sta theta               ; 55 抬 10°
@rts1:  rts
@n_roll:
        cmp #LEG_DWNWD
        bne @n_dwn
        jmp @alt_hold
@n_dwn: cmp #LEG_FLARE
        bne @n_flr
        jmp @flare
@n_flr: cmp #LEG_ROLLOUT
        bcc @n_ro
        rts
@n_ro:  cmp #LEG_FINAL
        bne @spd
        jmp @final
@spd:   ; 速度保持(pitch for speed):快 1 节即带杆,慢 2 节才松杆
        ldx leg
        lda vint
        sec
        sbc leg_tgt_ias,x
        beq @rts2
        bmi @slow
        lda theta
        cmp #36
        bcs @rts2
        inc theta
        rts
@slow:  cmp #<(-1)
        beq @rts2
        lda theta
        cmp #<(-14)
        beq @rts2
        dec theta
@rts2:  rts
@alt_hold:
        ; 三边:未到高 → 全油门保 80-83 爬;到高 → 定高 + 油门调速
        lda h_hi
        cmp #>950
        bcc @ah_climb
        bne @ah_at
        lda h_lo
        cmp #<950
        bcs @ah_at
@ah_climb:
        lda thr
        cmp #8
        bcs @ah_c2
        inc thr
@ah_c2: lda vint
        cmp #83
        bcc @ah_c3
        inc theta
        rts
@ah_c3: cmp #80
        bcs @rts_c
        lda theta
        cmp #<(-14)
        beq @rts_c
        dec theta
@rts_c: rts
@ah_at: lda h_hi
        cmp #>1030
        bcc @ah_lo
        bne @ah_dn
        lda h_lo
        cmp #<1030
        bcc @ah_lo
@ah_dn: dec theta
        jmp @ah_spd
@ah_lo: lda h_hi
        cmp #>970
        bcc @ah_up
        bne @ah_spd
        lda h_lo
        cmp #<970
        bcs @ah_spd
@ah_up: inc theta
@ah_spd:
        ; 过正切:教科书动作 —— 收油到 4,放襟翼 10,提前减速
        lda abeam_done
        beq @ah_v
        lda #1
        sta flap_tgt
        lda thr
        cmp #5
        bcc @rts
        dec thr
        rts
@ah_v:  lda vint
        cmp #94
        bcc @ah_s2
        dec thr
        rts
@ah_s2: cmp #87
        bcs @rts
        lda thr
        cmp #8
        bcs @rts
        inc thr
        rts
@final: ; 五边:俯仰保速 65,油门按 PAPI 保下滑道
        lda vint
        sec
        sbc #65
        beq @f_papi
        bmi @f_slow
        cmp #2
        bcc @f_papi
        inc theta
        bne @f_papi
@f_slow:
        cmp #<(-1)
        beq @f_papi
        dec theta
@f_papi:
        lda papi
        cmp #2
        beq @rts
        bcc @f_hi
        lda thr
        cmp #7
        bcs @rts
        inc thr
        rts
@f_hi:  lda thr
        beq @rts
        dec thr
        rts
@flare: ; 拉平:收油,带住,飘落
        lda #0
        sta thr
        lda theta
        cmp #8
        bcs @rts
        inc theta
@rts:   rts

; 五边中线截获(定位器式):ψ_cmd = -clamp(px/16, ±8) bdeg,浅坡度跟踪
ai_localizer:
        lda px_hi
        sta tmp1
        lda px_lo
        sta tmp0
        ldx #3
@s:     lda tmp1
        cmp #$80
        ror tmp1
        ror tmp0
        dex
        bne @s
        lda tmp1
        bmi @neg
        bne @cap_p
        lda tmp0
        cmp #10
        bcc @have
@cap_p: lda #10
        bne @have
@neg:   cmp #$FF
        bne @cap_n
        lda tmp0
        cmp #<(-10)
        bcs @have
@cap_n: lda #<(-10)
@have:  eor #$FF
        clc
        adc #1
        sec
        sbc #4                  ; 侧风偏流前馈(风自左前 → 机头偏西压偏流)
        sta tmp2                ; ψ_cmd = -clamp(px/8, ±10) - 4
        lda psi_hi
        sec
        sbc tmp2
        beq @lvl
        bmi @chk_r
        jsr roll_left10
        rts
@chk_r: jsr roll_right10
        rts
@lvl:   jsr roll_center
        rts

; 浅坡度(±10°)滚转,中线/微调用
roll_left10:
        sec
        lda bank88_lo
        sbc #40
        sta bank88_lo
        lda bank88_hi
        sbc #0
        sta bank88_hi
        cmp #<(-10)
        bpl @rts
        lda #<(-10)
        sta bank88_hi
        lda #0
        sta bank88_lo
@rts:   rts

roll_right10:
        clc
        lda bank88_lo
        adc #40
        sta bank88_lo
        lda bank88_hi
        adc #0
        sta bank88_hi
        cmp #10
        bmi @rts
        lda #10
        sta bank88_hi
        lda #0
        sta bank88_lo
@rts:   rts

; 转弯控制(AI 与教官代打共用):左转 diff 从 +64 递减,
; 提前 8 bdeg(≈11°)滚出;过了目标不反向追(等下一圈也不会有)
ai_turn_ctl:
        ldx next_turn
        cpx #4
        bcs @lvl
        lda psi_hi
        sec
        sbc turn_tgt,x
        beq @lvl
        bmi @past
        cmp #10
        bcc @lvl
        jsr roll_left
        rts
@past:  cmp #<(-6)
        bcs @lvl                ; 小过冲:等完成判定
        jsr roll_right          ; 大过冲:右修
        rts
@lvl:   jsr roll_center
        rts

; ============================================================================
; 航段状态机(每帧)
; ============================================================================
legs_tick:
        ; --- 转弯提示/判定 ---
        lda turn_phase
        beq @chk_trig
        jmp @in_turn
@chk_trig:
        ldx next_turn
        cpx #4
        bcc @trig_go
        jmp @turn_done
@trig_go:
        jsr turn_trigger_hit
        bcs @trig_hit
        jmp @turn_done
@trig_hit:
        lda #1
        sta turn_phase
        lda #240
        sta turn_timer
        lda #M_TURN
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        jmp @turn_done
@in_turn:
        cmp #1
        bne @phase2
        ; 提示窗:玩家压左坡 ≥10° → 开始转弯
        lda bank88_hi
        cmp #<(-9)
        bpl @p1_wait
        lda #2
        sta turn_phase
        lda #200
        jsr score_add8
        lda turn_timer
        cmp #150
        bcc @p1_scored
        lda #100
        jsr score_add8
@p1_scored:
        lda #M_NONE
        sta msg_id
        jsr msg_clear
        jmp @turn_done
@p1_wait:
        dec turn_timer
        bne @turn_done
        ; 超时 → 教官代打
        lda #3
        sta turn_phase
        lda #1
        sta ai_takeover
        lda #M_MYCTL
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        jmp @turn_done
@phase2:
        ; 转弯中:滚出判定(|ψ-tgt|≤8 且坡度<4°)
        ldx next_turn
        lda psi_hi
        sec
        sbc turn_tgt,x
        bpl @d_abs
        eor #$FF
        clc
        adc #1
@d_abs: cmp #9
        bcs @turn_done
        lda bank88_hi
        bpl @b_abs
        eor #$FF
@b_abs: cmp #4
        bcs @turn_done
        ; 完成本转
        lda #0
        sta turn_phase
        sta ai_takeover
        inc next_turn
        lda #100
        jsr score_add8
        ldy #CH_OK
        jsr chime_start
        ; leg = UPWIND + next_turn
        lda next_turn
        clc
        adc #LEG_UPWIND
        cmp leg
        beq @turn_done
        pha
        jsr leg_finalize
        pla
        sta leg
        jsr on_leg_enter
@turn_done:
        ; --- ABEAM ---
        lda abeam_done
        bne @ab_done
        lda leg
        cmp #LEG_DWNWD
        bne @ab_done
        lda py_hi
        bmi @ab_hit
        bne @ab_done
        lda py_lo
        cmp #<ABEAM_Y
        bcs @ab_done
@ab_hit:
        lda #1
        sta abeam_done
        lda #M_ABEAM
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        lda #M_TWR2
        sta radio_q
        lda #26
        sta radio_t
@ab_done:
        ; --- FLARE ---
        lda leg
        cmp #LEG_FINAL
        bne @fl_done
        lda on_ground
        bne @fl_done
        lda h_hi
        bne @fl_done
        lda h_lo
        cmp #30
        bcs @fl_done
        jsr leg_finalize
        lda #LEG_FLARE
        sta leg
        jsr on_leg_enter
@fl_done:
        ; --- 拉平自动蹬正(改出偏流:ψ→0,漂移随之出现 → 别飘太久) ---
        lda leg
        cmp #LEG_FLARE
        bne @dc_done
        lda on_ground
        bne @dc_done
        lda psi_hi
        beq @dc_done
        cmp #128
        bcs @dc_r
        sec
        lda psi_lo
        sbc #8
        sta psi_lo
        bcs @dc_done
        dec psi_hi
        jmp @dc_done
@dc_r:  clc
        lda psi_lo
        adc #8
        sta psi_lo
        bcc @dc_done
        inc psi_hi
@dc_done:
        ; --- 复飞(五边冲过头) ---
        lda leg
        cmp #LEG_FINAL
        bcc @ga_done
        cmp #LEG_ROLLOUT
        bcs @ga_done
        lda on_ground
        bne @ga_done
        lda py_hi
        bmi @ga_done
        cmp #>800
        bcc @ga_done
        bne @ga_go
        lda py_lo
        cmp #<800
        bcc @ga_done
@ga_go: lda h_hi
        bne @ga_yes
        lda h_lo
        cmp #40
        bcc @ga_done
@ga_yes:
        lda #M_GOAROUND
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        lda #0
        sta next_turn
        sta abeam_done
        sta turn_phase
        inc lap
        lda #LEG_UPWIND
        sta leg
        jsr on_leg_enter
@ga_done:
        ; --- 滑跑纪律:冲出跑道侧缘 / RIGHT RUDDER 提示 ---
        lda on_ground
        beq @roll_done
        lda vint
        cmp #12
        bcc @roll_done
        lda leg
        cmp #LEG_ROLL
        beq @roll_chk
        cmp #LEG_ROLLOUT
        bne @roll_done
@roll_chk:
        lda px_hi
        bmi @vx_n
        bne @veer
        lda px_lo
        cmp #31
        bcs @veer
        jmp @rud
@vx_n:  cmp #$FF
        bne @veer
        lda px_lo
        cmp #<(-30)
        bcs @rud
@veer:  lda crashed
        bne @roll_done
        lda #M_VEER
        jsr msg_set
        lda #1
        sta crashed
        lda #150
        sta done_timer
        lda #'E'
        sta grades+5
        lda #1
        sta grades_dirty
        lda #12
        sta noise_burst
        lda #2
        sta jolt_m
        lda #16
        sta jolt_t
        jmp @roll_done
@rud:   lda pf_msg
        bne @roll_done
        lda psi_hi
        cmp #128
        bcc @roll_done          ; 没有左偏
        cmp #255
        beq @roll_done          ; 仅 -1 bdeg,不吵
        inc pf_msg
        lda #M_RUDDER
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
@roll_done:
        ; --- 化油器加热提醒(空中收油门下滑) ---
        lda on_ground
        bne @cb_done
        lda thr
        cmp #3
        bcs @cb_reset
        lda carb_ok
        bne @cb_done
        lda h_hi
        bne @cb_go
        lda h_lo
        cmp #150
        bcc @cb_done
@cb_go: inc carb_ok
        lda #M_CARB
        jsr msg_set
        jmp @cb_done
@cb_reset:
        lda thr
        cmp #5
        bcc @cb_done
        lda #0
        sta carb_ok
@cb_done:
        ; --- 侧风偏流提示(五边偏出中线 ±90ft) ---
        lda leg
        cmp #LEG_FINAL
        bne @cr_done
        lda crab_msg
        bne @cr_done
        lda px_hi
        bmi @cr_n
        bne @cr_hit
        lda px_lo
        cmp #45
        bcs @cr_hit
        jmp @cr_done
@cr_n:  cmp #$FF
        bne @cr_hit
        lda px_lo
        cmp #<(-45)
        bcs @cr_done
@cr_hit:
        inc crab_msg
        lda #M_CRAB
        jsr msg_set
@cr_done:
        ; --- 塔台随机复飞令(玩家第一圈,五边 150-240 ft 评估一次) ---
        lda ai_on
        bne @tg_done
        lda ga_state
        beq @tg_eval
        cmp #2
        bne @tg_done
        lda ga_t
        beq @tg_done
        dec ga_t
        lda thr
        cmp #8
        bcc @tg_done
        lda flap_tgt
        cmp #2
        bcs @tg_done
        lda #4
        sta ga_state
        lda #<300
        sta tmp0
        lda #>300
        sta tmp1
        jsr score_add16
        lda #M_GAOK
        jsr msg_set
        jmp @tg_done
@tg_eval:
        lda leg
        cmp #LEG_FINAL
        bne @tg_done
        lda h_hi
        bne @tg_done
        lda h_lo
        cmp #240
        bcs @tg_done
        cmp #150
        bcc @tg_done
        lda lap
        bne @tg_skip
        lda gust_lfsr
        and #$03
        beq @tg_fire
@tg_skip:
        lda #3
        sta ga_state
        jmp @tg_done
@tg_fire:
        lda #2
        sta ga_state
        lda #180
        sta ga_t
        lda #M_TWRGA
        jsr msg_set
        ldy #CH_RADIO
        jsr chime_start
        lda #3
        sta noise_burst
@tg_done:
        ; --- 失速警告消息 ---
        lda horn_on
        beq @st_done
        lda msg_id
        cmp #M_STALL
        beq @st_done
        lda #M_STALL
        jsr msg_set
@st_done:
        ; --- 滑跑停止 ---
        lda on_ground
        beq @samp
        lda leg
        cmp #LEG_ROLLOUT
        bne @samp
        lda vint
        cmp #8
        bcs @samp
        lda #LEG_DONE
        sta leg
        lda #120
        sta done_timer
        lda #<300
        sta tmp0
        lda #>300
        sta tmp1
        jsr score_add16
@samp:  ; --- 采样评分(航段 1-5,坡度平稳时,每 16 帧) ---
        lda leg
        beq @rts0
        cmp #LEG_FLARE
        bcs @rts0
        lda bank_idx
        cmp #1
        bcs @rts0
        lda frame
        and #$0F
        bne @rts0
        lda leg_max
        cmp #250                ; 计数封顶,防 8 位回绕
        bcc @go_samp
@rts0:  rts
@go_samp:
        inc leg_max
        inc leg_max
        ldx leg
        lda vint
        sec
        sbc leg_tgt_ias,x
        bpl @i_abs
        eor #$FF
        clc
        adc #1
@i_abs: cmp leg_tol,x
        bcs @i_bad
        inc leg_good
        lda #2
        jsr score_add8
@i_bad: lda leg_mode,x
        beq @m_climb
        cmp #1
        beq @m_level
        cmp #4
        beq @m_cl
        ; 下降:vs16 < -50 fpm
        lda vs16_hi
        bpl @m_bad
        cmp #$FF
        bne @m_ok
        lda vs16_lo
        cmp #<(-50)
        bcs @m_bad
        bcc @m_ok
@m_cl:  lda vs16_hi
        bmi @m_level
        bne @m_ok
        lda vs16_lo
        cmp #100
        bcs @m_ok
        bcc @m_level
@m_climb:
        lda vs16_hi
        bmi @m_bad
        bne @m_ok
        lda vs16_lo
        cmp #100
        bcc @m_bad
        bcs @m_ok
@m_level:
        ; |h-1000| ≤ 80
        sec
        lda h_lo
        sbc #<920
        tay
        lda h_hi
        sbc #>920
        bne @m_bad
        cpy #161
        bcs @m_bad
@m_ok:  inc leg_good
        lda #2
        jsr score_add8
@m_bad:
@rts:   rts

; C=1 → 触发本转(X=next_turn)
turn_trigger_hit:
        lda leg
        cmp #LEG_ROLL
        beq @no
        cpx #0
        bne @t1
        ; y ≥ 2600 且 h ≥ 300
        lda h_hi
        cmp #>300
        bcc @no
        bne @y_chk
        lda h_lo
        cmp #<300
        bcc @no
@y_chk: lda py_hi
        bmi @no
        cmp #>TRIG_XW_Y
        bcc @no
        bne @yes
        lda py_lo
        cmp #<TRIG_XW_Y
        bcc @no
        bcs @yes
@t1:    cpx #1
        bne @t2
        ; x ≤ -1900:px - (-1900) < 0
        sec
        lda px_lo
        sbc #<TRIG_DW_X
        lda px_hi
        sbc #>TRIG_DW_X
        bmi @yes
        bpl @no
@t2:    cpx #2
        bne @t3
        sec
        lda py_lo
        sbc #<TRIG_BA_Y
        lda py_hi
        sbc #>TRIG_BA_Y
        bmi @yes
        bpl @no
@t3:    ; x ≥ -750
        sec
        lda px_lo
        sbc #<TRIG_FI_X
        lda px_hi
        sbc #>TRIG_FI_X
        bpl @yes
@no:    clc
        rts
@yes:   sec
        rts

; 旧航段结算(v1 同款:good×10 vs max×9/7/5/3)
leg_finalize:
        lda leg
        beq @zero
        cmp #LEG_FLARE
        bcs @zero
        tax
        dex
        stx tmp2                ; 槽位存好(mul8x8 会清 X!)
        lda leg_max
        beq @st_e
        lda leg_good
        ldy #10
        jsr mulset
        lda mul_lo
        sta num_lo
        lda mul_hi
        sta num_hi
        lda leg_max
        ldy #9
        jsr mulset
        jsr cmp_nm
        bcs @a
        lda leg_max
        ldy #7
        jsr mulset
        jsr cmp_nm
        bcs @b
        lda leg_max
        ldy #5
        jsr mulset
        jsr cmp_nm
        bcs @c
        lda leg_max
        ldy #3
        jsr mulset
        jsr cmp_nm
        bcs @d
@st_e:  lda #'E'
        bne @st
@a:     lda #'A'
        bne @st
@b:     lda #'B'
        bne @st
@c:     lda #'C'
        bne @st
@d:     lda #'D'
@st:    ldx tmp2
        sta grades,x
        lda #1
        sta grades_dirty
        lda #100
        jsr score_add8
        ldy #CH_OK
        jsr chime_start
@zero:  lda #0
        sta leg_good
        sta leg_max
        rts

mulset: sta tmp0
        sty tmp1
        jmp mul8x8

cmp_nm: lda num_hi
        cmp mul_hi
        bcc @no
        bne @yes
        lda num_lo
        cmp mul_lo
        bcc @no
@yes:   sec
        rts
@no:    clc
        rts

on_leg_enter:
        lda #1
        sta hud_leg_dirty
        lda #0
        sta crab_msg
        ldx leg
        cpx #LEG_XWIND
        bne @no_r1
        lda #M_TWR1
        sta radio_q
        lda #22
        sta radio_t
@no_r1: lda leg_msg,x
        beq @nomsg
        jsr msg_set
@nomsg: ; AI 前馈姿态/油门/襟翼
        lda ai_on
        ora ai_takeover
        beq @rts
        ldx leg
        lda ai_thff_tab,x
        sta theta
@rts:   rts

; ============================================================================
; 慢速层 v3 附加:电台/地面闪烁/中线行进/侧偏/扑面/航迹采样
; ============================================================================
slow_v3:
        ; -- 电台队列 --
        lda radio_t
        beq @rq_done
        dec radio_t
        bne @rq_done
        lda radio_q
        beq @rq_done
        ldx msg_timer
        cpx #90
        bcc @rq_go
        lda #4
        sta radio_t             ; 消息行占用,32 帧后再试
        jmp @rq_done
@rq_go: jsr msg_set
        lda #0
        sta radio_q
        ldy #CH_RADIO
        jsr chime_start
        lda #3
        sta noise_burst
@rq_done:
        ; -- 地面双相闪烁(行进感,节奏 ∝ 地速;只写 2 个调色板字节) --
        lda gs_t
        beq @gs_new
        dec gs_t
        jmp @gs_done
@gs_new:
        lda fade_mode
        beq @gs_run
        jmp @gs_done            ; 转场中不闪
@gs_run:
        lda vint
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #4
        bcc @gs_p
        lda #4
@gs_p:  sta tmp0
        sec
        lda #5
        sbc tmp0
        sta gs_t
        lda gs_phase
        eor #1
        sta gs_phase
        ldy buf_w
        cpy #150
        bcs @gs_done
        lda #$3F
        sta ppu_buf,y
        iny
        lda #$0E
        sta ppu_buf,y
        iny
        lda #2
        sta ppu_buf,y
        iny
        sty tmp1
        ldy #14
        lda (pal_ptr),y
        sta tmp2                ; c2 原值
        iny
        lda (pal_ptr),y
        ldy tmp1
        ldx gs_phase
        bne @gs_swap
        pha
        lda tmp2
        sta ppu_buf,y
        iny
        pla
        sta ppu_buf,y
        iny
        jmp @gs_fin
@gs_swap:
        sta ppu_buf,y
        iny
        lda tmp2
        sta ppu_buf,y
        iny
@gs_fin:
        lda #$FF
        sta ppu_buf,y
        sty buf_w
@gs_done:
        ; -- 中线行进(最近距贴块,原位重画) --
        lda rw_bucket
        bne @mc_done
        lda mch_t
        beq @mc_new
        dec mch_t
        jmp @mc_done
@mc_new:
        lda vint
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #2
        bcc @mc_p
        lda #2
@mc_p:  sta tmp0
        sec
        lda #3
        sbc tmp0
        sta mch_t
        lda mch_phase
        eor #1
        sta mch_phase
        lda rw_task
        bne @mc_done
        lda #2
        sta rw_task
@mc_done:
        ; -- 跑道侧偏透视:skew = -clamp(px>>6, ±2)(近距 bucket≤2) --
        lda #0
        sta tmp0
        lda rw_bucket
        cmp #3
        bcs @sk_set
        lda px_hi
        sta mul_hi
        lda px_lo
        sta mul_lo
        ldx #6
        jsr shrx
        lda mul_hi
        bmi @sk_n
        bne @sk_m2
        lda mul_lo
        beq @sk_set             ; 0 → 0(tmp0 已 0)
        cmp #2
        bcs @sk_m2
        lda #<(-1)
        bne @sk_st
@sk_m2: lda #<(-2)
        bne @sk_st
@sk_n:  cmp #$FF
        bne @sk_p2
        lda mul_lo
        cmp #$FF
        bne @sk_p2
        lda #1
        bne @sk_st
@sk_p2: lda #2
@sk_st: sta tmp0
@sk_set:
        lda tmp0
        sta rw_skew
        ; -- 低空地面扑面档 --
        ldx #0
        lda on_ground
        bne @gr_lvl2
        lda h_hi
        bne @gr_cmp
        lda h_lo
        cmp #150
        bcs @gr_cmp
        inx
        cmp #50
        bcs @gr_cmp
@gr_lvl2:
        ldx #2
@gr_cmp:
        cpx grush
        beq @gr_done
        stx grush
        lda #5
        sta hz_task
        lda #$FF
        sta rw_drawn_b
@gr_done:
        ; -- 航迹采样(每 32 拍 ≈ 4.3s) --
        inc trk_t
        lda trk_t
        and #$1F
        bne @tk_done
        ldx trk_i
        cpx #48
        bcs @tk_done
        clc
        lda px_lo
        adc #<2400
        sta tmp0
        lda px_hi
        adc #>2400
        bmi @tk_zx
        lsr a
        ror tmp0
        lsr a
        ror tmp0
        lsr a
        ror tmp0
        lsr a
        ror tmp0
        lda tmp0
        jmp @tk_sx
@tk_zx: lda #0
@tk_sx: sta trk_bx,x
        clc
        lda py_lo
        adc #<3200
        sta tmp0
        lda py_hi
        adc #>3200
        bmi @tk_zy
        ldy #5
@tk_ys: lsr a
        ror tmp0
        dey
        bne @tk_ys
        lda tmp0
        jmp @tk_sy
@tk_zy: lda #0
@tk_sy: sta trk_by,x
        inc trk_i
@tk_done:
        rts

; ============================================================================
; 慢速层(每 8 帧):方位/距离/跑道显示档/PAPI
; ============================================================================
slow_tick:
        jsr slow_v3
        ; dx = -px, dy = -py(指向入口)
        sec
        lda #0
        sbc px_lo
        sta tmp0
        lda #0
        sbc px_hi
        sta tmp1                ; dx(有符号)
        sec
        lda #0
        sbc py_lo
        sta tmp2
        lda #0
        sbc py_hi
        sta tmp3                ; dy
        ; ax=|dx| ay=|dy|
        lda tmp1
        sta tmp5
        bpl @ax_ok
        sec
        lda #0
        sbc tmp0
        sta tmp0
        lda #0
        sbc tmp1
        sta tmp1
@ax_ok: lda tmp3
        sta tmp6
        bpl @ay_ok
        sec
        lda #0
        sbc tmp2
        sta tmp2
        lda #0
        sbc tmp3
        sta tmp3
@ay_ok:
        ; dist ≈ max + min/2(先求 max/min)
        lda tmp1
        cmp tmp3
        bne @mx1
        lda tmp0
        cmp tmp2
@mx1:   bcs @x_big
        ; ay 大
        lda tmp0
        sta tmp4
        lda tmp1
        sta tmp7                ; min = ax
        lda tmp2
        sta rw_dist_lo
        lda tmp3
        sta rw_dist_hi
        jmp @mm
@x_big: lda tmp2
        sta tmp4
        lda tmp3
        sta tmp7                ; min = ay
        lda tmp0
        sta rw_dist_lo
        lda tmp1
        sta rw_dist_hi
@mm:    lsr tmp7
        ror tmp4
        clc
        lda rw_dist_lo
        adc tmp4
        sta rw_dist_lo
        lda rw_dist_hi
        adc tmp7
        sta rw_dist_hi
        ; 方位:φ = atan2(ax,ay) 归一到象限
        jsr atan_octant
        ; 象限:N/E: b=φ;S/E: 128-φ;S/W: 128+φ;N/W: 256-φ
        lda tmp5                ; dx 符号
        bmi @west
        lda tmp6
        bmi @se
        lda tmp4                ; NE
        jmp @b_set
@se:    sec
        lda #128
        sbc tmp4
        jmp @b_set
@west:  lda tmp6
        bmi @sw
        sec
        lda #0
        sbc tmp4                ; 256-φ
        jmp @b_set
@sw:    lda #128
        clc
        adc tmp4
@b_set: sta rw_bear
        ; rel = bear - ψ(有符号)
        sec
        sbc psi_hi
        sta rw_rel
        ; 显示档:|rel|>56 或 dist>4000 → 精灵/无
        lda rw_rel
        bpl @r_abs
        eor #$FF
        clc
        adc #1
@r_abs: cmp #57
        bcc @vis
        lda #$FF
        sta rw_bucket
        jmp @papi
@vis:   ldx #0
@bk:    lda rw_dist_hi
        cmp bucket_hi,x
        bcc @bk_got
        bne @bk_nx
        lda rw_dist_lo
        cmp bucket_lo,x
        bcc @bk_got
@bk_nx: inx
        cpx #6
        bne @bk
        lda #$FF
        sta rw_bucket
        jmp @papi
@bk_got:
        stx rw_bucket
        ; NT 列 = bear>>2(0..63)
        lda rw_bear
        lsr a
        lsr a
        sta rw_col
@papi:  ; PAPI:ideal = (dist2>>4)×27>>4(≈3° 下滑道)vs h
        lda leg
        cmp #LEG_FINAL
        bcc @papi_off
        cmp #LEG_ROLLOUT
        bcc @papi_calc
@papi_off:
        lda #2
        sta papi
        jmp @rw_sched
@papi_calc:
        lda rw_dist_hi
        sta tmp1
        lda rw_dist_lo
        sta tmp0
        ldx #4
@ds:    lsr tmp1
        ror tmp0
        dex
        bne @ds
        lda tmp0
        sta tmp0
        lda #27
        sta tmp1
        jsr mul8x8
        ; >>4 → ideal(16 位)
        ldx #4
@is:    lsr mul_hi
        ror mul_lo
        dex
        bne @is
        ; diff = h - ideal
        sec
        lda h_lo
        sbc mul_lo
        sta tmp0
        lda h_hi
        sbc mul_hi
        sta tmp1
        bmi @below
        bne @hi2
        lda tmp0
        cmp #80
        bcs @hi2
        cmp #30
        bcs @hi1
        lda #2
        bne @papi_set
@hi2:   lda #0
        beq @papi_set
@hi1:   lda #1
        bne @papi_set
@below: sec
        lda #0
        sbc tmp0
        sta tmp0
        lda #0
        sbc tmp1
        bne @lo2
        lda tmp0
        cmp #80
        bcs @lo2
        cmp #30
        bcs @lo1
        lda #2
        bne @papi_set
@lo2:   lda #4
        bne @papi_set
@lo1:   lda #3
@papi_set:
        sta papi
@rw_sched:
        ; 跑道贴块需要重画?(档/列/侧偏/地平线行变化)
        lda rw_task
        bne @rts
        lda rw_bucket
        cmp rw_drawn_b
        bne @redo
        lda rw_skew
        cmp rw_drawn_s
        bne @redo
        lda rw_col
        cmp rw_drawn_c
        beq @rts
@redo:  lda rw_drawn_b
        cmp #$FF
        beq @draw_only
        lda #1
        sta rw_task             ; 先擦
        rts
@draw_only:
        lda #2
        sta rw_task
@rts:   rts

; φ = atan2(ax(tmp1:tmp0), ay(tmp3:tmp2)) ∈ 0..64 → tmp4(自北的象限角)
atan_octant:
@nrm:   lda tmp1
        ora tmp3
        beq @low
        lsr tmp1
        ror tmp0
        lsr tmp3
        ror tmp2
        jmp @nrm
@low:   lda tmp0
        cmp tmp2
        bcs @ay_min
        lda tmp0                ; ax < ay:φ = atan(ax/ay)
        sta mul_lo
        lda tmp2
        sta mul_hi
        jsr ratio32
        tax
        lda atan_tab,x
        sta tmp4
        rts
@ay_min:
        lda tmp2
        sta mul_lo
        lda tmp0
        sta mul_hi
        jsr ratio32
        tax
        sec
        lda #64
        sbc atan_tab,x
        sta tmp4
        rts

; r = mul_lo×32/mul_hi(mul_lo ≤ mul_hi;逐步累加法,精确)
ratio32:
        lda mul_hi
        bne @go
        lda #0
        rts
@go:    lda #0
        sta tmp4
        lda #0
        ldy #32
@l:     clc
        adc mul_lo
        bcs @ge
        cmp mul_hi
        bcc @st
@ge:    sbc mul_hi              ; 进位已置(bcs 或 cmp≥),模 256 结果正确
        inc tmp4
@st:    dey
        bne @l
        lda tmp4
        rts

; ============================================================================
; 视图更新(每帧):滚动、地平线任务、跑道贴块任务
; ============================================================================
pan_update:
        ; pan = ψ·2 - 128 + 震动(9 位)
        lda psi_hi
        asl a
        sta pan_lo
        lda #0
        rol a
        sta pan_nt
        sec
        lda pan_lo
        sbc #128
        sta pan_lo
        bcs @shk
        lda pan_nt
        eor #$01
        sta pan_nt
@shk:   lda shake_x
        beq @rts
        bmi @sh_n
        clc
        adc pan_lo
        sta pan_lo
        bcc @rts
        lda pan_nt
        eor #$01
        sta pan_nt
        rts
@sh_n:  clc
        adc pan_lo
        sta pan_lo
        bcs @rts
        lda pan_nt
        eor #$01
        sta pan_nt
@rts:   rts

view_tick:
        jsr pan_update
        ; 地平线目标:hl = clamp(64+θ, 48..79)
        lda theta
        clc
        adc #64
        cmp #48
        bcs @c1
        lda #48
@c1:    cmp #80
        bcc @c2
        lda #79
@c2:    sta hl_px
        cmp hl_cur
        beq @hz_go
        sta hl_cur
        lda #5
        sta hz_task
        ; 地平线变行会盖掉跑道贴块 → 待重画
        lda #$FF
        sta rw_drawn_b
@hz_go: lda hz_task
        beq @rw_go
        lda buf_w
        cmp #112
        bcs @rts                ; 缓冲紧张,下帧再画
        ; 每帧重画一行(行 6..10):row = 11 - task
        sec
        lda #11
        sbc hz_task
        jsr hz_emit_row
        dec hz_task
        rts                     ; 本帧缓冲已够满
@rw_go: lda rw_task
        beq @rts
        lda buf_w
        cmp #110
        bcs @rts                ; 缓冲紧张,推迟
        lda rw_task
        cmp #1
        bne @rw_draw
        jsr rw_erase
        lda #2
        sta rw_task
        rts
@rw_draw:
        jsr rw_draw_stamp
        lda #0
        sta rw_task
@rts:   rts

; A=行(6-10)→ 地面瓦片:低空扑面粗纹理 + 行奇偶双相(调色板行进)
gnd_tile:
        tax
        lda grush
        beq @fine
        cmp #2
        bcs @co9
        cpx #10
        bcs @coarse
        bcc @fine
@co9:   cpx #9
        bcs @coarse
@fine:  txa
        and #$01
        beq @f_a
        lda #$69
        rts
@f_a:   lda #$68
        rts
@coarse:
        txa
        and #$01
        beq @c_a
        lda #$7D
        rts
@c_a:   lda #$7C
        rts

; 发射地平线行 A=row(6..10):两个 NT 各 32 字节
hz_emit_row:
        sta tmp4                ; row
        ; 决定该行瓦片:row < hl_row → $00;== → $60+sub;> → 地面
        lda hl_cur
        lsr a
        lsr a
        lsr a
        sta tmp5                ; hl_row
        lda tmp4
        cmp tmp5
        bcc @sky
        beq @line
        lda tmp4
        jsr gnd_tile
        jmp @have
@sky:   lda #$00
        beq @have
@line:  lda hl_cur
        and #$07
        clc
        adc #$60
@have:  sta tmp6                ; 瓦片
        ; NT0:addr = $2000 + row·32
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        sta tmp7                ; row·32 低(row≤9 → ≤288?9·32=288>255!)
        ; row·32:9·32=288 = $120 → 高位 = row>>3
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta tmp5                ; addr 高
        ldy buf_w
        sta ppu_buf,y
        iny
        lda tmp7
        sta ppu_buf,y
        iny
        lda #32
        sta ppu_buf,y
        iny
        ldx #0
        lda tmp6
@f0:    sta ppu_buf,y
        iny
        inx
        cpx #32
        bne @f0
        ; NT1
        lda tmp5
        clc
        adc #$04
        sta ppu_buf,y
        iny
        lda tmp7
        sta ppu_buf,y
        iny
        lda #32
        sta ppu_buf,y
        iny
        ldx #0
        lda tmp6
@f1:    sta ppu_buf,y
        iny
        inx
        cpx #32
        bne @f1
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; 擦除已画跑道区(13 列 × 3 行,地面双相瓦片)+ 恢复地面调色板
rw_erase:
        lda rw_drawn_b
        cmp #$FF
        beq @rts
        lda rw_drawn_r
        sta tmp4
        ldx #3
@row:   stx tmp3
        lda tmp4
        cmp #11
        bcs @attr
        lda rw_drawn_c
        sec
        sbc #6
        and #$3F
        sta tmp2
        lda #13
        sta tmp5
        lda tmp4
        jsr gnd_tile
        sta tmp6
        jsr emit_run
        inc tmp4
        ldx tmp3
        dex
        bne @row
@attr:  ; 属性恢复 pal3($FF)
        lda rw_att_c
        cmp #$FF
        beq @done
        ldx rw_att_n
        beq @att_z
@al:    stx tmp3
        lda rw_att_c
        clc
        adc tmp3
        sec
        sbc #1
        and #$0F
        jsr rw_attr_addr
        ldy buf_w
        lda tmp0
        sta ppu_buf,y
        iny
        lda tmp1
        sta ppu_buf,y
        iny
        lda #1
        sta ppu_buf,y
        iny
        lda #$FF
        sta ppu_buf,y
        iny
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        ldx tmp3
        dex
        bne @al
@att_z: lda #$FF
        sta rw_att_c
@done:  lda #$FF
        sta rw_drawn_b
@rts:   rts

; A=属性格(0-15,bit3=NT)→ tmp0=地址高 tmp1=地址低(行 8-11 的属性行)
rw_attr_addr:
        tax
        and #$07
        clc
        adc #$D0
        sta tmp1
        lda #$23
        cpx #8
        bcc @nt0
        lda #$27
@nt0:   sta tmp0
        rts

; 画跑道贴块(rw_bucket 0..4 → 表;5 → 仅精灵)
; 行处理:侧偏(顶行全偏/中行半偏)→ 垫宽到属性格 → 中线相位替换 → 发射
rw_draw_stamp:
        lda rw_bucket
        cmp #5
        bcc @stamp_go
        jmp @sprite_only
@stamp_go:
        sta rw_drawn_b
        lda rw_col
        sta rw_drawn_c
        lda rw_skew
        sta rw_drawn_s
        lda hl_cur
        lsr a
        lsr a
        lsr a
        clc
        adc #1
        sta rw_drawn_r
        sta tmp4                ; 当前行
        lda rw_bucket
        asl a
        tax
        lda stamp_ptr,x
        sta ptr_lo
        lda stamp_ptr+1,x
        sta ptr_hi
        ldy #0
        lda (ptr_lo),y
        sta tmp3                ; 剩余行数
        iny
@row:   lda tmp4
        cmp #11
        bcc @row_go
        jmp @attr
@row_go:
        lda (ptr_lo),y
        iny
        sta tmp5                ; 原宽
        lsr a
        sta tmp0
        lda rw_col
        sec
        sbc tmp0
        ; 行侧偏:最末行不偏,中行半偏,其上全偏
        ldx tmp3
        dex
        beq @sk_done
        cpx #1
        bne @sk_full
        sta tmp0
        lda rw_skew
        cmp #$80
        ror a
        clc
        adc tmp0
        jmp @sk_done
@sk_full:
        clc
        adc rw_skew
@sk_done:
        and #$3F
        sta tmp7                ; 未垫起点
        and #$03
        sta tmp0                ; 左垫
        lda tmp7
        and #$3C
        sta tmp2                ; 垫后起点
        ; 垫后宽 =(左垫+宽+3)&~3,钳 16
        lda tmp0
        clc
        adc tmp5
        clc
        adc #3
        and #$FC
        cmp #17
        bcc @pw_ok
        lda #16
@pw_ok: sta tmp7                ; 垫后宽
        ; 本行垫瓦片
        lda tmp4
        jsr gnd_tile
        sta tmp6
        ; 填暂存:左垫 | 数据(中线相位替换) | 右垫
        ldx #0
@lp:    cpx tmp0
        bcs @data
        lda tmp6
        sta stage,x
        inx
        bne @lp
@data:  lda tmp5
        sta tmp0                ; 复用:剩余数据数
@dl:    lda (ptr_lo),y
        iny
        cmp #$73
        bne @d_put
        lda mch_phase
        beq @d_73
        lda #$7E
        bne @d_put
@d_73:  lda #$73
@d_put: sta stage,x
        inx
        dec tmp0
        bne @dl
@rp:    cpx tmp7
        bcs @emit
        lda tmp6
        sta stage,x
        inx
        bne @rp
@emit:  lda tmp7
        sta tmp5                ; 发射宽 = 垫后宽
        sty tmp1
        jsr emit_stage
        ldy tmp1
        inc tmp4
        dec tmp3
        beq @attr
        jmp @row
@attr:  ; 跑道格切 pal1(白标线可用);记录以便擦除恢复
        lda tmp2
        lsr a
        lsr a
        sta rw_att_c
        lda tmp5
        lsr a
        lsr a
        sta rw_att_n
        beq @adone
        ldx rw_att_n
@al:    stx tmp3
        lda rw_att_c
        clc
        adc tmp3
        sec
        sbc #1
        and #$0F
        jsr rw_attr_addr
        ldy buf_w
        cpy #190
        bcs @adone
        lda tmp0
        sta ppu_buf,y
        iny
        lda tmp1
        sta ppu_buf,y
        iny
        lda #1
        sta ppu_buf,y
        iny
        lda #$55
        sta ppu_buf,y
        iny
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        ldx tmp3
        dex
        bne @al
@adone: rts
@sprite_only:
        lda #5
        sta rw_drawn_b
        lda rw_col
        sta rw_drawn_c
        lda rw_skew
        sta rw_drawn_s
        lda #10
        sta rw_drawn_r          ; 无贴块
        rts

; 单值行段:tmp2=起始列 tmp4=行 tmp5=宽 tmp6=瓦片
emit_run:
        jsr run_setup
        ; 段 1
        lda tmp7
        beq @seg2
        tax
        ldy buf_w
        lda num_hi
        sta ppu_buf,y
        iny
        lda num_lo
        sta ppu_buf,y
        iny
        txa
        sta ppu_buf,y
        iny
        lda tmp6
@w1:    sta ppu_buf,y
        iny
        dex
        bne @w1
        sty buf_w
@seg2:  lda tmp5
        sec
        sbc tmp7
        beq @fin
        tax
        ldy buf_w
        lda mul_hi
        sta ppu_buf,y
        iny
        lda mul_lo
        sta ppu_buf,y
        iny
        txa
        sta ppu_buf,y
        iny
        lda tmp6
@w2:    sta ppu_buf,y
        iny
        dex
        bne @w2
        sty buf_w
@fin:   ldy buf_w
        lda #$FF
        sta ppu_buf,y
        rts

; 暂存行段发射:tmp2=起始列 tmp4=行 tmp5=宽,数据在 stage
emit_stage:
        jsr run_setup
        ldy #0
        ; 段 1(tmp7 个)
        lda tmp7
        beq @s2
        sta tmp0
        ldx buf_w
        lda num_hi
        sta ppu_buf,x
        inx
        lda num_lo
        sta ppu_buf,x
        inx
        lda tmp7
        sta ppu_buf,x
        inx
@c1:    lda stage,y
        iny
        sta ppu_buf,x
        inx
        dec tmp0
        bne @c1
        stx buf_w
@s2:    lda tmp5
        sec
        sbc tmp7
        beq @fin
        sta tmp0
        ldx buf_w
        lda mul_hi
        sta ppu_buf,x
        inx
        lda mul_lo
        sta ppu_buf,x
        inx
        lda tmp0
        sta ppu_buf,x
        inx
@c2:    lda stage,y
        iny
        sta ppu_buf,x
        inx
        dec tmp0
        bne @c2
        stx buf_w
@fin:   ldx buf_w
        lda #$FF
        sta ppu_buf,x
        rts

; 计算跨 NT 的行段:输入 tmp2(列 0..63) tmp4(行) tmp5(宽)
; 输出:num=段1地址(len=tmp7),mul=段2地址(len=tmp5-tmp7)
run_setup:
        ; 段 1 长度 = min(宽, 32-(列&31))
        lda tmp2
        and #$1F
        sta tmp0
        sec
        lda #32
        sbc tmp0
        cmp tmp5
        bcc @part
        lda tmp5
@part:  sta tmp7
        ; 段 1 地址:NT = 列 bit5,addr = base + 行·32 + (列&31)
        lda tmp2
        and #$20
        beq @nt0
        lda #$04
        bne @nt
@nt0:   lda #$00
@nt:    sta num_hi              ; 暂存 NT 偏移(高位加成)
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        sta num_lo
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        clc
        adc num_hi
        sta num_hi
        lda num_lo
        clc
        adc tmp0
        sta num_lo
        bcc @a1
        inc num_hi
@a1:    ; 段 2:另一 NT,列 0
        lda tmp2
        and #$20
        beq @nt1b
        lda #$00
        beq @ntb
@nt1b:  lda #$04
@ntb:   sta mul_hi
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        sta mul_lo
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        clc
        adc mul_hi
        sta mul_hi
        rts

; ============================================================================
; HUD(轮转字段,跳表)
; ============================================================================
hud_tick:
        lda frame
        and #$07
        asl a
        tax
        lda hud_jmp,x
        sta ptr_lo
        lda hud_jmp+1,x
        sta ptr_hi
        jmp (ptr_lo)

hud_term:
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; 打开缓冲条目:A=hi X=lo Y 长度→tmp0;返回 Y=游标
buf_open:
        sty tmp0
        ldy buf_w
        sta ppu_buf,y
        iny
        txa
        sta ppu_buf,y
        iny
        lda tmp0
        sta ppu_buf,y
        iny
        rts

hud_f0: ; IAS(3)@ row13 col18
        lda vint
        jsr b2d8
        lda #$21
        ldx #$B2
        ldy #3
        jsr buf_open
        ldx #0
@c:     lda dec_buf+2,x
        sta ppu_buf,y
        iny
        inx
        cpx #3
        bne @c
        jmp hud_term

hud_f1: ; ALT(5)@ row14 col18
        lda h_lo
        sta num_lo
        lda h_hi
        sta num_hi
        jsr b2d16
        lda #$21
        ldx #$D2
        ldy #5
        jsr buf_open
        ldx #0
@c:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @c
        jmp hud_term

hud_f2: ; VS(±4)@ row15 col17
        lda vs16_hi
        bmi @neg
        lda vs16_lo
        sta num_lo
        lda vs16_hi
        sta num_hi
        lda #'+'
        bne @sgn
@neg:   sec
        lda #0
        sbc vs16_lo
        sta num_lo
        lda #0
        sbc vs16_hi
        sta num_hi
        lda #'-'
@sgn:   sta tmp2
        jsr b2d16
        lda #$21
        ldx #$F1
        ldy #5
        jsr buf_open
        lda tmp2
        sta ppu_buf,y
        iny
        ldx #1
@c:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @c
        jmp hud_term

hud_f3: ; HDG(3)@ row16 col18:deg = ψ + ψ·13/32
        lda psi_hi
        sta tmp0
        lda #13
        sta tmp1
        jsr mul8x8
        ldx #5
@s:     lsr mul_hi
        ror mul_lo
        dex
        bne @s
        lda psi_hi
        clc
        adc mul_lo
        sta num_lo
        lda #0
        adc mul_hi
        sta num_hi
        jsr b2d16
        lda #$22
        ldx #$12
        ldy #3
        jsr buf_open
        ldx #2
@c:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @c
        jmp hud_term

hud_f4: ; RPM(4)@ row17 col18(真实转速:定距桨随空速,带惯性)
        lda rpm_lo
        sta num_lo
        lda rpm_hi
        sta num_hi
        jsr b2d16
        lda #$22
        ldx #$32
        ldy #4
        jsr buf_open
        ldx #1
@c:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @c
        jmp hud_term

hud_f5: ; FLP(2)@ row18 col18 + PIT(±2)@ col25
        lda flaps
        asl a
        tax
        lda #$22
        stx tmp3
        ldx #$52
        ldy #2
        jsr buf_open
        ldx tmp3
        lda flap_str,x
        sta ppu_buf,y
        iny
        lda flap_str+1,x
        sta ppu_buf,y
        iny
        sty buf_w
        ; PIT:θ/2 带符号
        lda theta
        bmi @pn
        lsr a
        tax
        lda #'+'
        bne @pw
@pn:    eor #$FF
        clc
        adc #1
        lsr a
        tax
        lda #'-'
@pw:    sta tmp2
        txa
        jsr b2d8
        lda #$22
        ldx #$59
        ldy #3
        jsr buf_open
        lda tmp2
        sta ppu_buf,y
        iny
        lda dec_buf+3
        sta ppu_buf,y
        iny
        lda dec_buf+4
        sta ppu_buf,y
        iny
        jmp hud_term

hud_f6: ; 航段名/目标/评分槽(脏时)@ row19
        lda hud_leg_dirty
        ora grades_dirty
        bne @go
        rts
@go:    lda #0
        sta hud_leg_dirty
        sta grades_dirty
        ldx leg
        lda leg_name_lo,x
        sta ptr_lo
        lda leg_name_hi,x
        sta ptr_hi
        lda #$22
        ldx #$65
        ldy #8
        jsr buf_open
        sty tmp3
        ldy #0
@n:     lda (ptr_lo),y
        ldx tmp3
        sta ppu_buf,x
        inc tmp3
        iny
        cpy #8
        bne @n
        ldy tmp3
        sty buf_w
        ; TGT
        lda leg
        asl a
        adc leg
        tax
        stx tmp3
        lda #$22
        ldx #$72
        ldy #3
        jsr buf_open
        ldx tmp3
        lda tgt_ias_str,x
        sta ppu_buf,y
        iny
        lda tgt_ias_str+1,x
        sta ppu_buf,y
        iny
        lda tgt_ias_str+2,x
        sta ppu_buf,y
        iny
        sty buf_w
        ; 评分槽
        lda #$22
        ldx #$78
        ldy #6
        jsr buf_open
        ldx #0
@g:     lda grades,x
        sta ppu_buf,y
        iny
        inx
        cpx #6
        bne @g
        ; 分数 @ row21 col19
        sty buf_w
        lda score_lo
        sta num_lo
        lda score_hi
        sta num_hi
        jsr b2d16
        lda #$22
        ldx #$B3
        ldy #5
        jsr buf_open
        ldx #0
@s:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @s
        jmp hud_term

hud_f7: ; 消息计时 + 分数刷新
        lda msg_timer
        beq @demo
        dec msg_timer
        bne @score
        jsr msg_clear
        rts
@demo:  lda ai_on
        beq @score
        lda frame
        bne @score
        lda #M_DEMO
        jsr msg_set
        rts
@score: lda frame
        and #$38
        bne @rts
        lda score_lo
        sta num_lo
        lda score_hi
        sta num_hi
        jsr b2d16
        lda #$22
        ldx #$B3
        ldy #5
        jsr buf_open
        ldx #0
@s:     lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @s
        jmp hud_term
@rts:   rts

; ---------------- 消息(row20)----------------
msg_set:
        sta msg_id
        cmp #M_NONE
        beq @rts
        ldy buf_w
        cpy #168
        bcs @rts                ; 缓冲紧张,弃本条视觉(极罕见)
        tax
        lda msg_lo,x
        sta ptr_lo
        lda msg_hi,x
        sta ptr_hi
        lda #240
        sta msg_timer
        lda #$22
        ldx #$81
        ldy #30
        jsr buf_open
        sty tmp3
        ldy #0
        ldx tmp3
@cp:    lda (ptr_lo),y
        beq @pad
        sta ppu_buf,x
        inx
        iny
        cpy #30
        bne @cp
        beq @fin
@pad:   lda #' '
@pl:    sta ppu_buf,x
        inx
        iny
        cpy #30
        bne @pl
@fin:   lda #$FF
        sta ppu_buf,x
        stx buf_w
@rts:   rts

msg_clear:
        lda #$22
        ldx #$81
        ldy #30
        jsr buf_open
        ldx #0
        lda #' '
@sp:    sta ppu_buf,y
        iny
        inx
        cpx #30
        bne @sp
        lda #M_NONE
        sta msg_id
        lda #0
        sta msg_timer
        jmp hud_term

; ============================================================================
; 精灵:仪表指针 / PAPI / 远跑道 / 失速灯 / 小地图点 / 转弯箭头
; ============================================================================

; 画一枚指针:A=方向 0-15,tmp2=cx tmp3=cy,X=OAM 偏移(×4)
draw_needle:
        and #$0F
        tay
        lda tmp3
        clc
        adc ndl_dy,y
        sta oam,x
        inx
        lda ndl_tile,y
        sta oam,x
        inx
        lda ndl_attr,y
        sta oam,x
        inx
        lda tmp2
        clc
        adc ndl_dx,y
        sta oam,x
        rts

game_sprites:
        ; --- ASI:V 0..160 → 方向 0..15(V×24>>8) ---
        lda vint
        sta tmp0
        lda #24
        sta tmp1
        jsr mul8x8
        lda #20
        sta tmp2
        lda #115
        sta tmp3
        lda mul_hi
        ldx #4                  ; OAM 槽 1
        jsr draw_needle
        ; --- ALT 百位针:(alt mod 1000)>>6 ---
        lda h_lo
        sta num_lo
        lda h_hi
        sta num_hi
@m1k:   lda num_hi
        cmp #>1000
        bcc @mod_ok
        bne @msub
        lda num_lo
        cmp #<1000
        bcc @mod_ok
@msub:  sec
        lda num_lo
        sbc #<1000
        sta num_lo
        lda num_hi
        sbc #>1000
        sta num_hi
        jmp @m1k
@mod_ok:
        ; d = (mod1000)>>6 = (hi<<2)|(lo>>6),钳 15
        lda num_hi
        asl a
        asl a
        sta tmp4
        lda num_lo
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp4
        cmp #16
        bcc @alt_d
        lda #15
@alt_d: ldx #8
        pha
        lda #84
        sta tmp2
        lda #115
        sta tmp3
        pla
        jsr draw_needle
        ; --- ALT 千位短针(灰):h>>9(0..4) ---
        lda h_hi
        lsr a
        and #$0F
        ldx #12
        pha
        lda #84
        sta tmp2
        lda #115
        sta tmp3
        pla
        jsr draw_needle
        lda #$02                ; 千位针灰色调色板
        sta oam+14
        ; --- TACH:thr → 1+thr·3/2 ---
        lda thr
        asl a
        clc
        adc thr
        lsr a
        clc
        adc #1
        ldx #16
        pha
        lda #20
        sta tmp2
        lda #139
        sta tmp3
        pla
        jsr draw_needle
        ; --- DG:ψ>>4 ---
        lda psi_hi
        clc
        adc #8
        lsr a
        lsr a
        lsr a
        lsr a
        ldx #20
        pha
        lda #52
        sta tmp2
        lda #139
        sta tmp3
        pla
        jsr draw_needle
        ; --- VSI:12 + clamp(vs16_hi(≈vs/256), ±5) ---
        lda vs16_hi
        bpl @vsi_p
        cmp #<(-5)
        bcs @vsi_ok
        lda #<(-5)
        bne @vsi_ok
@vsi_p: cmp #6
        bcc @vsi_ok
        lda #5
@vsi_ok:
        clc
        adc #12
        and #$0F
        ldx #24
        pha
        lda #84
        sta tmp2
        lda #139
        sta tmp3
        pla
        jsr draw_needle
        ; --- AI 地平杆(2 精灵):y = 115 + clamp(θ>>2,±6),坡度选瓦片 ---
        lda theta
        cmp #$80
        ror a
        cmp #$80
        ror a                   ; 算术 >>2
        clc
        adc #115
        sta tmp4
        ldx bank_idx
        lda bank88_hi
        bmi @ai_l
        ; 右坡:V 翻转左右对调
        lda ai_bar_l,x
        sta tmp5
        lda ai_bar_r,x
        sta tmp6
        lda #$80
        sta tmp7
        bne @ai_put
@ai_l:  lda ai_bar_l,x
        sta tmp5
        lda ai_bar_r,x
        sta tmp6
        lda #$00
        sta tmp7
@ai_put:
        lda tmp4
        sta oam+28
        sta oam+32
        lda tmp5
        sta oam+29
        lda tmp6
        sta oam+33
        lda tmp7
        sta oam+30
        sta oam+34
        lda #44
        sta oam+31
        lda #52
        sta oam+35
        ; --- 失速灯(闪红,面板右上) ---
        lda horn_on
        beq @lamp_off
        lda frame
        and #$08
        bne @lamp_off
        lda #103
        sta oam+36
        lda #$4C
        sta oam+37
        lda #$00
        sta oam+38
        lda #244
        sta oam+39
        jmp @papi_s
@lamp_off:
        lda #$F8
        sta oam+36
@papi_s:
        ; --- PAPI(2 精灵 = 4 灯),五边且跑道可见 ---
        lda leg
        cmp #LEG_FINAL
        bcc @papi_off
        cmp #LEG_ROLLOUT
        bcs @papi_off
        lda rw_bucket
        cmp #$FF
        beq @papi_off
        ; 位置:跑道左侧
        lda rw_rel
        asl a
        clc
        adc #128
        sec
        sbc #24
        sta tmp2
        lda hl_cur
        clc
        adc #3
        sta tmp3
        lda papi
        asl a
        tax
        lda papi_spr,x
        sta oam+41
        lda papi_spr+1,x
        sta oam+45
        lda tmp3
        sta oam+40
        sta oam+44
        lda #$00
        sta oam+42
        sta oam+46
        lda tmp2
        sta oam+43
        clc
        adc #8
        sta oam+47
        jmp @rwspr
@papi_off:
        lda #$F8
        sta oam+40
        sta oam+44
@rwspr: ; --- 远跑道精灵(bucket 5) ---
        lda rw_bucket
        cmp #5
        bne @rw_off
        lda rw_rel
        asl a
        clc
        adc #128
        sec
        sbc #4
        sta tmp2
        lda hl_cur
        sec
        sbc #4
        sta oam+48
        lda #$4E
        sta oam+49
        lda #$00
        sta oam+50
        lda tmp2
        sta oam+51
        jmp @mapdot
@rw_off:
        lda #$F8
        sta oam+48
@mapdot:
        ; --- 小地图点:x∈[-2400,400] y∈[-3200,3200] → 框内 ---
        lda px_lo
        clc
        adc #<2400
        sta tmp0
        lda px_hi
        adc #>2400
        sta tmp1
        bpl @mx_ok
        lda #0
        sta tmp0
        sta tmp1
@mx_ok: ldx #5
@mxs:   lsr tmp1
        ror tmp0
        dex
        bne @mxs
        lda tmp0
        cmp #88
        bcc @mx2
        lda #87
@mx2:   clc
        adc #20
        sta tmp2                ; 屏幕 x
        sec
        lda #<3200
        sbc py_lo
        sta tmp0
        lda #>3200
        sbc py_hi
        sta tmp1
        bpl @my_ok
        lda #0
        sta tmp0
        sta tmp1
@my_ok: ldx #7
@mys:   lsr tmp1
        ror tmp0
        dex
        bne @mys
        lda tmp0
        cmp #40
        bcc @my2
        lda #39
@my2:   clc
        adc #167
        sta oam+52
        lda #$4D
        sta oam+53
        lda #$02
        sta oam+54
        lda tmp2
        sta oam+55
        ; --- 转弯提示箭头(闪) ---
        lda turn_phase
        cmp #1
        bne @arr_off
        lda frame
        and #$08
        bne @arr_off
        ldx #0
@arr:   lda arrow_y,x
        sta oam+56,x
        inx
        cpx #16
        bne @arr
        jmp @v3_spr
@arr_off:
        lda #$F8
        sta oam+56
        sta oam+60
        sta oam+64
        sta oam+68
@v3_spr:
        ; --- 油门旋钮(仪表台滑槽上) ---
        lda #182
        sta oam+72
        lda #$52
        sta oam+73
        lda #$00
        sta oam+74
        lda thr
        asl a
        asl a
        asl a
        clc
        adc #160
        sta oam+75
        ; --- 坡度云暗示:压坡度时两侧云反向升降(外景滚转感) ---
        lda on_ground
        bne @cl_off
        lda bank88_hi
        cmp #$80
        ror a
        cmp #$80
        ror a                   ; bank/4(±7)
        sta tmp0
        sec
        lda #24
        sbc tmp0
        sta oam+76
        lda #$51
        sta oam+77
        lda #$00
        sta oam+78
        lda #44
        sta oam+79
        clc
        lda #28
        adc tmp0
        sta oam+80
        lda #$51
        sta oam+81
        lda #$00
        sta oam+82
        lda #204
        sta oam+83
        rts
@cl_off:
        lda #$F8
        sta oam+76
        sta oam+80
        rts

; 标题画面的侧视飞机(v1 版,OAM 1-6)
draw_plane_at:
        sta tmp0
        lda pose
        asl a
        sta tmp1
        lda frame
        lsr a
        lsr a
        and #1
        clc
        adc tmp1
        sta tmp1
        asl a
        adc tmp1
        asl a
        clc
        adc #$10
        sta tmp1
        ldx #0
        ldy #0
@t:     tya
        cmp #3
        lda plane_py
        bcc @r0
        clc
        adc #8
@r0:    sec
        sbc #1
        sta oam+4,x
        tya
        clc
        adc tmp1
        sta oam+5,x
        lda #$00
        sta oam+6,x
        sty tmp2
        tya
        cmp #3
        bcc @c0
        sec
        sbc #3
@c0:    asl a
        asl a
        asl a
        clc
        adc tmp0
        sta oam+7,x
        ldy tmp2
        inx
        inx
        inx
        inx
        iny
        cpy #6
        bne @t
        rts

; ============================================================================
; 讲评
; ============================================================================
enter_debrief:
        lda #0
        sta $2000
        sta $2001
        bit $2002
        lda #ST_DEBRIEF
        sta game_state
        lda #0
        sta pan_lo
        sta pan_nt
        sta tt_lo
        sta tt_hi
        sta shake_x
        sta shake_fy
        jsr draw_debrief
        lda #$FF
        sta ppu_buf
        lda #0
        sta buf_w
        lda #$3F
        sta $2006
        lda #$00
        sta $2006
        lda #$0F
        sta $2007
        lda #$0A
        sta $2001
        ldx #$F8
        ldy #0
@h:     txa
        sta oam,y
        iny
        iny
        iny
        iny
        bne @h
        ldy #CH_OK
        jsr chime_start
        lda #PPUCTRL_BASE
        sta $2000
        rts

tick_debrief:
        lda pad_new
        and #BTN_SEL
        beq @n_sel
        lda #1
        jmp fade_begin
@n_sel: lda pad_new
        and #BTN_STA
        beq @auto
        ; START:玩家完好落地 → 昼夜进阶续飞(总分累计);否则重新开局
        lda crashed
        bne @fresh
        lda ai_on
        bne @fresh
        lda night_lvl
        cmp #2
        bcs @cont
        inc night_lvl
@cont:  lda #1
        sta cont_flag
        lda #0
        sta fade_arg
        lda #2
        jmp fade_begin
@fresh: lda #0
        sta fade_arg
        sta cont_flag
        lda #2
        jmp fade_begin
@auto:  ; 演示讲评 ~13s 后自动回标题(循环吸引)
        lda ai_on
        beq @rts
        inc tt_lo
        bne @rts
        inc tt_hi
        lda tt_hi
        cmp #3
        bcc @rts
        lda #1
        jmp fade_begin
@rts:   rts

; ============================================================================
; 画面绘制(渲染关时直写)
; ============================================================================
load_palettes:
        ldx night_lvl
        lda palset_lo,x
        sta pal_ptr
        lda palset_hi,x
        sta pal_ptr+1
        lda #$3F
        sta $2006
        lda #$00
        sta $2006
        lda fade_step
        asl a
        asl a
        asl a
        asl a
        sta tmp0
        ldy #0
@p:     lda (pal_ptr),y
        sec
        sbc tmp0
        bcs @ok
        lda #$0F
@ok:    sta $2007
        iny
        cpy #32
        bne @p
        rts

; ---------------- 转场渐变 ----------------
; 请求转场:A = 1 标题 / 2 游戏 / 3 讲评
fade_begin:
        ldx fade_mode
        bne @rts
        sta fade_next
        lda #1
        sta fade_mode
        lda #0
        sta fade_step
        lda #1
        sta fade_t
@rts:   rts

fade_tick:
        lda fade_mode
        bne @go
        rts
@go:    dec fade_t
        beq @step
        rts
@step:  lda #5
        sta fade_t
        lda fade_mode
        cmp #1
        beq @out
        lda fade_step
        beq @in_done
        dec fade_step
        jmp fade_emit
@in_done:
        lda #0
        sta fade_mode
        rts
@out:   lda fade_step
        cmp #4
        bcs @switch
        inc fade_step
        jmp fade_emit
@switch:
        lda #2
        sta fade_mode           ; 黑场切换后变亮
        lda fade_next
        cmp #1
        bne @n_t
        jmp enter_title
@n_t:   cmp #2
        bne @n_g
        lda fade_arg
        sta ai_on
        jmp enter_game
@n_g:   jmp enter_debrief

; 发射按 fade_step 暗化的整套调色板(缓冲)
fade_emit:
        ldy buf_w
        cpy #150
        bcs @rts
        lda #$3F
        sta ppu_buf,y
        iny
        lda #$00
        sta ppu_buf,y
        iny
        lda #32
        sta ppu_buf,y
        iny
        sty tmp1
        lda fade_step
        asl a
        asl a
        asl a
        asl a
        sta tmp0
        ldy #0
@l:     lda (pal_ptr),y
        sec
        sbc tmp0
        bcs @ok
        lda #$0F
@ok:    sty tmp2
        ldy tmp1
        sta ppu_buf,y
        inc tmp1
        ldy tmp2
        iny
        cpy #32
        bne @l
        ldy tmp1
        lda #$FF
        sta ppu_buf,y
        sty buf_w
@rts:   rts

clear_nts:
        lda #$20
        sta $2006
        lda #$00
        sta $2006
        ldx #8
        ldy #0
        lda #$00
@c:     sta $2007
        iny
        bne @c
        dex
        bne @c
        rts

set_addr:
        sta $2006
        stx $2006
        rts

draw_str:
        ldy #0
@c:     lda (ptr_lo),y
        beq @done
        sta $2007
        iny
        bne @c
@done:  rts

; A=hi X=lo,Y=数量,tmp0=瓦片:横向填充
fill_run:
        sta $2006
        stx $2006
        lda tmp0
@f:     sta $2007
        dey
        bne @f
        rts

; ---------------- 座舱静态画面 ----------------
draw_cockpit_static:
        jsr clear_nts
        ; 属性:行 0-3 pal2,行 4-7 pal1,行 8-11 pal3(地面双相),行 12+ pal0
        ldx #0
        jsr @attr_one
        ldx #4
        jsr @attr_one
        ; 仪表格:空速表(格 0)pal1 = 绿/白弧;姿态仪(格 1)pal2 = 天蓝/藏青面
        lda #$23
        ldx #$D8
        jsr set_addr
        lda #$55
        sta $2007
        lda #$AA
        sta $2007
        jmp @sky
@attr_one:
        txa
        clc
        adc #$23
        sta $2006
        lda #$C0
        sta $2006
        ldy #8
        lda #$AA                ; 行 0-3:天空物 pal2
@a0:    sta $2007
        dey
        bne @a0
        ldy #8
        lda #$55                ; 行 4-7:山影/地平线上带 pal1
@a1:    sta $2007
        dey
        bne @a1
        ldy #8
        lda #$FF                ; 行 8-11:地面 pal3(闪烁行进)
@a1b:   sta $2007
        dey
        bne @a1b
        ldy #40
        lda #$00
@a2:    sta $2007
        dey
        bne @a2
        rts
@sky:   ; 两个 NT 的风挡行:云(行 1-3 散布)、山影(行 4-5)、
        ; 地平线(行 8)、地面(行 9-10)、机头罩(行 11)
        ldx #0                  ; NT 索引 0/1
@nt:    stx tmp5
        ; 云:行 1-3
        ldy #1
@cl_row:
        sty tmp4
        jsr row_addr
        ldx #0
@cl_c:  txa
        asl a
        clc
        adc tmp4
        adc tmp5
        and #$07
        bne @cl_no
        lda #$6D
        bne @cl_put
@cl_no: lda #$00
@cl_put:
        sta $2007
        inx
        cpx #32
        bne @cl_c
        ldy tmp4
        iny
        cpy #4
        bne @cl_row
        ; 行 4:稀疏山峰
        lda #4
        sta tmp4
        jsr row_addr
        ldx #0
@h4:    txa
        clc
        adc tmp5
        and #$07
        cmp #3
        bne @h4_no
        lda #$6B
        bne @h4_put
@h4_no: lda #$00
@h4_put:
        sta $2007
        inx
        cpx #32
        bne @h4
        ; 行 5:连续山影/森林
        lda #5
        sta tmp4
        jsr row_addr
        ldx #0
@h5:    txa
        clc
        adc tmp5
        and #$03
        beq @h5_a
        lda #$6C
        bne @h5_put
@h5_a:  lda #$6A
@h5_put:
        sta $2007
        inx
        cpx #32
        bne @h5
        ; 行 8:地平线;行 9-10 地面;行 11 机头罩
        lda #8
        sta tmp4
        jsr row_addr
        lda #$60
        ldx #32
@l8:    sta $2007
        dex
        bne @l8
        lda #9
        sta tmp4
        jsr row_addr
        lda #$69                ; 行奇偶双相(调色板行进用)
        ldx #32
@g9:    sta $2007
        dex
        bne @g9
        lda #10
        sta tmp4
        jsr row_addr
        lda #$68
        ldx #32
@g10:   sta $2007
        dex
        bne @g10
        lda #11
        sta tmp4
        jsr row_addr
        lda #$78
        ldx #32
@cw:    sta $2007
        dex
        bne @cw
        ldx tmp5
        inx
        cpx #2
        beq @panel
        jmp @nt
@panel: ; ---- 面板(NT0 行 12-29) ----
        lda #$21
        ldx #$80
        jsr set_addr
        lda #$02
        ldx #32
@pe:    sta $2007
        dex
        bne @pe
        ; 行 13-29 填充
        ldy #13
@pf_row:
        sty tmp4
        lda #0
        sta tmp5
        jsr row_addr
        lda #$8A
        ldx #32
@pf:    sta $2007
        dex
        bne @pf
        ldy tmp4
        iny
        cpy #30
        bne @pf_row
        ; 六联表圈:两行三列(空速表带彩弧面,姿态仪带天地面)
        lda #$90
        ldx #1
        ldy #13
        jsr draw_bezel
        lda #$99
        ldx #5
        ldy #13
        jsr draw_bezel
        lda #$80
        ldx #9
        ldy #13
        jsr draw_bezel
        lda #$80
        ldx #1
        ldy #16
        jsr draw_bezel
        lda #$80
        ldx #5
        ldy #16
        jsr draw_bezel
        lda #$80
        ldx #9
        ldy #16
        jsr draw_bezel
        ; 数字区标签
        lda #<s_ias
        sta ptr_lo
        lda #>s_ias
        sta ptr_hi
        lda #$21
        ldx #$AE
        jsr set_addr
        jsr draw_str
        lda #<s_alt
        sta ptr_lo
        lda #>s_alt
        sta ptr_hi
        lda #$21
        ldx #$CE
        jsr set_addr
        jsr draw_str
        lda #<s_vs
        sta ptr_lo
        lda #>s_vs
        sta ptr_hi
        lda #$21
        ldx #$EE
        jsr set_addr
        jsr draw_str
        lda #<s_hdg
        sta ptr_lo
        lda #>s_hdg
        sta ptr_hi
        lda #$22
        ldx #$0E
        jsr set_addr
        jsr draw_str
        lda #<s_rpm
        sta ptr_lo
        lda #>s_rpm
        sta ptr_hi
        lda #$22
        ldx #$2E
        jsr set_addr
        jsr draw_str
        lda #<s_flp
        sta ptr_lo
        lda #>s_flp
        sta ptr_hi
        lda #$22
        ldx #$4E
        jsr set_addr
        jsr draw_str
        ; 行 19 框架:LEG/TGT/G
        lda #<s_row19
        sta ptr_lo
        lda #>s_row19
        sta ptr_hi
        lda #$22
        ldx #$61
        jsr set_addr
        jsr draw_str
        ; 行 21 SC
        lda #<s_sc
        sta ptr_lo
        lda #>s_sc
        sta ptr_hi
        lda #$22
        ldx #$B0
        jsr set_addr
        jsr draw_str
        ; 小地图框(行 21-25 列 2-13)
        lda #$22
        ldx #$A2
        jsr set_addr
        lda #$8B
        ldx #12
@mm_t:  sta $2007
        dex
        bne @mm_t
        ldy #22
@mm_r:  sty tmp4
        lda #0
        sta tmp5
        jsr row_addr
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #2
        tax
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta $2006
        stx $2006
        lda #$8C
        sta $2007
        ; 中间清黑
        lda #$01
        ldx #10
@mm_i:  sta $2007
        dex
        bne @mm_i
        lda #$8C
        sta $2007
        ldy tmp4
        iny
        cpy #26
        bne @mm_r
        ; 跑道标记(入口)在框右缘中部
        lda #$23
        ldx #$0C
        jsr set_addr
        lda #$8E
        sta $2007
        ; 油门滑槽(行 23:标签 + 槽)
        lda #<s_thr
        sta ptr_lo
        lda #>s_thr
        sta ptr_hi
        lda #$22
        ldx #$F0
        jsr set_addr
        jsr draw_str
        lda #$22
        ldx #$F4
        jsr set_addr
        lda #'-'
        ldx #9
@thr_s: sta $2007
        dex
        bne @thr_s
        ; 行 27 提示(列 3)
        lda #<s_hint
        sta ptr_lo
        lda #>s_hint
        sta ptr_hi
        lda #$23
        ldx #$63
        jsr set_addr
        jsr draw_str
        rts

; 行地址:tmp4=行(0-29) tmp5=NT(0/1)→ 设 $2006 到行首
row_addr:
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        sta tmp6
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        ldx tmp5
        beq @nt0
        clc
        adc #$04
@nt0:   sta $2006
        lda tmp6
        sta $2006
        rts

; 表圈 3×3:A=基瓦片 X=列 Y=起始行(渲染关直写)
draw_bezel:
        sta tmp1
        stx tmp2
        sty tmp3
        ldx #0
@r:     stx tmp7
        lda tmp3
        clc
        adc tmp7
        sta tmp6                ; 行
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc tmp2
        pha
        lda tmp6
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta $2006
        pla
        sta $2006
        ; tile = 基 + r·3 起连续 3 个
        lda tmp7
        asl a
        clc
        adc tmp7
        clc
        adc tmp1
        sta $2007
        clc
        adc #1
        sta $2007
        clc
        adc #1
        sta $2007
        ldx tmp7
        inx
        cpx #3
        bne @r
        rts

; ---------------- 标题画面 ----------------
draw_title:
        jsr clear_nts
        ; 属性:全 0,地面行 6-7 属性行 = $55
        lda #$23
        ldx #$C0
        jsr set_addr
        ldy #48
        lda #$00
@a0:    sta $2007
        dey
        bne @a0
        ldy #16
        lda #$55
@a1:    sta $2007
        dey
        bne @a1
        ; 云
        ldy #2
@cl_r:  sty tmp4
        lda #0
        sta tmp5
        jsr row_addr
        ldx #0
@cl:    txa
        asl a
        clc
        adc tmp4
        and #$07
        bne @cl_n
        lda #$6D
        bne @cl_p
@cl_n:  lda #$00
@cl_p:  sta $2007
        inx
        cpx #32
        bne @cl
        ldy tmp4
        iny
        cpy #6
        bne @cl_r
        ; 大字 C172S(行 8-9 列 11)
        lda #$21
        ldx #$0B
        jsr set_addr
        ldx #0
@l1:    txa
        clc
        adc #$C0
        sta $2007
        inx
        cpx #10
        bne @l1
        lda #$21
        ldx #$2B
        jsr set_addr
        ldx #0
@l2:    txa
        clc
        adc #$D0
        sta $2007
        inx
        cpx #10
        bne @l2
        ; 五边飞行(行 11-12 列 12)
        lda #$21
        ldx #$6C
        jsr set_addr
        ldx #0
@h1:    txa
        clc
        adc #$E0
        sta $2007
        inx
        cpx #8
        bne @h1
        lda #$21
        ldx #$8C
        jsr set_addr
        ldx #0
@h2:    txa
        clc
        adc #$F0
        sta $2007
        inx
        cpx #8
        bne @h2
        ; 文本
        lda #<str_sub
        sta ptr_lo
        lda #>str_sub
        sta ptr_hi
        lda #$21
        ldx #$E4
        jsr set_addr
        jsr draw_str
        lda #<str_poh
        sta ptr_lo
        lda #>str_poh
        sta ptr_hi
        lda #$22
        ldx #$23
        jsr set_addr
        jsr draw_str
        lda #<str_press
        sta ptr_lo
        lda #>str_press
        sta ptr_hi
        lda #$22
        ldx #$8A
        jsr set_addr
        jsr draw_str
        lda #<str_demo
        sta ptr_lo
        lda #>str_demo
        sta ptr_hi
        lda #$22
        ldx #$C3
        jsr set_addr
        jsr draw_str
        ; 地面:行 24 山,25 森林,26-29 田野
        lda #24
        sta tmp4
        lda #0
        sta tmp5
        jsr row_addr
        ldx #0
@hl:    txa
        and #$07
        cmp #2
        bne @hl_n
        lda #$6B
        bne @hl_p
@hl_n:  lda #$00
@hl_p:  sta $2007
        inx
        cpx #32
        bne @hl
        lda #25
        sta tmp4
        jsr row_addr
        lda #$6C
        ldx #32
@fr:    sta $2007
        dex
        bne @fr
        ldy #26
@gr_r:  sty tmp4
        jsr row_addr
        lda #$68
        ldx #32
@gr:    sta $2007
        dex
        bne @gr
        ldy tmp4
        iny
        cpy #30
        bne @gr_r
        ; 键位行(行 23)
        lda #<str_keys
        sta ptr_lo
        lda #>str_keys
        sta ptr_hi
        lda #$22
        ldx #$E0
        jsr set_addr
        jsr draw_str
        rts

; ---------------- 讲评画面 ----------------
draw_debrief:
        jsr clear_nts
        lda #$20
        ldx #$00
        jsr set_addr
        ldx #4
        ldy #0
        lda #$01
@f:     sta $2007
        iny
        bne @f
        dex
        bne @f
        lda #$23
        ldx #$C0
        jsr set_addr
        ldy #64
        lda #$00
@at:    sta $2007
        dey
        bne @at
        lda #<str_log
        sta ptr_lo
        lda #>str_log
        sta ptr_hi
        lda #$20
        ldx #$6B
        jsr set_addr
        jsr draw_str
        ; 六行成绩(行 6/8/10/12/14/16 列 8)
        ldx #0
@leg:   stx tmp0
        txa
        asl a
        clc
        adc #6
        sta tmp4
        lda #0
        sta tmp5
        jsr row_addr
        ; 列 2:重设地址
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #2
        tax
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta $2006
        stx $2006
        lda tmp0
        asl a
        asl a
        asl a
        tay
        ldx #0
@nm:    lda debrief_names,y
        sta $2007
        iny
        inx
        cpx #8
        bne @nm
        lda #' '
        sta $2007
        sta $2007
        ldx tmp0
        lda grades,x
        sta $2007
        ldx tmp0
        inx
        cpx #6
        bne @leg
        ; ---- 航迹回放图(右侧):跑道线 + 采样点 ----
        lda #<str_track
        sta ptr_lo
        lda #>str_track
        sta ptr_hi
        lda #$20
        ldx #$95
        jsr set_addr
        jsr draw_str
        ldx #7                  ; 跑道:col 26 行 7-10
@rwm:   stx tmp4
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #26
        tay
        txa
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta $2006
        sty $2006
        lda #$8E
        sta $2007
        ldx tmp4
        inx
        cpx #11
        bne @rwm
        ldx #0
@pt:    cpx trk_i
        bcs @pt_done
        stx tmp0
        lda trk_bx,x
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #17
        sta tmp2                ; 列 17-27
        sec
        lda #187
        sbc trk_by,x
        bcs @py_ok
        lda #0
@py_ok: lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #5
        sta tmp4                ; 行 5-16
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc tmp2
        tay
        lda tmp4
        lsr a
        lsr a
        lsr a
        clc
        adc #$20
        sta $2006
        sty $2006
        lda #'.'
        sta $2007
        ldx tmp0
        inx
        bne @pt
@pt_done:
        ; 接地:TOUCH ±fpm + OFFSET
        lda #<str_touch
        sta ptr_lo
        lda #>str_touch
        sta ptr_hi
        lda #$22
        ldx #$42
        jsr set_addr
        jsr draw_str
        lda ldg_fpm_lo
        sta num_lo
        lda ldg_fpm_hi
        sta num_hi
        jsr b2d16
        ldx #1
@fp:    lda dec_buf,x
        sta $2007
        inx
        cpx #5
        bne @fp
        lda #<str_fpm
        sta ptr_lo
        lda #>str_fpm
        sta ptr_hi
        jsr draw_str
        ; 分数
        lda #<str_score
        sta ptr_lo
        lda #>str_score
        sta ptr_hi
        lda #$22
        ldx #$82
        jsr set_addr
        jsr draw_str
        lda score_lo
        sta num_lo
        lda score_hi
        sta num_hi
        jsr b2d16
        ldx #0
@sc:    lda dec_buf,x
        sta $2007
        inx
        cpx #5
        bne @sc
        ; 评语
        lda crashed
        beq @r_by_score
        lda #<str_r_crash
        sta ptr_lo
        lda #>str_r_crash
        sta ptr_hi
        jmp @r_draw
@r_by_score:
        lda score_hi
        cmp #>5000
        bcc @r1
        bne @r0
        lda score_lo
        cmp #<5000
        bcc @r1
@r0:    lda #<str_r0
        sta ptr_lo
        lda #>str_r0
        sta ptr_hi
        bne @r_draw
@r1:    lda score_hi
        cmp #>3800
        bcc @r2
        bne @r1y
        lda score_lo
        cmp #<3800
        bcc @r2
@r1y:   lda #<str_r1
        sta ptr_lo
        lda #>str_r1
        sta ptr_hi
        bne @r_draw
@r2:    lda score_hi
        cmp #>2200
        bcc @r3
        bne @r2y
        lda score_lo
        cmp #<2200
        bcc @r3
@r2y:   lda #<str_r2
        sta ptr_lo
        lda #>str_r2
        sta ptr_hi
        bne @r_draw
@r3:    lda #<str_r3
        sta ptr_lo
        lda #>str_r3
        sta ptr_hi
@r_draw:
        lda #$22
        ldx #$C3
        jsr set_addr
        jsr draw_str
        ; 续飞提示(完好玩家落地 → 昼夜进阶;否则 PRESS START)
        lda crashed
        bne @h_press
        lda ai_on
        bne @h_press
        ldx night_lvl
        lda nexthint_lo,x
        sta ptr_lo
        lda nexthint_hi,x
        sta ptr_hi
        jmp @h_draw
@h_press:
        lda #<str_press
        sta ptr_lo
        lda #>str_press
        sta ptr_hi
@h_draw:
        lda #$23
        ldx #$25
        jsr set_addr
        jsr draw_str
        lda #<str_totitle
        sta ptr_lo
        lda #>str_totitle
        sta ptr_hi
        lda #$23
        ldx #$69
        jsr set_addr
        jsr draw_str
        rts

; ============================================================================
; 声音(v1 引擎,喇叭改为迎角驱动)
; ============================================================================
CH_OK    = 0
CH_WARN  = 4
CH_BLIP  = 8
CH_RADIO = 12

chime_start:
        sty chime_base
        lda #0
        sta chime_note
        lda #1
        sta chime_timer
        lda #0
        sta chime_ptr
        rts

sound_tick:
        lda game_state
        cmp #ST_TITLE
        bne @ingame
        jmp music_tick
@ingame:
        cmp #ST_GAME
        beq @game
        lda #$30
        sta $4000
        sta $400C
        jmp @chime
@game:  ldx eng_idx             ; 声调随真实转速(含惯性/风车效应)
        lda eng_per_lo,x
        clc
        adc frame
        and #$03
        adc eng_per_lo,x
        sta $4002
        lda eng_per_hi,x
        cmp eng_hi_last
        beq @nohi
        sta eng_hi_last
        sta $4003
@nohi:  lda paused
        beq @evol
        lda #$72
        bne @ev
@evol:  ldx eng_idx
        lda eng_vol,x
        ora #$70
@ev:    sta $4000
        ; 失速喇叭
        lda horn_on
        beq @horn_off
        lda #$B9
        sta $4004
        lda frame
        and #$08
        beq @h1
        lda #<186
        sta $4006
        lda #>186
        sta $4007
        jmp @noise
@h1:    lda #<210
        sta $4006
        lda #>210
        sta $4007
        jmp @noise
@horn_off:
@chime: lda horn_on
        bne @noise
        lda chime_ptr
        cmp #$FF
        beq @noise
        dec chime_timer
        bne @noise
        lda chime_base
        clc
        adc chime_note
        tax
        lda chime_tab,x
        beq @ch_end
        tax
        lda note_lo,x
        sta $4006
        lda note_hi,x
        sta $4007
        lda #$B7
        sta $4004
        lda #7
        sta chime_timer
        inc chime_note
        bne @noise
@ch_end:
        lda #$B0
        sta $4004
        lda #$FF
        sta chime_ptr
@noise: lda game_state
        cmp #ST_GAME
        bne @tri
        lda noise_burst
        beq @wind
        dec noise_burst
        lda noise_burst
        ora #$30
        sta $400C
        lda #$0C
        sta $400E
        bne @tri
@wind:  lda flap_mov
        beq @wnat
        lda #$33                ; 襟翼电机运转:轻微电流嗡声
        sta $400C
        lda #$08
        sta $400E
        bne @tri
@wnat:  lda vint
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #6
        bcc @wv
        lda #6
@wv:    ldx on_ground
        beq @wr
        clc
        adc #1
@wr:    ora #$30
        sta $400C
        lda #$05
        sta $400E
@tri:   lda tri_timer
        beq @rts
        dec tri_timer
        lda #$FF
        sta $4008
        lda #12
        sec
        sbc tri_timer
        tax
        lda thump_per,x
        sta $400A
        lda #$09
        sta $400B
        lda tri_timer
        bne @rts
        lda #$80
        sta $4008
        lda #$08
        sta $400B
@rts:   rts

music_tick:
        dec mus_t1
        bne @m2
        ldx mus_i1
        lda mus_sq1,x
        cmp #$FF
        bne @n1
        ldx #0
        lda mus_sq1
@n1:    sta tmp0
        lda mus_sq1+1,x
        sta mus_t1
        inx
        inx
        stx mus_i1
        ldx tmp0
        beq @r1
        lda note_lo,x
        sta $4002
        lda note_hi,x
        sta $4003
        lda #$B6
        sta $4000
        bne @m2
@r1:    lda #$B0
        sta $4000
@m2:    dec mus_t2
        bne @m3
        ldx mus_i2
        lda mus_sq2,x
        cmp #$FF
        bne @n2
        ldx #0
        lda mus_sq2
@n2:    sta tmp0
        lda mus_sq2+1,x
        sta mus_t2
        inx
        inx
        stx mus_i2
        ldx tmp0
        beq @r2
        lda note_lo,x
        sta $4006
        lda note_hi,x
        sta $4007
        lda #$B4
        sta $4004
        bne @m3
@r2:    lda #$B0
        sta $4004
@m3:    dec mus_t3
        bne @rts
        ldx mus_i3
        lda mus_tri,x
        cmp #$FF
        bne @n3
        ldx #0
        lda mus_tri
@n3:    sta tmp0
        lda mus_tri+1,x
        sta mus_t3
        inx
        inx
        stx mus_i3
        ldx tmp0
        beq @r3
        lda #$FF
        sta $4008
        lda note_lo,x
        sta $400A
        lda note_hi,x
        ora #$08
        sta $400B
        rts
@r3:    lda #$80
        sta $4008
        lda #$08
        sta $400B
@rts:   rts

; ============================================================================
.segment "RODATA"

.include "aero_tables.inc"

; 调色板三套:白天/黄昏/夜航(圈数进阶)。布局:
;   BG0 面板/字  BG1 跑道带(藏青体/白标线/绿垫) BG2 天空物+姿态仪面  BG3 地面双绿(闪烁行进)
palettes:
pal_day:
        .byte $22,$0F,$2D,$30
        .byte $22,$02,$19,$30
        .byte $22,$02,$11,$30
        .byte $22,$02,$19,$1A
        .byte $22,$0F,$30,$16
        .byte $22,$0F,$30,$27
        .byte $22,$0F,$2D,$10
        .byte $22,$0F,$30,$27
pal_dusk:
        .byte $26,$0F,$2D,$30
        .byte $26,$03,$08,$30
        .byte $26,$03,$14,$36
        .byte $26,$03,$08,$18
        .byte $26,$0F,$30,$16
        .byte $26,$0F,$30,$27
        .byte $26,$0F,$2D,$10
        .byte $26,$0F,$30,$27
pal_night:
        .byte $0F,$0F,$06,$16
        .byte $0F,$00,$08,$30
        .byte $0F,$00,$04,$2D
        .byte $0F,$00,$08,$09
        .byte $0F,$0F,$30,$16
        .byte $0F,$0F,$30,$27
        .byte $0F,$0F,$2D,$10
        .byte $0F,$0F,$30,$27
palset_lo: .byte <pal_day,<pal_dusk,<pal_night
palset_hi: .byte >pal_day,>pal_dusk,>pal_night

; P-factor(左偏,8.8 bdeg/帧,按油门;>85kt 减半,>100kt 无)
pf_tab:    .byte 0,0,0,0,1,1,1,2,2

; 定常风:来自 300°/8kt(36 号跑道左前侧风),阵风三档 ±25%
; 分量(朝 120°):东 +6.9kt、北 -4.0kt;单位 8.8 ft/2 每帧(kt×3.6)
wind_e_tab: .byte 19,25,31
wind_n_tab: .byte <(-11),<(-14),<(-18)

; 定距桨:目标转速 = base[thr] + V×slp[thr]>>3;怠速高速风车效应
rpm_base_lo: .byte <700,<900,<1100,<1300,<1500,<1700,<1900,<2100,<2300
rpm_base_hi: .byte >700,>900,>1100,>1300,>1500,>1700,>1900,>2100,>2300
rpm_slp:     .byte 16,6,8,10,12,15,18,21,24

; 指针方向表(枢轴像素 (0,7);翻转覆盖 16 向)
ndl_tile: .byte $04,$05,$06,$07,$08,$07,$06,$05,$04,$05,$06,$07,$08,$07,$06,$05
ndl_attr: .byte $00,$00,$00,$00,$80,$80,$80,$80,$C0,$C0,$C0,$C0,$40,$40,$40,$40
ndl_dx:   .byte 0,0,0,0,0,0,0,0
          .byte <(-7),<(-7),<(-7),<(-7),<(-7),<(-7),<(-7),<(-7)
ndl_dy:   .byte <(-7),<(-7),<(-7),<(-7),0,0,0,0,0,0,0,0,<(-7),<(-7),<(-7),<(-7)

; AI 地平杆瓦片(按 bank_idx;15° 档用 10/20 共用近似)
ai_bar_l: .byte $09,$0A,$0A,$0C
ai_bar_r: .byte $09,$0B,$0B,$0D

; PAPI 两精灵瓦片(左灯对/右灯对),索引=红灯数
papi_spr:
        .byte $48,$48           ; 0 红:全白(太高)
        .byte $48,$49           ; 1
        .byte $48,$4B           ; 2 两白两红(正好)
        .byte $49,$4B           ; 3
        .byte $4B,$4B           ; 4 全红(太低)

; 转弯箭头 OAM 模板(y,tile,attr,x)×4:风挡左上闪烁
arrow_y:
        .byte 40,$44,$01,96
        .byte 40,$45,$01,104
        .byte 48,$46,$01,96
        .byte 48,$47,$01,104

; 航段数据
leg_tgt_ias: .byte 55,74,74,90,73,65,60,0,0
leg_tol:     .byte 99,8,30,8,8,6,99,99,99
leg_mode:    .byte 3,0,4,1,2,2,3,3,3
leg_msg:     .byte M_ROLL,M_UPWIND,M_XWIND,M_DWNWD,M_BASE,M_FINAL,M_FLARE,M_ROLLOUT,M_NONE

tgt_ias_str: .byte "055","074","074","090","073","065","060","---","---"

leg_name_lo:
        .byte <ln0,<ln1,<ln2,<ln3,<ln4,<ln5,<ln6,<ln7,<ln8
leg_name_hi:
        .byte >ln0,>ln1,>ln2,>ln3,>ln4,>ln5,>ln6,>ln7,>ln8
ln0:    .byte "ROLL    "
ln1:    .byte "UPWIND  "
ln2:    .byte "XWIND   "
ln3:    .byte "DOWNWIND"
ln4:    .byte "BASE    "
ln5:    .byte "FINAL   "
ln6:    .byte "FLARE   "
ln7:    .byte "ROLLOUT "
ln8:    .byte "DONE    "

debrief_names:
        .byte "UPWIND  "
        .byte "XWIND   "
        .byte "DOWNWIND"
        .byte "BASE    "
        .byte "FINAL   "
        .byte "LANDING "

; 接地评分:fpm 档(<150 A <250 B <400 C <600 D)与分值
ldg_thr_lo: .byte <150,<250,<400,<600
ldg_thr_hi: .byte >150,>250,>400,>600
ldg_score:  .word 2000,1200,700,300

; 转弯目标航向(bdeg):一转 270°,二转 180°,三转 90°,四转 0°
turn_tgt:   .byte 192,128,64,0
; 各航段标称航向(直线段航向保持用)
leg_hdg:    .byte 0,0,192,128,64,0,0,0,0

; AI 表:油门/襟翼/前馈姿态(半度)
;                ROLL UPW XW  DWN BAS FIN FLR RO  DONE
ai_thr_tab:   .byte 8,  8,  8,  5,  3, $FF, 0,  0,  0
ai_flap_tab:  .byte 0,  0,  0,  0,  2,  3,  3,  3,  3
ai_thff_tab:  .byte 0,  19, 19, 2,  <(-6), <(-8), 2, 2, 0

; 跑道显示档距离(ft/2):≤300/500/800/1300/2200/4000
bucket_lo:  .byte <300,<500,<800,<1300,<2200,<4000
bucket_hi:  .byte >300,>500,>800,>1300,>2200,>4000

; 跑道贴块(行数;每行:宽,瓦片…)
stamp_ptr:  .word stamp0,stamp1,stamp2,stamp3,stamp4
stamp0: .byte 3
        .byte 4,$75,$74,$74,$76
        .byte 6,$70,$72,$73,$73,$72,$71
        .byte 8,$70,$72,$72,$73,$73,$72,$72,$71
stamp1: .byte 2
        .byte 3,$75,$74,$76
        .byte 5,$70,$72,$73,$72,$71
stamp2: .byte 2
        .byte 2,$75,$76
        .byte 4,$70,$73,$73,$71
stamp3: .byte 1
        .byte 3,$75,$74,$76
stamp4: .byte 1
        .byte 2,$75,$76

; HUD 跳表
hud_jmp:
        .word hud_f0,hud_f1,hud_f2,hud_f3,hud_f4,hud_f5,hud_f6,hud_f7

rpm_str: .byte "0700","0950","1200","1450","1700","1950","2200","2450","2700"
flap_str:.byte "00","10","20","30"

; 面板标签
s_ias:  .byte "IAS",0
s_alt:  .byte "ALT",0
s_vs:   .byte "VS",0
s_hdg:  .byte "HDG",0
s_rpm:  .byte "RPM",0
s_flp:  .byte "FLP    PIT",0
s_row19:.byte "LEG          TGT     G",0
s_sc:   .byte "SC",0
s_hint: .byte "A/B PWR U/D PITCH L/R BANK",0

; 消息
msg_lo:
        .byte 0
        .byte <m1,<m2,<m3,<m4,<m5,<m6,<m7,<m8,<m9
        .byte <m10,<m11,<m12,<m13,<m14,<m15,<m16,<m17,<m18
        .byte <m19,<m20,<m21,<m22
        .byte <m23,<m24,<m25,<m26,<m27,<m28,<m29,<m30
        .byte <m31,<m32,<m33,<m34,<m35,<m36
msg_hi:
        .byte 0
        .byte >m1,>m2,>m3,>m4,>m5,>m6,>m7,>m8,>m9
        .byte >m10,>m11,>m12,>m13,>m14,>m15,>m16,>m17,>m18
        .byte >m19,>m20,>m21,>m22
        .byte >m23,>m24,>m25,>m26,>m27,>m28,>m29,>m30
        .byte >m31,>m32,>m33,>m34,>m35,>m36
m1:     .byte "FULL POWER : ROTATE AT 55",0
m2:     .byte "CLIMB AT VY 74",0
m3:     .byte "CROSSWIND : CLIMB TO 1000",0
m4:     .byte "DOWNWIND : LEVEL 1000 , 90 KT",0
m5:     .byte "ABEAM : POWER 3 , FLAPS 10",0
m6:     .byte "BASE : FLAPS 20 , 73 KT",0
m7:     .byte "FINAL : FLAPS 30 , 65 KT",0
m8:     .byte "OVER THE FENCE : EASE BACK",0
m9:     .byte "BRAKE GENTLY < HOLD B >",0
m10:    .byte "TURN LEFT ! < HOLD LEFT >",0
m11:    .byte "INSTRUCTOR : MY CONTROLS",0
m12:    .byte "STALL ! NOSE DOWN !",0
m13:    .byte "GO AROUND : CLIMB STRAIGHT",0
m14:    .byte "HARD LANDING ...",0
m15:    .byte "OFF THE RUNWAY ...",0
m16:    .byte "GREASED IT ! WELL DONE !",0
m17:    .byte "AUTOPILOT DEMO : PRESS START",0
m18:    .byte "PAUSED",0
m19:    .byte "FLAPS UP",0
m20:    .byte "FLAPS 10",0
m21:    .byte "FLAPS 20",0
m22:    .byte "FLAPS 30",0
m23:    .byte "RIGHT RUDDER !",0
m24:    .byte "CRAB INTO THE WIND !",0
m25:    .byte "BOUNCED ! EASE IT ON",0
m26:    .byte "PORPOISE ! HOLD IT OFF ...",0
m27:    .byte "NOSE WHEEL FIRST !",0
m28:    .byte "SIDE LOAD ! TOUCH SOONER",0
m29:    .byte "FLAPS OVERSPEED ! < 85 KT",0
m30:    .byte "CARB HEAT ON",0
m31:    .byte "TWR : REPORT DOWNWIND",0
m32:    .byte "TWR : CLEARED TO LAND RWY 36",0
m33:    .byte "TWR : GO AROUND ! TRAFFIC !",0
m34:    .byte "GOOD GO AROUND ! + 300",0
m35:    .byte "WING DROP ! UNSTALL !",0
m36:    .byte "VEERED OFF THE RUNWAY !",0

str_press: .byte "PRESS START",0
str_sub:   .byte "TRAFFIC PATTERN TRAINER",0
str_poh:   .byte "POH NUMBERS : 55 74 90 65",0
str_demo:  .byte "OR WAIT FOR AUTOPILOT DEMO",0
str_keys:  .byte "REAL AERO : COCKPIT VIEW",0
str_log:   .byte "FLIGHT LOG",0
str_touch: .byte "TOUCH ",0
str_fpm:   .byte " FPM",0
str_score: .byte "SCORE ",0
str_r0:    .byte "RATING : CHECKRIDE PASSED !",0
str_r1:    .byte "RATING : READY FOR SOLO",0
str_r2:    .byte "RATING : STUDENT PILOT",0
str_r3:    .byte "RATING : MORE PATTERN WORK",0
str_r_crash: .byte "RATING : SEE THE MECHANIC ...",0
str_next1: .byte "START : DUSK CIRCUIT",0
str_next2: .byte "START : NIGHT CIRCUIT",0
str_next3: .byte "START : ANOTHER NIGHT ROUND",0
nexthint_lo: .byte <str_next1,<str_next2,<str_next3
nexthint_hi: .byte >str_next1,>str_next2,>str_next3
str_totitle: .byte "SELECT : TITLE",0
str_track: .byte "TRACK",0
s_thr:   .byte "THR",0

eng_per_lo: .byte <2047,<2047,<1864,<1543,<1316,<1147,<1017,<913,<828
eng_per_hi: .byte >2047,>2047,>1864,>1543,>1316,>1147,>1017,>913,>828
eng_vol:    .byte 3,4,5,6,7,8,9,10,11

thump_per:  .byte $60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0,$FF,$FF,$FF

note_lo: .byte 0,<852,<639,<568,<426,<338,<319,<284,<253,<225,<213,<189,<168,<142
note_hi: .byte 0,>852,>639,>568,>426,>338,>319,>284,>253,>225,>213,>189,>168,>142

chime_tab:
        .byte 10,12,13,0
        .byte 7,5,7,0
        .byte 12,0,0,0
        .byte 3,3,0,0           ; CH_RADIO:低音双响(配噪声沙沙)

mus_sq1:
        .byte 5,12, 7,12, 10,12, 7,12,  8,12, 10,12, 12,12, 10,12
        .byte 11,12, 9,12, 7,12,  9,12, 10,12, 7,12,  5,12,  7,12
        .byte $FF
mus_sq2:
        .byte 0,12, 4,12, 0,12, 5,12,  0,12, 6,12, 0,12, 8,12
        .byte 0,12, 7,12, 0,12, 7,12,  0,12, 5,12, 0,12, 4,12
        .byte $FF
mus_tri:
        .byte 1,24, 1,24, 2,24, 2,24,  3,24, 3,24, 1,24, 1,24
        .byte $FF

pow_lo: .byte <10000,<1000,<100,<10
pow_hi: .byte >10000,>1000,>100,>10

.segment "VECTORS"
        .addr nmi
        .addr reset
        .addr irq

.segment "CHR"
        .incbin "build/chr.bin"
