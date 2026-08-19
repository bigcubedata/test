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

.segment "BSS"
ppu_buf:     .res 208
grades:      .res 6
dec_buf:     .res 5
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
@set:   ldx #14
@d:     dex
        bne @d
        lda #$01
        sta $2006
        lda #$60
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
        ; 喇叭(空中且 α_req ≥ horn)
        ldx #0
        lda on_ground
        bne @hs
        lda a_req
        bmi @hs
        ldy flaps
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

        ; ---- 航向(转弯率 = g·tanφ/V) ----
        lda bank_idx
        beq @position
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
        bcc @position
        inc psi_hi
        jmp @position
@turn_l:
        sec
        lda psi_lo
        sbc mul_hi
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
@on:    lda #LEG_ROLLOUT
        sta leg
        lda #2
        sta theta
        lda #10
        sta noise_burst
        lda #12
        sta tri_timer
        jsr grade_landing
        jsr on_leg_enter
        rts
@off:   lda #1
        sta crashed
        lda #150
        sta done_timer
        lda #'E'
        sta grades+5
        lda #1
        sta grades_dirty
        lda #M_OFFRWY
        jsr msg_set
        lda #12
        sta noise_burst
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

; 接地评分:真实 fpm 档(<150 A <250 B <400 C <600 D)+ 中线奖励
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
        ; 硬着陆
        lda #'E'
        sta grades+5
        lda #1
        sta grades_dirty
        lda #M_HARD
        jsr msg_set
        lda #1
        sta crashed
        lda #150
        sta done_timer
        rts
@got:   txa
        clc
        adc #'A'
        sta grades+5
        lda #1
        sta grades_dirty
        txa
        asl a
        tax
        lda ldg_score,x
        sta tmp0
        lda ldg_score+1,x
        sta tmp1
        jsr score_add16
        lda ldg_x
        cmp #9
        bcs @m
        lda #<300
        sta tmp0
        lda #>300
        sta tmp1
        jsr score_add16
@m:     lda ldg_fpm_hi
        bne @m2
        lda ldg_fpm_lo
        cmp #150
        bcs @m2
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
        sta ai_on
        jmp enter_game

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
        sta score_lo
        sta score_hi
        sta done_timer
        sta a_hold
        sta b_hold
        sta ai_timer
        sta ai_takeover
        sta eng_hi_last
        sta hz_task
        sta rw_task
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
        jmp enter_debrief
@alive: lda leg
        cmp #LEG_DONE
        bne @notdone
        dec done_timer
        bne @rts0
        jmp enter_debrief
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
        jmp enter_title
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
        lda flaps
        clc
        adc #1
        and #3
        sta flaps
        clc
        adc #M_FLAP0
        jsr msg_set
        ldy #CH_BLIP
        jsr chime_start
@roll:  ; LEFT/RIGHT 压坡度(玩家;教官代打时被 ai_turn_ctl 覆盖)
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
        jsr roll_center
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
        cmp flaps
        beq @flap_ok
        bcc @flap_dn
        inc flaps
        bne @flap_ok
@flap_dn:
        dec flaps
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
        bcs @rts
        lda theta
        cmp #<(-14)
        beq @rts
        dec theta
        rts
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
        lda vint
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
        sta tmp2                ; ψ_cmd = -clamp(px/8, ±10)
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
        ldx leg
        lda leg_msg,x
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
; 慢速层(每 8 帧):方位/距离/跑道显示档/PAPI
; ============================================================================
slow_tick:
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
        ; 跑道贴块需要重画?(档/列/地平线行变化)
        lda rw_task
        bne @rts
        lda rw_bucket
        cmp rw_drawn_b
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
        ; pan = ψ·2 - 128(9 位)
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
        lda #4
        sta hz_task
        ; 地平线变行会盖掉跑道贴块 → 待重画
        lda #$FF
        sta rw_drawn_b
@hz_go: lda hz_task
        beq @rw_go
        lda buf_w
        cmp #120
        bcs @rts                ; 缓冲紧张,下帧再画
        ; 每帧重画一行(行 6..9):row = 10 - task
        sec
        lda #10
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

; 发射地平线行 A=row(6..9):两个 NT 各 32 字节
hz_emit_row:
        sta tmp4                ; row
        ; 决定该行瓦片:row < hl_row → $00;== → $60+sub;> → $68
        lda hl_cur
        lsr a
        lsr a
        lsr a
        sta tmp5                ; hl_row
        lda tmp4
        cmp tmp5
        bcc @sky
        beq @line
        lda #$68
        bne @have
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

; 擦除已画跑道区(11 列 × 3 行,地面色)
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
        bcs @done
        lda rw_drawn_c
        sec
        sbc #5
        and #$3F
        sta tmp2
        lda #11
        sta tmp5
        lda #$68
        sta tmp6
        jsr emit_run
        inc tmp4
        ldx tmp3
        dex
        bne @row
@done:  lda #$FF
        sta rw_drawn_b
@rts:   rts

; 画跑道贴块(rw_bucket 0..4 → 表;5 → 仅精灵)
rw_draw_stamp:
        lda rw_bucket
        cmp #5
        bcs @sprite_only
        ; 记录
        sta rw_drawn_b
        lda rw_col
        sta rw_drawn_c
        lda hl_cur
        lsr a
        lsr a
        lsr a
        clc
        adc #1
        sta rw_drawn_r
        sta tmp4                ; 当前行
        ; 表指针
        lda rw_bucket
        asl a
        tax
        lda stamp_ptr,x
        sta ptr_lo
        lda stamp_ptr+1,x
        sta ptr_hi
        ldy #0
        lda (ptr_lo),y
        sta tmp3                ; 行数
        iny
@row:   lda tmp4
        cmp #11
        bcs @done
        lda (ptr_lo),y
        iny
        sta tmp5                ; 宽
        ; 起始列 = rw_col - 宽/2
        lsr a
        sta tmp2
        lda rw_col
        sec
        sbc tmp2
        and #$3F
        sta tmp2
        ; 数据在 (ptr),y…先收集到发射器:emit_run_tiles
        jsr emit_run_tiles
        inc tmp4
        dec tmp3
        bne @row
@done:  rts
@sprite_only:
        lda #5
        sta rw_drawn_b
        lda rw_col
        sta rw_drawn_c
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

; 表数据行段:tmp2=起始列 tmp4=行 tmp5=宽,数据在 (ptr),y(推进 y)
emit_run_tiles:
        sty tmp1                ; 保存数据游标
        jsr run_setup
        ldy tmp1
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
@c1:    lda (ptr_lo),y
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
@c2:    lda (ptr_lo),y
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

hud_f4: ; RPM(4)@ row17 col18(查表)
        lda thr
        asl a
        asl a
        tax
        lda #$22
        stx tmp3
        ldx #$32
        ldy #4
        jsr buf_open
        ldx tmp3
        lda rpm_str,x
        sta ppu_buf,y
        iny
        lda rpm_str+1,x
        sta ppu_buf,y
        iny
        lda rpm_str+2,x
        sta ppu_buf,y
        iny
        lda rpm_str+3,x
        sta ppu_buf,y
        iny
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
        rts
@arr_off:
        lda #$F8
        sta oam+56
        sta oam+60
        sta oam+64
        sta oam+68
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
        and #BTN_STA
        beq @rts
        jmp enter_title
@rts:   rts

; ============================================================================
; 画面绘制(渲染关时直写)
; ============================================================================
load_palettes:
        lda #$3F
        sta $2006
        lda #$00
        sta $2006
        ldx #0
@p:     lda palettes,x
        sta $2007
        inx
        cpx #32
        bne @p
        rts

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
        ; 属性:行 0-7 pal2($AA),行 8-11 pal1($55),行 12+ pal0($00)
        ldx #0
        jsr @attr_one
        ldx #4
        jsr @attr_one
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
        ldy #16
        lda #$55                ; 行 4-11:山影/地面 pal1(地平线全程绿)
@a1:    sta $2007
        dey
        bne @a1
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
        ldx #0
@g9:    txa
        and #$01
        beq @g9a
        lda #$69
        bne @g9p
@g9a:   lda #$68
@g9p:   sta $2007
        inx
        cpx #32
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
        ; 六联表圈:两行三列
        ldx #1
        ldy #13
        jsr draw_bezel
        ldx #5
        ldy #13
        jsr draw_bezel
        ldx #9
        ldy #13
        jsr draw_bezel
        ldx #1
        ldy #16
        jsr draw_bezel
        ldx #5
        ldy #16
        jsr draw_bezel
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

; 表圈 3×3:X=列 Y=起始行(渲染关直写)
draw_bezel:
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
        ; tile = $80 + r·3 起连续 3 个
        lda tmp7
        asl a
        clc
        adc tmp7
        clc
        adc #$80
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
        ldx #0
@gr:    txa
        eor tmp4
        and #$01
        beq @gr_a
        lda #$69
        bne @gr_p
@gr_a:  lda #$68
@gr_p:  sta $2007
        inx
        cpx #32
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
        ; 列 8:重设地址
        lda tmp4
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #8
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
        ; 接地:TOUCH ±fpm + OFFSET
        lda #<str_touch
        sta ptr_lo
        lda #>str_touch
        sta ptr_hi
        lda #$22
        ldx #$48
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
        ldx #$88
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
        lda #<str_press
        sta ptr_lo
        lda #>str_press
        sta ptr_hi
        lda #$23
        ldx #$2A
        jsr set_addr
        jsr draw_str
        rts

; ============================================================================
; 声音(v1 引擎,喇叭改为迎角驱动)
; ============================================================================
CH_OK   = 0
CH_WARN = 4
CH_BLIP = 8

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
@game:  ldx thr
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
@evol:  ldx thr
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
@wind:  lda vint
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

palettes:
        ; BG:0 面板/字  1 地面(绿/藏青/白) 2 天空物  3 备用
        .byte $22,$0F,$2D,$30
        .byte $22,$02,$19,$30
        .byte $22,$02,$11,$30
        .byte $22,$0F,$16,$27
        ; SPR:0 指针/PAPI/灯(白+红) 1 箭头橙 2 灰(千位针/地图点) 3 备用
        .byte $22,$0F,$30,$16
        .byte $22,$0F,$30,$27
        .byte $22,$0F,$2D,$10
        .byte $22,$0F,$30,$27

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
msg_hi:
        .byte 0
        .byte >m1,>m2,>m3,>m4,>m5,>m6,>m7,>m8,>m9
        .byte >m10,>m11,>m12,>m13,>m14,>m15,>m16,>m17,>m18
        .byte >m19,>m20,>m21,>m22
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
