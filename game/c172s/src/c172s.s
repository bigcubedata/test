; ============================================================================
; 《C172S 五边飞行》—— NES 原生风格的塞斯纳 172S 起落航线教练游戏
; NROM(mapper 0),32KB PRG + 8KB CHR,竖直镜像(横向卷轴)
;
; 理念承袭 C172S Simulator(claude/goal-setting-sjhs9v 分支):
;   POH 校准的目标速度(旋转 55 / Vy 74 / 三边 90 / 五边 65 KIAS),
;   起落航线逐段目标 + 教官评分(PatternPilot),
;   标题画面自动驾驶演示即"自动飞行教官"。
;
; 技术:SMB 式全 NMI 主循环 + sprite-0 分屏(顶部 6 行仪表板)+
;       列流式横向卷轴 + 表驱动飞行模型 + APU 引擎/失速喇叭/接地音效。
; ============================================================================

; ---------------- iNES 头 ----------------
.segment "HEADER"
        .byte "NES", $1A
        .byte 2                 ; 2×16KB PRG
        .byte 1                 ; 1×8KB CHR
        .byte $01               ; 竖直镜像,mapper 0
        .byte $00
        .res 8, $00

; ---------------- 常量 ----------------

PPUCTRL_BASE   = $88            ; NMI 开,精灵 $1000,背景 $0000,inc 1,NT0

ST_TITLE       = 0
ST_GAME        = 1
ST_DEBRIEF     = 2

; 航段
LEG_ROLL       = 0
LEG_UPWIND     = 1
LEG_XWIND      = 2
LEG_DWNWD      = 3
LEG_BASE       = 4
LEG_FINAL      = 5
LEG_FLARE      = 6
LEG_ROLLOUT    = 7
LEG_DONE       = 8

; 世界几何(像素,总长 9216 = 512 的倍数,保证 NT 相位连续)
MAP_X          = 9216
RWY_END        = 576            ; 跑道 0..575
XW_AT          = 2076
DW_AT          = 3276
ABEAM_AT       = 4776
BASE_AT        = 6276
FIN_AT         = 7476
THRESH_AT      = 8976           ; 着陆入口
MAP_COLS       = 1152

PLANE_SX       = 64             ; 飞机屏幕 X
GROUND_PY      = 192            ; 地面时飞机顶部 Y(轮子贴 207)

; 手柄位
BTN_A          = $01
BTN_B          = $02
BTN_SEL        = $04
BTN_STA        = $08
BTN_UP         = $10
BTN_DN         = $20
BTN_LT         = $40
BTN_RT         = $80

; 消息 id
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
M_OVERRUN   = 14
M_OFFRWY    = 15
M_HARD      = 16
M_NICE      = 17
M_DEMO      = 18
M_PAUSED    = 19
M_FLAP0     = 20
M_FLAP1     = 21
M_FLAP2     = 22
M_FLAP3     = 23

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
ptr_lo:      .res 1
ptr_hi:      .res 1
mul_lo:      .res 1
mul_hi:      .res 1
num_lo:      .res 1
num_hi:      .res 1

; 相机 / 世界(16.8 定点)
wx_fr:       .res 1
wx_lo:       .res 1
wx_hi:       .res 1
lastcol_lo:  .res 1
lastcol_hi:  .res 1
px_lo:       .res 1             ; 飞机世界 X(整数像素,mod MAP_X)
px_hi:       .res 1
wcol_lo:     .res 1             ; build_col 输入:世界列(mod 1152)
wcol_hi:     .res 1
scol_lo:     .res 1             ; 屏幕列(未取模,用于 NT 寻址)
scol_hi:     .res 1
lap:         .res 1

; 飞行状态
thr:         .res 1             ; 0..8
flaps:       .res 1             ; 0..3(0/10/20/30)
pitch_b:     .res 1             ; 0..4(偏置,2=平飞)
on_ground:   .res 1
stalled:     .res 1
paused:      .res 1
ias_fr:      .res 1
ias_hi:      .res 1             ; 节(整数部)
tgt_ias:     .res 1
vs_lo:       .res 1             ; 8.8 英尺/帧,有符号
vs_hi:       .res 1
alt_fr:      .res 1
alt_lo:      .res 1
alt_hi:      .res 1             ; 英尺 16 位
plane_py:    .res 1
pose:        .res 1
bank_timer:  .res 1
crashed:     .res 1

; 航段 / 评分
leg:         .res 1
next_turn:   .res 1             ; 0..3,4=完
turn_win:    .res 1             ; 转弯窗口开启
abeam_done:  .res 1
leg_good:    .res 1
leg_max:     .res 1
score_lo:    .res 1
score_hi:    .res 1
papi:        .res 1             ; 红灯数 0..4
ldg_raw:     .res 1             ; 接地下沉率(8.8 原始值绝对值)
msg_id:      .res 1
msg_timer:   .res 1
hud_leg_dirty: .res 1
grades_dirty:  .res 1
smoke_timer: .res 1
done_timer:  .res 1

; AI(演示 / 教官)
ai_on:       .res 1
ai_timer:    .res 1

; 标题
tt_lo:       .res 1
tt_hi:       .res 1
tplane_fr:   .res 1
tplane_x:    .res 1

; 声音
eng_hi_last: .res 1
horn_on:     .res 1
chime_ptr:   .res 1             ; 音符序内索引,$FF=停
chime_note:  .res 1
chime_timer: .res 1
chime_base:  .res 1             ; 序表偏移
tri_timer:   .res 1
noise_burst: .res 1
mus_i1:      .res 1
mus_t1:      .res 1
mus_i2:      .res 1
mus_t2:      .res 1
mus_i3:      .res 1
mus_t3:      .res 1

; ---------------- BSS ----------------
.segment "BSS"

ppu_buf:     .res 160           ; 缓冲写:[hi][lo][ctrl:len|$80=inc32][data…] $FF 结束
col_tiles:   .res 24            ; 一列 24 个瓦片(行 6..29)
grades:      .res 6             ; ASCII:五段 + 着陆
dec_buf:     .res 5             ; bin2dec 输出
oam := $0200

; ============================================================================
.segment "CODE"

reset:
        sei
        cld
        ldx #$40
        stx $4017               ; 帧计数器 IRQ 关
        ldx #$FF
        txs
        inx
        stx $2000               ; NMI 关
        stx $2001               ; 渲染关
        stx $4010
        bit $2002
@vbl1:  bit $2002
        bpl @vbl1
        ; 清 RAM
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
        lda #$F8                ; OAM 移出屏
@clro:  sta $0200,x
        inx
        bne @clro
        lda #$FF
        sta ppu_buf             ; 缓冲终止符,防 NMI 早到
@vbl2:  bit $2002
        bpl @vbl2

        ; APU 初始化
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
        sta $4003               ; 装入长度(halt 位保持)
        sta $4007
        sta $400F

        jsr enter_title

        lda #PPUCTRL_BASE
        sta $2000               ; 开 NMI
forever:
        jmp forever

irq:    rti

; ============================================================================
; NMI:vblank 上载 → 面板滚动归零 → sprite-0 分屏 → 帧逻辑(SMB 式)
; ============================================================================
nmi:
        pha
        txa
        pha
        tya
        pha
        lda nmi_busy
        beq @go
        pla                     ; 上一帧逻辑超时:跳帧
        tay
        pla
        tax
        pla
        rti
@go:    inc nmi_busy
        bit $2002               ; 复位 w
        lda #$00
        sta $2003
        lda #$02
        sta $4014               ; OAM DMA
        jsr flush_buf
        lda #PPUCTRL_BASE
        sta $2000
        lda #0
        sta $2005
        sta $2005               ; 面板区 (0,0)
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

; ---------------- sprite-0 分屏:等命中后写世界滚动 ----------------
do_split:
        ldx #0
        ldy #24                 ; 超时保护
@wclr:  bit $2002
        bvc @hit0               ; S0 已清
        dex
        bne @wclr
        dey
        bne @wclr
        rts                     ; 超时(渲染未开等)
@hit0:  ldx #0
        ldy #40
@wset:  bit $2002
        bvs @set                ; S0 命中
        dex
        bne @wset
        dey
        bne @wset
        rts
@set:   lda wx_hi
        and #$01
        ora #PPUCTRL_BASE
        sta $2000               ; NT X 位
        lda wx_lo
        sta $2005               ; 单写:粗/细 X 下条扫描线生效
        rts

; ---------------- 缓冲上载 ----------------
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
        beq @done               ; 0 长度视为损坏,终止
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

; ---------------- 手柄 ----------------
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
        ror pad                 ; 首位(A)最终落在 bit0
        dex
        bne @b
        lda pad_prev
        eor #$FF
        and pad
        sta pad_new
        rts

; ============================================================================
; 标题画面
; ============================================================================
enter_title:
        lda #0
        sta $2000
        sta $2001
        bit $2002               ; 复位 w 锁存(可能刚做过分屏 $2005 单写)
        lda #ST_TITLE
        sta game_state
        jsr load_palettes
        jsr draw_title
        lda #0
        sta tt_lo
        sta tt_hi
        sta tplane_fr
        lda #40
        sta tplane_x
        ; 音乐复位
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
        lda #$1E
        sta $2001
        lda #PPUCTRL_BASE
        sta $2000               ; 恢复 NMI(状态切换发生在 NMI 内)
        rts

tick_title:
        ; START → 玩家开局;超时 → 自动驾驶演示
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
        cmp #3                  ; ~13 秒
        bcc @blink
        lda #1
        jmp start_game
@blink: ; PRESS START 闪烁
        lda tt_lo
        and #$1F
        bne @plane
        ldy buf_w
        lda #$22
        sta ppu_buf,y
        iny
        lda #$8A                ; 行 20 列 10
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
        jmp @fin
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
@plane: ; 地面滑行的飞机
        lda tplane_fr
        clc
        adc #160                ; 0.625 px/帧
        sta tplane_fr
        bcc @nx
        inc tplane_x
@nx:    lda #GROUND_PY
        sta plane_py
        lda #0
        sta pose
        lda tplane_x
        jsr draw_plane_at
        rts

; A=1 → 演示(自动驾驶),0 → 玩家
start_game:
        sta ai_on
        jmp enter_game

; ============================================================================
; 进入游戏:重画游戏画面 + 状态复位
; ============================================================================
enter_game:
        lda #0
        sta $2000
        sta $2001
        bit $2002               ; 复位 w 锁存
        lda #ST_GAME
        sta game_state
        jsr load_palettes
        jsr draw_game_static

        ; 状态清零
        lda #0
        sta wx_fr
        sta wx_lo
        sta wx_hi
        sta lastcol_lo
        sta lastcol_hi
        sta lap
        sta flaps
        sta thr
        sta ias_fr
        sta ias_hi
        sta vs_lo
        sta vs_hi
        sta alt_fr
        sta alt_lo
        sta alt_hi
        sta stalled
        sta paused
        sta crashed
        sta bank_timer
        sta next_turn
        sta turn_win
        sta abeam_done
        sta leg_good
        sta leg_max
        sta score_lo
        sta score_hi
        sta smoke_timer
        sta done_timer
        sta a_hold
        sta b_hold
        sta ai_timer
        sta eng_hi_last
        lda #1
        sta on_ground
        lda #2
        sta pitch_b
        lda #LEG_ROLL
        sta leg
        lda #'-'
        ldx #5
@g:     sta grades,x
        dex
        bpl @g
        lda #$FF
        sta chime_ptr
        sta ppu_buf
        lda #0
        sta buf_w
        lda #1
        sta hud_leg_dirty
        sta grades_dirty
        lda #M_ROLL
        jsr msg_set

        ; sprite-0(分屏锚)
        lda #38
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
        ; 坠机/结束展示计时后进入讲评
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
        ; 暂停(仅玩家)
        lda ai_on
        bne @noai_pause
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
        beq @noai_pause
        rts
@noai_pause:
        lda ai_on
        beq @player
        ; 演示中:START → 玩家新局;其他键 → 回标题
        lda pad_new
        and #BTN_STA
        beq @chk_other
        lda #0
        jmp start_game
@chk_other:
        lda pad_new
        and #BTN_A|BTN_B|BTN_SEL
        beq @ai_go
        jmp enter_title
@ai_go: jsr ai_tick
        jmp @common
@player:
        jsr apply_input
@common:
        jsr physics
        jsr legs_tick
        jsr scroll_tick
        jsr hud_tick
        jsr game_sprites
        rts

; ---------------- 玩家输入 ----------------
apply_input:
        ; A:加油门(按住连发)
        lda pad
        and #BTN_A
        beq @a_off
        inc a_hold
        lda pad_new
        and #BTN_A
        bne @a_do
        lda a_hold
        cmp #12
        bcc @a_done
        lda #0
        sta a_hold
@a_do:  lda thr
        cmp #8
        bcs @a_done
        inc thr
@a_done:
        jmp @b
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
        bcc @b_done
        lda #0
        sta b_hold
@b_do:  lda thr
        beq @b_done
        dec thr
@b_done:
        jmp @pitch
@b_off: lda #0
        sta b_hold
@pitch: lda pad_new
        and #BTN_UP
        beq @dn
        lda pitch_b
        cmp #4
        bcs @dn
        inc pitch_b
@dn:    lda pad_new
        and #BTN_DN
        beq @sel
        lda pitch_b
        beq @sel
        dec pitch_b
@sel:   lda pad_new
        and #BTN_SEL
        beq @left
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
@left:  lda pad_new
        and #BTN_LT
        beq @done
        jsr try_turn
@done:  rts

; ---------------- 自动驾驶(演示 / PatternPilot 传承) ----------------
ai_tick:
        inc ai_timer
        lda ai_timer
        and #$0F
        beq @act
        ; 转弯提示照按
        lda turn_win
        beq @rts
        jsr try_turn
@rts:   rts
@act:   ldx leg
        lda ai_thr_tab,x
        cmp #$FF
        beq @thr_done           ; 保持
        cmp thr
        beq @thr_done
        bcc @thr_dn
        inc thr
        bne @thr_done
@thr_dn:
        dec thr
@thr_done:
        lda ai_flap_tab,x
        cmp #$FF
        beq @flap_done
        cmp flaps
        beq @flap_done
        bcc @flap_dn
        inc flaps
        bne @flap_done
@flap_dn:
        dec flaps
@flap_done:
        ; 俯仰:按航段策略
        lda leg
        cmp #LEG_ROLL
        bne @n_roll
        lda #2
        sta pitch_b
        lda ias_hi
        cmp #56
        bcc @roll_done
        lda #4
        sta pitch_b
@roll_done:
        jmp @setp_done
@n_roll:
        cmp #LEG_UPWIND
        beq @climb
        cmp #LEG_XWIND
        bne @n_climb
        ; 侧风:接近 1000 改平
        lda alt_hi
        cmp #>995
        bcc @climb
        bne @lvl
        lda alt_lo
        cmp #<995
        bcc @climb
@lvl:   lda #2
        sta pitch_b
        jmp @setp_done
@climb: lda #4
        sta pitch_b
        jmp @setp_done
@n_climb:
        cmp #LEG_DWNWD
        bne @n_dwn
        ; 定高 1000:>1030 低头,<970 抬头
        lda alt_hi
        cmp #>1030
        bcc @dw_lowchk
        bne @dw_hi
        lda alt_lo
        cmp #<1030
        bcc @dw_lowchk
@dw_hi: lda #1
        sta pitch_b
        bne @setp_done
@dw_lowchk:
        lda alt_hi
        cmp #>970
        bcc @dw_lo
        bne @dw_mid
        lda alt_lo
        cmp #<970
        bcs @dw_mid
@dw_lo: lda #3
        sta pitch_b
        bne @setp_done
@dw_mid:
        lda #2
        sta pitch_b
        bne @setp_done
@n_dwn: cmp #LEG_BASE
        bne @n_base
        ; 四边:按 700 ft 带修正下滑
        lda #1
        sta pitch_b
        lda alt_hi
        cmp #>750
        bcc @b_lowchk
        bne @b_hi
        lda alt_lo
        cmp #<750
        bcc @b_lowchk
@b_hi:  lda #0
        sta pitch_b
        beq @b_done
@b_lowchk:
        lda alt_hi
        cmp #>650
        bcs @b_done
        lda #2
        sta pitch_b
@b_done:
        jmp @setp_done
@n_base:
        cmp #LEG_FINAL
        bne @n_fin
        ; 按 PAPI 修正
        ldx papi
        lda ai_papi_pitch,x
        sta pitch_b
        lda ai_papi_thr,x
        sta thr
        bne @setp_done
@n_fin: cmp #LEG_FLARE
        bne @n_flare
        ; 拉平:收油;15 ft 以上继续带下滑,以下改平飘落(掉速软接地)
        lda #0
        sta thr
        lda #1
        sta pitch_b
        lda alt_hi
        bne @setp_done
        lda alt_lo
        cmp #15
        bcs @setp_done
        lda #2
        sta pitch_b
@setp_done:
@n_flare:
        rts

; ---------------- 转弯窗口 ----------------
try_turn:
        lda turn_win
        beq @rts
        lda #0
        sta turn_win
        lda #48
        sta bank_timer
        inc next_turn
        ; 基础 200 分 + 精准 100
        lda #200
        jsr score_add8
        ; |px-bound| < 32?
        ldx next_turn
        dex
        txa
        asl a
        tax
        sec
        lda px_lo
        sbc turn_bounds,x
        sta tmp0
        lda px_hi
        sbc turn_bounds+1,x
        bpl @pos
        ; 取负
        lda tmp0
        eor #$FF
        clc
        adc #1
        sta tmp0
        lda #0                  ; 高位近似:窗口≤96,高位必 0/FF
@pos:   lda tmp0
        cmp #32
        bcs @chime
        lda #100
        jsr score_add8
@chime: ldy #CH_OK
        jsr chime_start
        lda #M_NONE
        sta msg_id
        lda #0
        sta msg_timer
        jsr msg_clear
@rts:   rts

; ---------------- 飞行物理(表驱动,POH 数字) ----------------
physics:
        ; 目标空速 = BASE[thr] + PITCH_MOD[pitch] - FLAP_DRAG[flaps]
        ldx thr
        lda base_ias,x
        sta tmp0
        lda #0
        sta tmp1
        ldx pitch_b
        lda stalled
        beq @use_p
        ldx #0                  ; 失速:等效满低头,速度自然恢复
@use_p: lda pitch_mod,x
        bpl @pm_pos
        clc
        adc tmp0
        sta tmp0
        lda tmp1
        adc #$FF
        sta tmp1
        jmp @pm_done
@pm_pos:
        clc
        adc tmp0
        sta tmp0
        bcc @pm_done
        inc tmp1
@pm_done:
        ldx flaps
        sec
        lda tmp0
        sbc flap_drag,x
        sta tmp0
        lda tmp1
        sbc #0
        sta tmp1
        bpl @cl_ok
        lda #0
        sta tmp0
@cl_ok: lda tmp0
        cmp #130
        bcc @cl2
        lda #130
@cl2:   sta tgt_ias

        ; ias += (tgt-ias) >> 9(空中 τ≈8.5s;地面 >>7,τ≈2s)
        sec
        lda #0
        sbc ias_fr
        sta tmp0
        lda tgt_ias
        sbc ias_hi
        sta tmp1
        ldx #9
        lda on_ground
        beq @sh
        ldx #7
@sh:    lda tmp1
        cmp #$80
        ror tmp1
        ror tmp0
        dex
        bne @sh
        clc
        lda ias_fr
        adc tmp0
        sta ias_fr
        lda ias_hi
        adc tmp1
        sta ias_hi

        ; 地面:不升降
        lda on_ground
        beq @air
        lda #0
        sta vs_lo
        sta vs_hi
        sta alt_fr
        sta alt_lo
        sta alt_hi
        sta stalled
        ; 起飞离地:IAS≥55 且带杆
        lda leg
        cmp #LEG_ROLL
        bne @gnd_done
        lda ias_hi
        cmp #55
        bcc @gnd_done
        lda pitch_b
        cmp #3
        bcc @gnd_done
        lda #0
        sta on_ground
        lda #LEG_UPWIND
        sta leg
        jsr on_leg_enter
@gnd_done:
        jmp @spd_done

@air:   ; 失速判定
        ldx flaps
        lda ias_hi
        cmp stall_spd,x
        bcs @rec_chk
        lda stalled
        bne @vs_calc
        lda #1
        sta stalled
        lda #M_STALL
        jsr msg_set
        jmp @vs_calc
@rec_chk:
        lda stalled
        beq @vs_calc
        lda stall_spd,x
        clc
        adc #4
        cmp ias_hi
        bcs @vs_calc
        lda #0
        sta stalled
@vs_calc:
        lda stalled
        beq @vs_norm
        lda #<(-480)
        sta vs_lo
        lda #>(-480)
        sta vs_hi
        jmp @vs_done
@vs_norm:
        ; vs = VS_TAB[pitch] × 2(表存半值,展开成 16 位)
        ldx pitch_b
        lda vs_tab,x
        sta vs_lo
        bpl @vp
        lda #$FF
        bne @vx
@vp:    lda #0
@vx:    sta vs_hi
        asl vs_lo
        rol vs_hi
@mush:  ; IAS<55:下沉(55-ias)*8
        lda ias_hi
        cmp #55
        bcs @vs_done
        lda #55
        sec
        sbc ias_hi
        asl a
        asl a
        asl a
        sta tmp0
        sec
        lda vs_lo
        sbc tmp0
        sta vs_lo
        lda vs_hi
        sbc #0
        sta vs_hi
@vs_done:
        ; alt += vs(24 位)
        lda vs_hi
        bpl @vs_ext_p
        lda #$FF
        bne @vs_ext
@vs_ext_p:
        lda #0
@vs_ext:
        sta tmp2
        clc
        lda alt_fr
        adc vs_lo
        sta alt_fr
        lda alt_lo
        adc vs_hi
        sta alt_lo
        lda alt_hi
        adc tmp2
        sta alt_hi
        ; 触地?
        bmi @touch
        lda alt_hi
        ora alt_lo
        ora alt_fr
        bne @ceil
@touch: jsr touchdown
        jmp @spd_done
@ceil:  ; 限高 2000
        lda alt_hi
        cmp #>2000
        bcc @spd_done
        bne @cl_alt
        lda alt_lo
        cmp #<2000
        bcc @spd_done
@cl_alt:
        lda #<2000
        sta alt_lo
        lda #>2000
        sta alt_hi
        lda #0
        sta alt_fr
@spd_done:
        ; 着陆滑跑减速
        lda on_ground
        beq @rts
        lda leg
        cmp #LEG_ROLLOUT
        bne @rts
        ; 刹车:B(或 AI)
        lda ai_on
        bne @brk
        lda pad
        and #BTN_B
        beq @stop_chk
@brk:   sec
        lda ias_fr
        sbc #96
        sta ias_fr
        lda ias_hi
        sbc #0
        sta ias_hi
        bpl @stop_chk
        lda #0
        sta ias_hi
        sta ias_fr
@stop_chk:
        lda ias_hi
        cmp #8
        bcs @rts
        lda #LEG_DONE
        sta leg
        lda #120
        sta done_timer
        jsr finish_flight
@rts:   rts

; ---------------- 接地 ----------------
touchdown:
        lda #0
        sta alt_fr
        sta alt_lo
        sta alt_hi
        sta stalled
        ; 下沉率(取负 → 正值,16 位钳到 255)
        sec
        lda #0
        sbc vs_lo
        sta ldg_raw
        lda #0
        sbc vs_hi
        beq @raw_ok
        lda #$FF
        sta ldg_raw
@raw_ok:
        lda #0
        sta vs_lo
        sta vs_hi
        ; 在跑道上?px≥THRESH 或 px<RWY_END
        lda px_hi
        cmp #>THRESH_AT
        bcc @chk_low
        bne @on_rwy
        lda px_lo
        cmp #<THRESH_AT
        bcs @on_rwy
@chk_low:
        lda px_hi
        cmp #>RWY_END
        bcc @chk_l2
        bne @off
        lda px_lo
        cmp #<RWY_END
        bcc @on_rwy
        bcs @off
@chk_l2:
        jmp @on_rwy
@off:   ; 落在场外
        lda #1
        sta crashed
        lda #150
        sta done_timer
        lda #'E'
        sta grades+5
        lda #M_OFFRWY
        jsr msg_set
        lda #10
        sta noise_burst
        lda #1
        sta on_ground
        lda #LEG_ROLLOUT
        sta leg
        rts
@on_rwy:
        lda #1
        sta on_ground
        lda #2
        sta pitch_b
        lda #LEG_ROLLOUT
        sta leg
        lda #30
        sta smoke_timer
        lda #12
        sta tri_timer
        lda #10
        sta noise_burst
        ; 评级:ldg_raw <32 A <60 B <100 C <144 D else 硬着陆
        ldx #0
        lda ldg_raw
        cmp #32
        bcc @grade
        inx
        cmp #60
        bcc @grade
        inx
        cmp #100
        bcc @grade
        inx
        cmp #144
        bcc @grade
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
@grade: txa
        clc
        adc #'A'
        sta grades+5
        lda #1
        sta grades_dirty
        ; 加分
        txa
        asl a
        tax
        lda ldg_score,x
        sta tmp0
        lda ldg_score+1,x
        sta tmp1
        jsr score_add16
        lda ldg_raw
        cmp #32
        bcs @msgb
        lda #M_NICE
        jsr msg_set
        jmp @snd
@msgb:  lda #M_ROLLOUT
        jsr msg_set
@snd:   ldy #CH_OK
        jsr chime_start
        jsr on_leg_enter        ; ROLLOUT 的 HUD 刷新
        rts

finish_flight:
        ; 完成航线小奖励
        lda #<300
        sta tmp0
        lda #>300
        sta tmp1
        jsr score_add16
        rts

; ---------------- 航段状态机 / 提示 / 采样 ----------------
legs_tick:
        ; px = wx + 76(mod MAP_X)
        clc
        lda wx_lo
        adc #76
        sta px_lo
        lda wx_hi
        adc #0
        sta px_hi
        cmp #>MAP_X
        bcc @px_ok
        ; wx<9216 → px<9292:减 9216
        sec
        lda px_lo
        sbc #<MAP_X
        sta px_lo
        lda px_hi
        sbc #>MAP_X
        sta px_hi
@px_ok:
        lda on_ground
        beq @airleg
        jmp @sample_done        ; 地面航段(ROLL/ROLLOUT)由物理层切换
@airleg:
        ; FLARE:仅从 FINAL/FLARE 进入,低于 40 ft 且接近跑道
        lda leg
        cmp #LEG_FINAL
        bcc @by_x
        lda alt_hi
        bne @by_x
        lda alt_lo
        cmp #40
        bcs @by_x
        ; px≥THRESH-320 或 px<RWY_END
        lda px_hi
        cmp #>(THRESH_AT-320)
        bcc @flare_low
        bne @flare_yes
        lda px_lo
        cmp #<(THRESH_AT-320)
        bcs @flare_yes
@flare_low:
        lda px_hi
        cmp #>RWY_END
        bcs @by_x
        bne @flare_yes
@flare_yes:
        lda leg
        cmp #LEG_FLARE
        beq @legdone
        jsr leg_finalize        ; 结算 FINAL 段评分
        lda #LEG_FLARE
        sta leg
        jsr on_leg_enter
        jmp @legdone
@by_x:  ; 按世界 X 判定航段
        ldx #LEG_UPWIND
        lda px_hi
        cmp #>XW_AT
        bcc @got
        bne @c2
        lda px_lo
        cmp #<XW_AT
        bcc @got
@c2:    inx                     ; XWIND
        lda px_hi
        cmp #>DW_AT
        bcc @got
        bne @c3
        lda px_lo
        cmp #<DW_AT
        bcc @got
@c3:    inx                     ; DWNWD
        lda px_hi
        cmp #>BASE_AT
        bcc @got
        bne @c4
        lda px_lo
        cmp #<BASE_AT
        bcc @got
@c4:    inx                     ; BASE
        lda px_hi
        cmp #>FIN_AT
        bcc @got
        bne @c5
        lda px_lo
        cmp #<FIN_AT
        bcc @got
@c5:    inx                     ; FINAL
@got:   txa
        cmp leg
        beq @legdone
        pha
        jsr leg_finalize        ; 结算旧航段评分
        pla
        sta leg
        jsr on_leg_enter
@legdone:
        ; 转弯窗口:比对下一个边界
        lda next_turn
        cmp #4
        bcs @turn_done
        asl a
        tax
        ; d = px - (bound-96)
        sec
        lda px_lo
        sbc turn_bounds_m96,x
        sta tmp0
        lda px_hi
        sbc turn_bounds_m96+1,x
        bmi @win_off            ; 还没到
        bne @past               ; 远超(>255)
        lda tmp0
        cmp #192                ; 窗口宽 192px
        bcs @past
        ; 窗口内
        lda turn_win
        bne @turn_done
        lda #1
        sta turn_win
        lda #M_TURN
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        jmp @turn_done
@past:  ; 错过 → 教官代打
        lda turn_win
        beq @turn_done
        lda #0
        sta turn_win
        lda #48
        sta bank_timer
        inc next_turn
        lda #M_MYCTL
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
        jmp @turn_done
@win_off:
@turn_done:
        ; ABEAM 提示(三边中点)
        lda abeam_done
        bne @abeam_done
        lda leg
        cmp #LEG_DWNWD
        bne @abeam_done
        lda px_hi
        cmp #>ABEAM_AT
        bcc @abeam_done
        bne @abeam_hit
        lda px_lo
        cmp #<ABEAM_AT
        bcc @abeam_done
@abeam_hit:
        lda #1
        sta abeam_done
        lda #M_ABEAM
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
@abeam_done:
        ; 采样评分(航段 1..5,每 16 帧)
        lda leg
        beq @sample_done
        cmp #LEG_FLARE
        bcs @sample_done
        lda frame
        and #$0F
        bne @sample_done
        inc leg_max
        inc leg_max
        ldx leg
        ; IAS 在带内?
        lda ias_hi
        sec
        sbc leg_tgt_ias,x
        bpl @abs_ok
        eor #$FF
        clc
        adc #1
@abs_ok:
        cmp leg_tol,x
        bcs @ias_bad
        inc leg_good
        lda #2
        jsr score_add8
@ias_bad:
        ; 模式:0 爬升 1 平飞 2 下降 4 爬升或到高
        lda leg_mode,x
        beq @m_climb
        cmp #1
        beq @m_level
        cmp #4
        beq @m_cl
        ; 下降:vs ≤ -20
        lda vs_hi
        bpl @m_bad
        cmp #$FF
        bne @m_ok
        lda vs_lo
        cmp #$ED
        bcs @m_bad
        bcc @m_ok
@m_cl:  ; 爬升合格,或已平飞在 1000 带内
        lda vs_hi
        bmi @m_level
        bne @m_ok
        lda vs_lo
        cmp #20
        bcs @m_ok
        bcc @m_level
@m_climb:
        lda vs_hi
        bmi @m_bad
        bne @m_ok
        lda vs_lo
        cmp #20
        bcc @m_bad
        bcs @m_ok
@m_level:
        ; |alt-1000| ≤ 80 → alt-920 在 [0,160]
        sec
        lda alt_lo
        sbc #<920
        tay
        lda alt_hi
        sbc #>920
        bne @m_bad
        cpy #161
        bcs @m_bad
@m_ok:  inc leg_good
        lda #2
        jsr score_add8
@m_bad:
@sample_done:
        ; PAPI(五边/拉平)
        jsr papi_calc
        ; 失速警告横幅刷新
        rts

; 旧航段评分结算 → 字母
leg_finalize:
        lda leg
        beq @rts
        cmp #LEG_FLARE
        bcs @rts
        tax
        dex                     ; 槽位 0..4
        lda leg_max
        beq @store_e
        ; good*10 与 max*9/7/5/3 比
        lda leg_good
        ldy #10
        jsr mul8
        lda mul_lo
        sta num_lo
        lda mul_hi
        sta num_hi
        lda leg_max
        ldy #9
        jsr mul8
        jsr cmp_num_mul
        bcs @a
        lda leg_max
        ldy #7
        jsr mul8
        jsr cmp_num_mul
        bcs @b
        lda leg_max
        ldy #5
        jsr mul8
        jsr cmp_num_mul
        bcs @c
        lda leg_max
        ldy #3
        jsr mul8
        jsr cmp_num_mul
        bcs @d
@store_e:
        lda #'E'
        bne @store
@a:     lda #'A'
        bne @store
@b:     lda #'B'
        bne @store
@c:     lda #'C'
        bne @store
@d:     lda #'D'
@store: sta grades,x
        lda #1
        sta grades_dirty
        ; 完段 +100
        lda #100
        jsr score_add8
        ldy #CH_OK
        jsr chime_start
@rts:   lda #0
        sta leg_good
        sta leg_max
        rts

; num ≥ mul ?(C=1 是)
cmp_num_mul:
        lda num_hi
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

; 航段进入:消息 + HUD 脏标记
on_leg_enter:
        lda #1
        sta hud_leg_dirty
        ldx leg
        lda leg_msg,x
        beq @nomsg
        jsr msg_set
@nomsg: rts

; ---------------- PAPI ----------------
papi_calc:
        lda leg
        cmp #LEG_FINAL
        beq @on
        cmp #LEG_FLARE
        beq @on
        lda #2
        sta papi
        rts
@on:    ; dist = 9040 - px(px<9040 时;超过则 0)
        sec
        lda #<9040
        sbc px_lo
        sta tmp0
        lda #>9040
        sbc px_hi
        sta tmp1
        bpl @dist_ok
        lda #0
        sta tmp0
        sta tmp1
@dist_ok:
        ; ideal = dist*13 >> 5
        lda tmp0
        sta num_lo
        lda tmp1
        sta num_hi
        ; num*13 = num*8 + num*4 + num
        lda num_lo
        sta tmp2
        lda num_hi
        sta tmp3
        asl num_lo
        rol num_hi
        asl num_lo
        rol num_hi              ; ×4
        clc
        lda num_lo
        adc tmp2
        sta tmp4
        lda num_hi
        adc tmp3
        sta tmp5                ; ×5
        asl num_lo
        rol num_hi              ; ×8
        clc
        lda num_lo
        adc tmp4
        sta num_lo
        lda num_hi
        adc tmp5
        sta num_hi              ; ×13
        ldx #5
@shr:   lsr num_hi
        ror num_lo
        dex
        bne @shr
        ; diff = alt - ideal(有符号 16 位)
        sec
        lda alt_lo
        sbc num_lo
        sta tmp0
        lda alt_hi
        sbc num_hi
        sta tmp1
        ; 分档:>+80 → 0 红;>+30 → 1;≥-30 → 2;≥-80 → 3;else 4
        bmi @below
        bne @very_hi
        lda tmp0
        cmp #80
        bcs @very_hi
        cmp #30
        bcs @hi1
        lda #2
        sta papi
        rts
@very_hi:
        lda #0
        sta papi
        rts
@hi1:   lda #1
        sta papi
        rts
@below: ; 负:tmp = -diff
        sec
        lda #0
        sbc tmp0
        sta tmp0
        lda #0
        sbc tmp1
        bne @very_lo            ; ≤ -256
        lda tmp0
        cmp #80
        bcs @very_lo
        cmp #30
        bcs @lo3
        lda #2
        sta papi
        rts
@lo3:   lda #3
        sta papi
        rts
@very_lo:
        lda #4
        sta papi
        rts

; ---------------- 卷轴 / 列流式生成 ----------------
scroll_tick:
        lda on_ground
        bne @roll
        lda #0
@roll:  ; dx = ias*6(16 位)
        lda ias_hi
        sta tmp0
        lda #0
        sta tmp1
        asl tmp0
        rol tmp1                ; ×2
        lda tmp0
        sta tmp2
        lda tmp1
        sta tmp3
        asl tmp0
        rol tmp1                ; ×4
        clc
        lda tmp0
        adc tmp2
        sta tmp0
        lda tmp1
        adc tmp3
        sta tmp1                ; ×6
        ; wx(16.8)+= dx(视作 8.8)
        clc
        lda wx_fr
        adc tmp0
        sta wx_fr
        lda wx_lo
        adc tmp1
        sta wx_lo
        lda wx_hi
        adc #0
        sta wx_hi
        ; 回绕
        cmp #>MAP_X
        bcc @nowrap
        sec
        lda wx_hi
        sbc #>MAP_X
        sta wx_hi
        jsr on_wrap
@nowrap:
        ; 列前瞻:cam_col 变化 → 生成 cam_col+33
        lda wx_lo
        sta tmp0
        lda wx_hi
        sta tmp1
        lsr tmp1
        ror tmp0
        lsr tmp1
        ror tmp0
        lsr tmp1
        ror tmp0
        lda tmp0
        cmp lastcol_lo
        bne @newcol
        lda tmp1
        cmp lastcol_hi
        beq @rts
@newcol:
        lda tmp0
        sta lastcol_lo
        lda tmp1
        sta lastcol_hi
        ; scol = cam_col + 33
        clc
        lda tmp0
        adc #33
        sta scol_lo
        lda tmp1
        adc #0
        sta scol_hi
        ; wcol = scol mod 1152
        lda scol_lo
        sta wcol_lo
        lda scol_hi
        sta wcol_hi
        cmp #>MAP_COLS
        bcc @modded
        bne @sub
        lda wcol_lo
        cmp #<MAP_COLS
        bcc @modded
@sub:   sec
        lda wcol_lo
        sbc #<MAP_COLS
        sta wcol_lo
        lda wcol_hi
        sbc #>MAP_COLS
        sta wcol_hi
@modded:
        jsr build_col
        jsr emit_col_buf
        ; 每 4 列刷新该属性列(行 24-31 调色板:草地/跑道)
        lda scol_lo
        and #3
        bne @rts
        jsr emit_attr_buf
@rts:   rts

on_wrap:
        inc lap
        lda #0
        sta next_turn
        sta abeam_done
        ; 空中且高于 40 ft → 复飞
        lda on_ground
        bne @rts
        lda alt_hi
        bne @ga
        lda alt_lo
        cmp #40
        bcc @rts
@ga:    lda #M_GOAROUND
        jsr msg_set
        ldy #CH_WARN
        jsr chime_start
@rts:   rts

; ---------------- 列内容生成(col_tiles[0..23] = 行 6..29) ----------------
; 输入:wcol_lo/hi(0..1151)
build_col:
        lda #0
        ldx #23
@clr:   sta col_tiles,x
        dex
        bpl @clr
        ; h = hash(wcol)
        lda wcol_lo
        asl a
        asl a
        eor wcol_lo
        clc
        adc wcol_hi
        eor #$5A
        sta tmp4                ; h
        ; 跑道区?
        ldx #0                  ; tmp5=rz
        lda wcol_hi
        bne @chk_hi
        lda wcol_lo
        cmp #72
        bcs @rz_done
        inx
        bne @rz_done
@chk_hi:
        cmp #4
        bne @rz_done
        lda wcol_lo
        cmp #$62                ; 1122
        bcc @rz_done
        inx
@rz_done:
        stx tmp5
        ; 云带 A(行 6-7)
        lda tmp4
        and #$07
        bne @ca1
        lda #$6D
        sta col_tiles+0
        beq @cb
@ca1:   cmp #1
        bne @cb
        lda #$6D
        sta col_tiles+1
@cb:    ; 云带 B(行 8-13)
        lda tmp4
        and #$0E
        cmp #2
        bne @cb2
        lda tmp4
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        tax
        lda #$6D
        sta col_tiles+2,x
        bne @hills
@cb2:   cmp #8
        bne @hills
        lda tmp4
        lsr a
        lsr a
        lsr a
        lsr a
        and #1
        tax
        lda #$6D
        sta col_tiles+5,x
@hills: ; 山脊(行 21-23 = idx 15-17),8 列一档
        lda wcol_hi
        sta tmp1
        lda wcol_lo
        lsr tmp1
        ror a
        lsr tmp1
        ror a
        lsr tmp1
        ror a
        sta tmp0                ; wcol>>3
        asl a
        asl a
        eor tmp0
        eor #$C3
        and #3
        tax                     ; hh
        lda #$67
        sta col_tiles+17
        cpx #1
        bcc @decor
        beq @h1
        lda #$68
        sta col_tiles+15
        lda #$67
        sta col_tiles+16
        bne @decor
@h1:    lda #$68
        sta col_tiles+16
@decor: ; 景物(行 24-25 = idx 18-19)
        lda tmp5
        beq @grass_decor
        ; 跑道区固定:4 风袋 14 塔台 20/21 机库
        lda wcol_hi
        bne @ground
        lda wcol_lo
        cmp #4
        bne @rd1
        lda #$73
        sta col_tiles+19
        bne @ground
@rd1:   cmp #14
        bne @rd2
        lda #$74
        sta col_tiles+18
        lda #$75
        sta col_tiles+19
        bne @ground
@rd2:   cmp #20
        bne @rd3
        lda #$76
        sta col_tiles+19
        bne @ground
@rd3:   cmp #21
        bne @ground
        lda #$77
        sta col_tiles+19
        bne @ground
@grass_decor:
        lda tmp4
        and #$1F
        bne @gd1
        lda #$6E
        sta col_tiles+18
        lda #$6F
        sta col_tiles+19
        bne @ground
@gd1:   cmp #4
        bne @gd2
        lda #$70
        sta col_tiles+19
        bne @ground
@gd2:   cmp #8
        bne @gd3
        lda #$72
        sta col_tiles+19
        bne @ground
@gd3:   cmp #12
        bne @ground
        lda #$71
        sta col_tiles+19
@ground: ; 行 26-29 = idx 20-23
        lda tmp5
        beq @grass_gnd
        ; 端头条纹?(68-71 或 1122-1125)
        lda wcol_hi
        bne @th_hi
        lda wcol_lo
        cmp #68
        bcc @rwy_norm
        cmp #72
        bcs @rwy_norm
        bcc @thresh
@th_hi: lda wcol_lo
        cmp #$62
        bcc @rwy_norm
        cmp #$66
        bcs @rwy_norm
@thresh:
        lda #$66
        sta col_tiles+20
        sta col_tiles+21
        lda #$64
        sta col_tiles+22
        sta col_tiles+23
        rts
@rwy_norm:
        lda #$63
        sta col_tiles+20
        lda wcol_lo
        and #3
        cmp #2
        bcs @dash_off
        lda #$65
        bne @dash
@dash_off:
        lda #$64
@dash:  sta col_tiles+21
        lda #$64
        sta col_tiles+22
        sta col_tiles+23
        rts
@grass_gnd:
        lda tmp4
        and #1
        beq @ga2
        lda #$60
        bne @gs
@ga2:   lda #$61
@gs:    sta col_tiles+20
        lda #$62
        sta col_tiles+21
        sta col_tiles+22
        sta col_tiles+23
        rts

; 列 → 缓冲(inc32,addr = NT + $C0 + x)
emit_col_buf:
        ldy buf_w
        lda scol_lo
        and #$20
        beq @nt0
        lda #$24
        bne @hi
@nt0:   lda #$20
@hi:    sta ppu_buf,y
        iny
        lda scol_lo
        and #$1F
        clc
        adc #$C0
        sta ppu_buf,y
        iny
        lda #24|$80
        sta ppu_buf,y
        iny
        ldx #0
@d:     lda col_tiles,x
        sta ppu_buf,y
        iny
        inx
        cpx #24
        bne @d
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; 属性列(行 6/7 两字节)→ 缓冲
emit_attr_buf:
        ldy buf_w
        lda scol_lo
        and #$20
        beq @nt0
        lda #$27
        bne @hi
@nt0:   lda #$23
@hi:    sta ppu_buf,y
        iny
        sta tmp3
        lda scol_lo
        and #$1F
        lsr a
        lsr a
        clc
        adc #$F0
        sta ppu_buf,y
        iny
        lda #1
        sta ppu_buf,y
        iny
        lda tmp5                ; rz(build_col 留下的)
        beq @grass
        lda #$AA
        bne @v1
@grass: lda #$55
@v1:    sta ppu_buf,y
        iny
        ; 第二字节 $F8+acol
        lda tmp3
        sta ppu_buf,y
        iny
        lda scol_lo
        and #$1F
        lsr a
        lsr a
        clc
        adc #$F8
        sta ppu_buf,y
        iny
        lda #1
        sta ppu_buf,y
        iny
        lda tmp5
        beq @grass2
        lda #$AA
        bne @v2
@grass2:
        lda #$55
@v2:    sta ppu_buf,y
        iny
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; ---------------- HUD(轮转字段更新,跳表分发) ----------------
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

hud_f0: ; IAS(3 位)
        lda ias_hi
        jsr b2d8
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$25
        sta ppu_buf,y
        iny
        lda #3
        sta ppu_buf,y
        iny
        ldx #0
@ic:    lda dec_buf+2,x
        sta ppu_buf,y
        iny
        inx
        cpx #3
        bne @ic
        jmp hud_term

hud_f1: ; ALT(4 位)
        lda alt_lo
        sta num_lo
        lda alt_hi
        sta num_hi
        jsr b2d16
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$2E
        sta ppu_buf,y
        iny
        lda #4
        sta ppu_buf,y
        iny
        ldx #1
@ac:    lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @ac
        jmp hud_term

hud_f2: ; RPM(查表 ASCII)
        lda thr
        asl a
        asl a
        tax
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$38
        sta ppu_buf,y
        iny
        lda #4
        sta ppu_buf,y
        iny
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

hud_f3: ; 襟翼(2 位)+ 分数(5 位)
        lda flaps
        asl a
        tax
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$3E
        sta ppu_buf,y
        iny
        lda #2
        sta ppu_buf,y
        iny
        lda flap_str,x
        sta ppu_buf,y
        iny
        lda flap_str+1,x
        sta ppu_buf,y
        iny
        sty buf_w
        lda score_lo
        sta num_lo
        lda score_hi
        sta num_hi
        jsr b2d16
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$52
        sta ppu_buf,y
        iny
        lda #5
        sta ppu_buf,y
        iny
        ldx #0
@sc:    lda dec_buf,x
        sta ppu_buf,y
        iny
        inx
        cpx #5
        bne @sc
        jmp hud_term

hud_f4: ; VS 箭头
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$5C
        sta ppu_buf,y
        iny
        lda #1
        sta ppu_buf,y
        iny
        lda vs_hi
        bmi @dn
        bne @up
        lda vs_lo
        cmp #24
        bcs @up
        lda #'-'
        bne @vw
@up:    lda #$04
        bne @vw
@dn:    lda #$05
@vw:    sta ppu_buf,y
        iny
        jmp hud_term

hud_f5: ; 航段名 + 目标(脏时)
        lda hud_leg_dirty
        bne @go
        rts
@go:    lda #0
        sta hud_leg_dirty
        ldx leg
        lda leg_name_lo,x
        sta ptr_lo
        lda leg_name_hi,x
        sta ptr_hi
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$85
        sta ppu_buf,y
        iny
        lda #8
        sta ppu_buf,y
        iny
        sty tmp0
        ldy #0
@ln:    lda (ptr_lo),y
        ldx tmp0
        sta ppu_buf,x
        inc tmp0
        iny
        cpy #8
        bne @ln
        ldy tmp0
        sty buf_w
        ; 目标空速(3)+ 高度(4)
        lda leg
        asl a
        adc leg                 ; ×3
        tax
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$45
        sta ppu_buf,y
        iny
        lda #3
        sta ppu_buf,y
        iny
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
        lda leg
        asl a
        asl a                   ; ×4
        tax
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$49
        sta ppu_buf,y
        iny
        lda #4
        sta ppu_buf,y
        iny
        lda tgt_alt_str,x
        sta ppu_buf,y
        iny
        lda tgt_alt_str+1,x
        sta ppu_buf,y
        iny
        lda tgt_alt_str+2,x
        sta ppu_buf,y
        iny
        lda tgt_alt_str+3,x
        sta ppu_buf,y
        iny
        jmp hud_term

hud_f6: ; 评分槽(脏时)
        lda grades_dirty
        bne @go
        rts
@go:    lda #0
        sta grades_dirty
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$90
        sta ppu_buf,y
        iny
        lda #6
        sta ppu_buf,y
        iny
        ldx #0
@gr:    lda grades,x
        sta ppu_buf,y
        iny
        inx
        cpx #6
        bne @gr
        jmp hud_term

hud_f7: ; 消息计时
        lda msg_timer
        beq @demo_msg
        dec msg_timer
        bne @rts
        jsr msg_clear
        rts
@demo_msg:
        lda ai_on
        beq @rts
        lda frame
        bne @rts
        lda #M_DEMO
        jsr msg_set
@rts:   rts

; ---------------- 消息 ----------------
; A = 消息 id
msg_set:
        sta msg_id
        cmp #M_NONE
        beq @rts
        tax
        lda msg_lo,x
        sta ptr_lo
        lda msg_hi,x
        sta ptr_hi
        lda #240
        sta msg_timer
        ; 写 30 字符(串 0 结尾,余下补空格)
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$61
        sta ppu_buf,y
        iny
        lda #30
        sta ppu_buf,y
        iny
        sty tmp0
        ldy #0
        ldx tmp0
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
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$61
        sta ppu_buf,y
        iny
        lda #30
        sta ppu_buf,y
        iny
        ldx #0
        lda #' '
@sp:    sta ppu_buf,y
        iny
        inx
        cpx #30
        bne @sp
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        lda #M_NONE
        sta msg_id
        rts

; ---------------- 精灵 ----------------
game_sprites:
        ; 高度 → 屏幕 Y:py = 192 - min(140, alt/2)
        lda alt_hi
        bne @cap
        lda alt_lo
        lsr a
        cmp #140
        bcc @gotpx
@cap:   lda #140
@gotpx: sta tmp0
        lda #GROUND_PY
        sec
        sbc tmp0
        sta plane_py
        ; 失速抖振
        lda stalled
        beq @pose
        lda frame
        and #$04
        beq @pose
        inc plane_py
@pose:  ; 姿态
        lda bank_timer
        beq @nb
        dec bank_timer
        lda #3
        bne @setpose
@nb:    lda stalled
        bne @posedn
        lda pitch_b
        cmp #3
        bcs @poseup
        cmp #2
        beq @poselv
@posedn:
        lda #2
        bne @setpose
@poseup:
        lda #1
        bne @setpose
@poselv:
        lda #0
@setpose:
        sta pose
        lda #PLANE_SX
        jsr draw_plane_at
        ; 转弯箭头(OAM 7-10)
        lda turn_win
        beq @arr_off
        lda frame
        and #$08
        bne @arr_off
        lda plane_py
        sec
        sbc #12
        sta tmp0
        ldx #0
@arr:   lda tmp0
        sta oam+28,x            ; y
        lda arrow_tiles,x
        pha
        txa
        and #2
        beq @arow0
        lda tmp0
        clc
        adc #8
        sta oam+28,x
@arow0: pla
        sta oam+29,x
        lda #$01                ; 调色板 1
        sta oam+30,x
        txa
        and #1
        beq @acol0
        lda #PLANE_SX+40
        bne @asx
@acol0: lda #PLANE_SX+32
@asx:   sta oam+31,x
        inx
        inx
        inx
        inx
        cpx #16
        bne @arr
        beq @papi_s
@arr_off:
        lda #$F8
        sta oam+28
        sta oam+32
        sta oam+36
        sta oam+40
@papi_s: ; PAPI 灯(OAM 11-14),仅五边显示
        lda leg
        cmp #LEG_FINAL
        beq @papi_on
        cmp #LEG_FLARE
        beq @papi_on
        lda #$F8
        sta oam+44
        sta oam+48
        sta oam+52
        sta oam+56
        bne @smoke
@papi_on:
        ldx #0
@pl:    lda #31
        sta oam+44,x            ; y(面板行 4)
        ; 瓦片:i ≥ 4-papi → 红
        txa
        lsr a
        lsr a                   ; i = x/4
        sta tmp0
        lda #4
        sec
        sbc papi
        cmp tmp0
        beq @red
        bcs @white
@red:   lda #$49
        bne @pt
@white: lda #$48
@pt:    sta oam+45,x
        lda #$00
        sta oam+46,x
        txa
        asl a                   ; x*2 → 间距 8:x=0,4,8,12 → 0,8,16,24
        clc
        adc #224
        sta oam+47,x
        inx
        inx
        inx
        inx
        cpx #16
        bne @pl
@smoke: ; 接地烟(OAM 15-16)
        lda smoke_timer
        beq @smoke_off
        dec smoke_timer
        lda #200
        sta oam+60
        lda #$40
        sta oam+61
        lda #$02
        sta oam+62
        lda #PLANE_SX
        sec
        sbc smoke_timer
        sta oam+63
        lda #204
        sta oam+64
        lda #$41
        sta oam+65
        lda #$02
        sta oam+66
        lda #PLANE_SX+12
        sec
        sbc smoke_timer
        sta oam+67
        rts
@smoke_off:
        lda #$F8
        sta oam+60
        sta oam+64
        rts

; 画飞机 6 精灵(OAM 1-6)。A=屏幕 X,plane_py/pose 已设
draw_plane_at:
        sta tmp0
        ; 变体 = pose*2 + 桨相位
        lda pose
        asl a
        sta tmp1
        lda frame
        lsr a
        lsr a
        and #1
        clc
        adc tmp1
        ; 瓦片基址 = $10 + 变体*6
        sta tmp1
        asl a
        adc tmp1                ; ×3
        asl a                   ; ×6
        clc
        adc #$10
        sta tmp1                ; 基瓦片
        ldx #0                  ; OAM 偏移(从 oam+4)
        ldy #0                  ; 瓦片序号
@t:     ; y
        tya
        cmp #3
        lda plane_py
        bcc @row0
        clc
        adc #8
@row0:  sec
        sbc #1
        sta oam+4,x
        ; tile
        tya
        clc
        adc tmp1
        sta oam+5,x
        lda #$00
        sta oam+6,x
        ; x = tmp0 + (i%3)*8
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

; ---------------- 讲评 ----------------
enter_debrief:
        lda #0
        sta $2000
        sta $2001
        bit $2002               ; 复位 w 锁存(分屏单写后 w=1)
        lda #ST_DEBRIEF
        sta game_state
        jsr draw_debrief
        lda #$FF
        sta ppu_buf
        lda #0
        sta buf_w
        ; 黑底
        lda #$3F
        sta $2006
        lda #$00
        sta $2006
        lda #$0F
        sta $2007
        lda #$0A
        sta $2001               ; 只开背景(精灵全藏)
        ldx #$F8
        stx oam+4
        stx oam+8
        stx oam+12
        stx oam+16
        stx oam+20
        stx oam+24
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

; 清两个 NT + 属性
clear_nts:
        lda #$20
        sta $2006
        lda #$00
        sta $2006
        ldx #8                  ; 8×256 = 2KB
        ldy #0
        lda #$00
@c:     sta $2007
        iny
        bne @c
        dex
        bne @c
        rts

; 属性表基础布局(游戏/标题共用):
; 行 0-1 = $00(面板),行 2-5 = $FF(天空/山),行 6-7 由列生成时覆盖
init_attrs:
        ldx #0                  ; NT0
        jsr @one
        ldx #4                  ; NT1
@one:   txa
        clc
        adc #$23
        sta $2006
        lda #$C0
        sta $2006
        ldy #16
        lda #$00
@a0:    sta $2007
        dey
        bne @a0
        ldy #32
        lda #$FF
@a1:    sta $2007
        dey
        bne @a1
        ldy #16
        lda #$55                ; 默认草地;跑道列稍后覆盖
@a2:    sta $2007
        dey
        bne @a2
        rts

; 直写一列(渲染关):scol/wcol 已设,col_tiles 已生成
emit_col_direct:
        lda scol_lo
        and #$20
        beq @nt0
        lda #$24
        bne @hi
@nt0:   lda #$20
@hi:    sta $2006
        lda scol_lo
        and #$1F
        clc
        adc #$C0
        sta $2006
        lda #$04                ; inc32,NMI 关(直写仅在渲染关时)
        sta $2000
        ldx #0
@d:     lda col_tiles,x
        sta $2007
        inx
        cpx #24
        bne @d
        lda #$00
        sta $2000
        rts

; ptr → 以 0 结尾字符串写到当前 $2006 位置
draw_str:
        ldy #0
@c:     lda (ptr_lo),y
        beq @done
        sta $2007
        iny
        bne @c
@done:  rts

; A=hi X=lo 设置 PPU 地址
set_addr:
        sta $2006
        stx $2006
        rts

; 游戏静态画面:面板 + 初始 64 列世界
draw_game_static:
        jsr clear_nts
        jsr init_attrs
        ; 面板 NT0 行 0-5
        lda #$20
        ldx #$00
        jsr set_addr
        ldx #0
@r0:    lda #$03
        sta $2007
        inx
        cpx #32
        bne @r0
        ldx #0
@r14:   lda panel_row1,x
        sta $2007
        inx
        cpx #128
        bne @r14
        ldx #0
@r5:    lda #$02
        sta $2007
        inx
        cpx #32
        bne @r5
        ; NT1 行 0-5:顶线/黑/分隔条(分屏提前一行的保险)
        lda #$24
        ldx #$00
        jsr set_addr
        ldx #0
@n0:    lda #$03
        sta $2007
        inx
        cpx #32
        bne @n0
        ldx #0
        lda #$01
@n14:   sta $2007
        inx
        cpx #128
        bne @n14
        ldx #0
@n5:    lda #$02
        sta $2007
        inx
        cpx #32
        bne @n5
        ; 初始 64 列
        lda #0
        sta scol_lo
        sta scol_hi
@cols:  lda scol_lo
        sta wcol_lo
        lda #0
        sta wcol_hi
        jsr build_col
        jsr emit_col_direct
        ; 跑道属性列(行 6/7):rz 时 $AA
        lda scol_lo
        and #3
        bne @next
        lda tmp5
        beq @next
        lda scol_lo
        and #$20
        beq @a_nt0
        lda #$27
        bne @a_hi
@a_nt0: lda #$23
@a_hi:  sta $2006
        pha
        lda scol_lo
        and #$1F
        lsr a
        lsr a
        clc
        adc #$F0
        sta $2006
        lda #$AA
        sta $2007
        pla
        sta $2006
        lda scol_lo
        and #$1F
        lsr a
        lsr a
        clc
        adc #$F8
        sta $2006
        lda #$AA
        sta $2007
@next:  inc scol_lo
        lda scol_lo
        cmp #64
        bne @cols
        rts

; 标题画面
draw_title:
        jsr clear_nts
        jsr init_attrs
        ; 地景先画(64 列,取世界 200 起的草地段),文字后叠
        lda #0
        sta scol_lo
        sta scol_hi
@cols:  lda scol_lo
        clc
        adc #200
        sta wcol_lo
        lda #0
        adc #0
        sta wcol_hi
        jsr build_col
        jsr emit_col_direct
        inc scol_lo
        lda scol_lo
        cmp #64
        bne @cols
        ; 大字 C172S(行 8-9,列 11)
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
        ; 五边飞行(行 11-12,列 12)
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
        ; 文本行
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
        lda #<str_keys
        sta ptr_lo
        lda #>str_keys
        sta ptr_hi
        lda #$23
        ldx #$60                ; 行 27(地面上,SMB 版权行风格)
        jsr set_addr
        jsr draw_str
        rts

; 讲评画面
draw_debrief:
        jsr clear_nts
        ; 全黑底
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
        ; 属性全 0
        lda #$23
        ldx #$C0
        jsr set_addr
        ldy #64
        lda #$00
@at:    sta $2007
        dey
        bne @at
        ; 标题
        lda #<str_log
        sta ptr_lo
        lda #>str_log
        sta ptr_hi
        lda #$20
        ldx #$6B
        jsr set_addr
        jsr draw_str
        ; 五段 + 着陆:行 6,8,10,12,14,16,列 8
        ldx #0
@leg:   stx tmp0
        txa
        asl a                   ; ×2 行距
        clc
        adc #6
        ; 地址 = $2000 + 行*32 + 8
        sta tmp1
        lda #0
        sta tmp2
        asl tmp1
        rol tmp2
        asl tmp1
        rol tmp2
        asl tmp1
        rol tmp2
        asl tmp1
        rol tmp2
        asl tmp1
        rol tmp2
        lda tmp2
        clc
        adc #$20
        sta $2006
        lda tmp1
        clc
        adc #8
        sta $2006
        ; 名字(8 字符)
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
        ; 接地率
        lda #<str_touch
        sta ptr_lo
        lda #>str_touch
        sta ptr_hi
        lda #$22
        ldx #$48
        jsr set_addr
        jsr draw_str
        lda ldg_raw
        ldy #7
        jsr mul8
        lsr mul_hi
        ror mul_lo              ; ×3.5 ≈ 真实 FPM(补偿 4 倍垂直缩放)
        lda mul_lo
        sta num_lo
        lda mul_hi
        sta num_hi
        jsr b2d16
        ldx #1
@fp:    lda dec_buf,x
        sta $2007
        inx
        cpx #5
        bne @fp
        lda #' '
        sta $2007
        lda #'F'
        sta $2007
        lda #'P'
        sta $2007
        lda #'M'
        sta $2007
        ; 总分
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
        beq @rate_score
        lda #<str_r_crash
        sta ptr_lo
        lda #>str_r_crash
        sta ptr_hi
        bne @rate_draw
@rate_score:
        ; ≥5000 / ≥3800 / ≥2200 / 其他
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
        bne @rate_draw
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
        bne @rate_draw
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
        bne @rate_draw
@r3:    lda #<str_r3
        sta ptr_lo
        lda #>str_r3
        sta ptr_hi
@rate_draw:
        lda #$22
        ldx #$C3
        jsr set_addr
        jsr draw_str
        ; PRESS START
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
; 声音
; ============================================================================
CH_OK   = 0                     ; 序表偏移:C5 E5 G5
CH_WARN = 4                     ; G4 E4 G4
CH_BLIP = 8                     ; E5 -

chime_start:
        sty chime_base
        lda #0
        sta chime_note
        lda #1
        sta chime_timer
        lda #0
        sta chime_ptr           ; 0=激活
        rts

sound_tick:
        lda game_state
        cmp #ST_TITLE
        bne @ingame
        jmp music_tick
@ingame:
        cmp #ST_GAME
        beq @game
        ; 讲评:引擎静音,只留啁啾
        lda #$30
        sta $4000
        sta $400C
        jmp @chime
@game:  ; --- 引擎(方波1):周期表 + 微抖 ---
        ldx thr
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
        lda #$70|2
        bne @ev
@evol:  ldx thr
        lda eng_vol,x
        ora #$70
@ev:    sta $4000
        ; --- 失速喇叭(方波2,优先于啁啾) ---
        lda on_ground
        bne @horn_off
        ldx flaps
        lda stall_spd,x
        clc
        adc #5
        cmp ias_hi
        bcc @horn_off
        lda #1
        sta horn_on
        lda #$B0|9
        sta $4004
        lda frame
        and #$08
        beq @h1
        lda #<186
        sta $4006
        lda #>186
        sta $4007
        bne @noise
@h1:    lda #<210
        sta $4006
        lda #>210
        sta $4007
        bne @noise
@horn_off:
        lda horn_on
        beq @chime
        lda #0
        sta horn_on
        lda #$B0
        sta $4004               ; 音量 0
@chime: ; --- 啁啾(方波2,喇叭空闲时) ---
        lda horn_on
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
        lda #$B0|7
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
@noise: ; --- 噪声:风声/滑跑 + 接地爆发 ---
        lda game_state
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
@wind:  lda ias_hi
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
@tri:   ; --- 三角:接地闷响 ---
        lda tri_timer
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
        lda #$01
        ora #$08
        sta $400B
        lda tri_timer
        bne @rts
        lda #$80
        sta $4008
        lda #$08
        sta $400B
@rts:   rts

; 标题音乐:方1 主旋 / 方2 和声 / 三角低音
music_tick:
        ; 方波1
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
        lda #$B0|6
        sta $4000
        bne @m2
@r1:    lda #$B0
        sta $4000
@m2:    ; 方波2
        dec mus_t2
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
        lda #$B0|4
        sta $4004
        bne @m3
@r2:    lda #$B0
        sta $4004
@m3:    ; 三角
        dec mus_t3
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
; 数学 / 工具
; ============================================================================

; A × Y → mul_hi:mul_lo(小乘数循环加)
mul8:
        sta tmp0
        lda #0
        sta mul_lo
        sta mul_hi
        cpy #0
        beq @rts
@l:     clc
        lda mul_lo
        adc tmp0
        sta mul_lo
        bcc @nc
        inc mul_hi
@nc:    dey
        bne @l
@rts:   rts

; score += A
score_add8:
        clc
        adc score_lo
        sta score_lo
        bcc @rts
        inc score_hi
@rts:   rts

; score += tmp1:tmp0
score_add16:
        clc
        lda score_lo
        adc tmp0
        sta score_lo
        lda score_hi
        adc tmp1
        sta score_hi
        rts

; num_hi:num_lo → dec_buf[0..4] ASCII
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

; A → dec_buf[2..4](3 位)
b2d8:
        sta num_lo
        lda #0
        sta num_hi
        jmp b2d16

; ============================================================================
.segment "RODATA"

palettes:
        ; 背景:0 面板/云白  1 草地  2 跑道  3 天空物(山/云)
        .byte $22,$0F,$2D,$30
        .byte $22,$0F,$09,$29
        .byte $22,$0F,$00,$30
        .byte $22,$02,$11,$30
        ; 精灵:0 飞机/PAPI  1 箭头橙  2 烟灰  3 备用
        .byte $22,$0F,$30,$16
        .byte $22,$0F,$30,$27
        .byte $22,$0F,$2D,$10
        .byte $22,$0F,$30,$27

; 飞行模型(POH 数字)
base_ias:   .byte 0,45,58,70,82,94,104,113,120
pitch_mod:  .byte 25,12,0,<(-20),<(-45)
flap_drag:  .byte 0,5,10,18
stall_spd:  .byte 49,46,43,40
vs_tab:     .byte <(-112),<(-56),0,56,112   ; 半值,物理层 ×2(合计 ×4 补偿 4 倍距离压缩)

; 转弯边界(及 -96 提前量)
turn_bounds:     .word XW_AT, DW_AT, BASE_AT, FIN_AT
turn_bounds_m96: .word XW_AT-96, DW_AT-96, BASE_AT-96, FIN_AT-96

; 航段数据(索引 = leg 0..8)
leg_tgt_ias: .byte 55,74,74,90,73,65,60,0,0
leg_tol:     .byte 99,8,30,8,8,6,99,99,99  ; 侧风段放宽(改平后自然加速)
leg_mode:    .byte 3,0,4,1,2,2,3,3,3       ; 0 爬升 1 平飞 2 下降 3 不评 4 爬升或到高
leg_msg:     .byte M_ROLL,M_UPWIND,M_XWIND,M_DWNWD,M_BASE,M_FINAL,M_FLARE,M_ROLLOUT,M_NONE

tgt_ias_str: .byte "055","074","074","090","073","065","060","---","---"
tgt_alt_str: .byte "0000","0500","1000","1000","0700","0300","0000","----","----"

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

; 着陆分(A/B/C/D)
ldg_score: .word 2000,1200,700,300

; AI 每航段目标油门/襟翼($FF=不动)
;               ROLL UPW  XW  DWN BASE FIN FLARE ROLL DONE
ai_thr_tab:  .byte 8,   8,  8,  5,  3, $FF,  0,   0,  0
ai_flap_tab: .byte 0,   0,  0,  0,  2,  3,   3,   3,  3
; PAPI 修正(索引=红灯数 0..4):偏高→压杆收油,偏低→带杆加油
ai_papi_pitch: .byte 0,1,1,2,3
ai_papi_thr:   .byte 3,3,4,5,6

; HUD 轮转字段跳表
hud_jmp:
        .word hud_f0,hud_f1,hud_f2,hud_f3,hud_f4,hud_f5,hud_f6,hud_f7

; RPM 显示(700+250×thr)
rpm_str: .byte "0700","0950","1200","1450","1700","1950","2200","2450","2700"
flap_str:.byte "00","10","20","30"

; 面板模板(行 1-4,各 32 字符)
panel_row1:
        .byte " IAS 000  ALT 0000  RPM 0000 F00"
        .byte " TGT 055/0000  SC 00000  VS -   "
        .byte "                                "
        .byte " LEG ROLL     G ------  PAPI    "

; 消息(≤30 字符,0 结尾)
msg_lo:
        .byte 0
        .byte <m1,<m2,<m3,<m4,<m5,<m6,<m7,<m8,<m9
        .byte <m10,<m11,<m12,<m13,<m14,<m15,<m16,<m17,<m18,<m19
        .byte <m20,<m21,<m22,<m23
msg_hi:
        .byte 0
        .byte >m1,>m2,>m3,>m4,>m5,>m6,>m7,>m8,>m9
        .byte >m10,>m11,>m12,>m13,>m14,>m15,>m16,>m17,>m18,>m19
        .byte >m20,>m21,>m22,>m23
m1:     .byte "FULL POWER : ROTATE AT 55",0
m2:     .byte "CLIMB AT VY 74",0
m3:     .byte "CROSSWIND : CLIMB TO 1000",0
m4:     .byte "DOWNWIND : LEVEL 1000 , 90 KT",0
m5:     .byte "ABEAM : POWER 3 , FLAPS 10",0
m6:     .byte "BASE : FLAPS 20 , 73 KT",0
m7:     .byte "FINAL : FLAPS 30 , 65 KT",0
m8:     .byte "OVER THE FENCE : EASE BACK",0
m9:     .byte "BRAKE GENTLY < HOLD B >",0
m10:    .byte "TURN LEFT NOW !",0
m11:    .byte "INSTRUCTOR : MY CONTROLS",0
m12:    .byte "STALL ! NOSE DOWN !",0
m13:    .byte "GO AROUND : CLIMB STRAIGHT",0
m14:    .byte "OVERRUN ! BRAKE !",0
m15:    .byte "OFF THE RUNWAY ...",0
m16:    .byte "HARD LANDING ...",0
m17:    .byte "GREASED IT ! WELL DONE !",0
m18:    .byte "AUTOPILOT DEMO : PRESS START",0
m19:    .byte "PAUSED",0
m20:    .byte "FLAPS UP",0
m21:    .byte "FLAPS 10",0
m22:    .byte "FLAPS 20",0
m23:    .byte "FLAPS 30",0

; 标题/讲评文本
str_press: .byte "PRESS START",0
str_sub:   .byte "TRAFFIC PATTERN TRAINER",0
str_poh:   .byte "POH NUMBERS : 55 74 90 65",0
str_demo:  .byte "OR WAIT FOR AUTOPILOT DEMO",0
str_keys:  .byte "A/B POWER  UP/DN PITCH  SEL FLAP",0
str_log:   .byte "FLIGHT LOG",0
str_touch: .byte "TOUCH ",0
str_score: .byte "SCORE ",0
str_r0:    .byte "RATING : CHECKRIDE PASSED !",0
str_r1:    .byte "RATING : READY FOR SOLO",0
str_r2:    .byte "RATING : STUDENT PILOT",0
str_r3:    .byte "RATING : MORE PATTERN WORK",0
str_r_crash: .byte "RATING : SEE THE MECHANIC ...",0

; 箭头精灵瓦片(16x16 → 4 块:TL TR BL BR)
arrow_tiles: .byte $44,$45,$46,$47

; 引擎:周期/音量(thr 0..8;RPM 700..2700 → ~35..135Hz)
eng_per_lo: .byte <2047,<2047,<1864,<1543,<1316,<1147,<1017,<913,<828
eng_per_hi: .byte >2047,>2047,>1864,>1543,>1316,>1147,>1017,>913,>828
eng_vol:    .byte 3,4,5,6,7,8,9,10,11

; 接地闷响周期(12 帧下滑)
thump_per:  .byte $60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0,$FF,$FF,$FF

; 音符表:0 休止 1 C3 2 F3 3 G3 4 C4 5 E4 6 F4 7 G4 8 A4 9 B4
;         10 C5 11 D5 12 E5 13 G5
note_lo: .byte 0,<852,<639,<568,<426,<338,<319,<284,<253,<225,<213,<189,<168,<142
note_hi: .byte 0,>852,>639,>568,>426,>338,>319,>284,>253,>225,>213,>189,>168,>142

; 啁啾序(id…0 结束)
chime_tab:
        .byte 10,12,13,0        ; OK:C5 E5 G5
        .byte 7,5,7,0           ; WARN:G4 E4 G4
        .byte 12,0,0,0          ; BLIP

; 标题曲(id,时值)…$FF 循环
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

; 十进制幂
pow_lo: .byte <10000,<1000,<100,<10
pow_hi: .byte >10000,>1000,>100,>10

; ---------------- 向量 ----------------
.segment "VECTORS"
        .addr nmi
        .addr reset
        .addr irq

; ---------------- CHR ----------------
.segment "CHR"
        .incbin "build/chr.bin"
