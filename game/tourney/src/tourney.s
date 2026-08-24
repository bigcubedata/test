; ============================================================================
; 《比武大会》GRAND TOURNEY —— 骑士长枪比武(NES,NROM)
;
; 玩法:Punch-Out 式对冲读招。B 持盾(举高/放中),A+方向 固枪瞄准
;       (上=盔 2 分/中=胸盾 1 分/下=卑劣的低刺——重创但失德)。
;       固枪时机:太早会被高手看破换盾,贴身则只擦中——沉住气才是骑士。
; 荣誉:开赛致意、饶过断盾之人、扶起坠马对手挣荣誉;低刺、趁人之危失德。
;       荣誉决定加赛裁决、冠军再战权与结局(真骑士/凡冠/空冠)。
; 战役 7 场(各有性情:早固枪/假盾/看破早枪/低刺者)+ 2P 同屏对战。
; ============================================================================

.segment "HEADER"
        .byte "NES", $1A
        .byte 2, 1, $01, $00
        .res 8, $00

; ---------------- 常量 ----------------

PPUCTRL_BASE   = $88            ; NMI 开,BG $0000,SPR $1000

ST_TITLE       = 0
ST_GAME        = 1
ST_INTER       = 2              ; 战役对手卡
ST_END         = 3              ; 结局
ST_HOWTO       = 4              ; 演示前教学卡

PS_READY       = 0
PS_CHARGE      = 1
PS_RIDEOUT     = 2
PS_RESULT      = 3
PS_BOUTEND     = 4
PS_HELP        = 5              ; 扶不扶?
PS_HELPSCENE   = 6
PS_RETRY       = 7

AIM_NONE       = 0
AIM_HIGH       = 1
AIM_MID        = 2
AIM_LOW        = 3

BTN_A          = $01
BTN_B          = $02
BTN_SEL        = $04
BTN_STA        = $08
BTN_UP         = $10
BTN_DN         = $20
BTN_LT         = $40
BTN_RT         = $80

; 赛道几何(精灵中心 x)
X_LEFT         = 28
X_RIGHT        = 228
Y_HORSE        = 128            ; 马精灵顶 y
Y_KNIGHT       = 114
CONTACT_D      = 20             ; 中心距 ≤ 此值触发交锋

; 固枪时机窗口(中心距)
CW_MAX         = 160
CW_EARLY       = 56             ; > 此为早(可被看破)
CW_LATE        = 24             ; < 此为迟(擦枪)

Q_NONE         = 0
Q_GLANCE       = 1
Q_CLEAN        = 2
Q_PERFECT      = 3

SEAT_P         = 12             ; 玩家座力

; 消息 id = 串表下标(S_* 占 0-25,消息从 26 起,与 RODATA 表序一致)
M_READY     = 26
M_BLOCK     = 27
M_BREAST    = 28
M_HELM      = 29
M_GLANCE    = 30
M_LOW       = 31
M_WARN      = 32
M_DQ        = 33
M_UNHORSE   = 34
M_SALUTE    = 35
M_RETSAL    = 36
M_SNAP      = 37
M_MERCY     = 38
M_MERCYHIT  = 39
M_HELPQ     = 40
M_HELPED    = 41
M_NOHELP    = 42
M_WINB      = 43
M_LOSEB     = 44
M_CLEANV    = 45
M_JUDGE     = 46
M_EXTRA     = 47
M_REMATCH   = 48
M_RETRY     = 49
M_DEMO      = 50
M_TIEJ      = 51
M_VSWIN1    = 52
M_VSWIN2    = 53
M_FOEDQ     = 54
S_HAZ       = 55
M_HHIT      = 56

; ---------------- 零页 ----------------
.segment "ZEROPAGE"

nmi_busy:    .res 1
frame:       .res 1
game_state:  .res 1
pad:         .res 1
pad_prev:    .res 1
pad_new:     .res 1
pad2:        .res 1
pad2_prev:   .res 1
pad2_new:    .res 1
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
lfsr:        .res 1
oam_i:       .res 1

fade_mode:   .res 1             ; 0 无 1 变暗 2 变亮
fade_step:   .res 1
fade_t:      .res 1
fade_next:   .res 1             ; 1 标题 2 游戏 3 对手卡 4 结局 5 教学卡

st_t:        .res 1             ; 状态帧计时(低)
st_t_hi:     .res 1
idle_t:      .res 1
idle_t_hi:   .res 1

vs_mode:     .res 1             ; 1 = 2P 对战
demo_on:     .res 1             ; 1 = 演示(双方 AI)
bout_idx:    .res 1             ; 0-6
pass_idx:    .res 1
pass_max:    .res 1             ; 3,平局加赛递增至 5
pass_st:     .res 1
ps_t:        .res 1
msg_t:       .res 1
msg2_t:      .res 1

; 骑手数组[2]:0=玩家/近端蓝,1=对手/红
rx_lo:       .res 2
rx_hi:       .res 2             ; 中心 x(px)
rv_lo:       .res 2
rv_hi:       .res 2
rdir:        .res 2             ; 0 向右 1 向左
raim:        .res 2
rguard:      .res 2             ; 1 高 2 中
rgshow:      .res 2             ; 显示的盾位(假盾用)
rcq:         .res 2
rseat:       .res 2
rseat_max:   .res 2
rscore:      .res 2
rlance:      .res 2             ; 1 有枪(未断)
rshield:     .res 2             ; 1 有盾
rfall:       .res 2             ; >0 坠马动画计时
rsalute:     .res 2
rlow_n:      .res 2
ranim:       .res 2             ; 奔跑相位累加(hi)
ranim_lo:    .res 2
rvmax_lo:    .res 2
rvmax_hi:    .res 2

contact_done:.res 1
saluted:     .res 1             ; 玩家本场已致意
honor:       .res 1
warn_flag:   .res 2             ; 已受裁判警告
dq_who:      .res 1             ; $FF 无,否则 DQ 的骑手号
bout_winner: .res 1             ; $FF 未定
win_by_fall: .res 1
help_choice: .res 1
ev_snap:     .res 1             ; 本回合断盾事件(对手无盾)
ev_mercyok:  .res 1             ; 玩家本回合未击打断盾者
rematch_ok:  .res 1
clean_bout:  .res 1             ; 本场玩家没用过低刺
ai_couch_d:  .res 1
ai_feint:    .res 1
ai_tell_d:   .res 1
p0_ai_cd:    .res 1             ; 演示:0 号 AI 固枪距

; 当前对手参数(从表载入)
opp_aimh:    .res 1
opp_aiml:    .res 1
opp_gdh:     .res 1
opp_tell:    .res 1
opp_feint:   .res 1
opp_react:   .res 1
opp_seat:    .res 1
opp_vlo:     .res 1
opp_vhi:     .res 1
opp_salute:  .res 1
opp_color:   .res 1
opp_event:   .res 1

; 特效
star_t:      .res 1
star_x:      .res 1
star_y:      .res 1
shardA_t:    .res 1
shardA_x:    .res 1
shardA_y:    .res 1
shardB_t:    .res 1
shardB_x:    .res 1
shardB_y:    .res 1
dust_t:      .res 1
dust_x:      .res 1
plumeoff_t:  .res 1
plumeoff_x:  .res 1
plumeoff_y:  .res 1
hud_dirty:   .res 1

; 绘制/结算工作区(与 tmp 隔离)
cur_r:       .res 1             ; 当前骑手号
ms_x:        .res 1             ; 元精灵基准(马左上 x)
ms_y:        .res 1
ms_at:       .res 1             ; 属性(含翻转)
ms_t:        .res 1
ms_i:        .res 1
kny:         .res 1             ; 骑士顶 y
sn_aim0:     .res 1
sn_aim1:     .res 1
sn_g0:       .res 1
sn_g1:       .res 1
sk_aim:      .res 1
sk_grd:      .res 1
sk_shl:      .res 1
sk_pts:      .res 1
sk_dmg:      .res 1
msg_line:    .res 1             ; 0 → 行1,1 → 行2
ai_plan_aim: .res 1

; 声音
mus_on:      .res 1
mus_i1:      .res 1
mus_t1:      .res 1
mus_i2:      .res 1
mus_t2:      .res 1
jg_ptr:      .res 1             ; 铜管一击式乐句(sq1),$FF 空闲
jg_t:        .res 1
sq2_t:       .res 1
tri_t:       .res 1
burst_t:     .res 1
cheer_t:     .res 1
boo_t:       .res 1
gal_prev:    .res 2

; 视觉强化(魂斗罗化)
shake_t:     .res 1             ; 全屏震动余帧
rflash:      .res 2             ; 受击白闪帧
rrecoil:     .res 2             ; 受击后仰帧
shardC_t:    .res 1
shardC_x:    .res 1
shardC_y:    .res 1
shardD_t:    .res 1
shardD_x:    .res 1
shardD_y:    .res 1
hd_t:        .res 3             ; 蹄尘环形槽
hd_x:        .res 3
hd_n:        .res 1
streak_t:    .res 1             ; 完美固枪速度线
streak_x:    .res 1
streak_y:    .res 1
streak_d:    .res 1
pen_t:       .res 1             ; 飘旗计时/相位
pen_ph:      .res 1
ov_t:        .res 1             ; 观众起立浪余帧
scene:       .res 1             ; 0 白日 1 黄昏
att_n:       .res 1             ; 演示轮数(黄昏轮换)
kb0:         .res 1             ; 骑士姿态瓦片基址(上排)
kb1:         .res 1             ; (下排)

.segment "BSS"
ppu_buf:     .res 192
pal_work:    .res 32

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
        lda #$5A
        sta lfsr
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
; NMI:OAM DMA → 缓冲刷写 → 滚动清零 → 逻辑 tick → 声音
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
        lda #PPUCTRL_BASE
        sta $2000
        lda #0
        sta $2005
        ldx shake_t
        beq @shk0
        dec shake_t
        lda shk_tab-1,x
@shk0:  sta $2005
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
@s2:    cmp #ST_INTER
        bne @s3
        jsr tick_inter
        jmp @tickd
@s3:    cmp #ST_END
        bne @s4
        jsr tick_end
        jmp @tickd
@s4:    jsr tick_howto
@tickd:
        jsr fade_tick
        jsr sound_tick
        inc frame
        inc st_t
        bne @nsth
        inc st_t_hi
@nsth:  lda #0
        sta nmi_busy
        pla
        tay
        pla
        tax
        pla
        rti

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
        lda pad2
        sta pad2_prev
        lda #1
        sta $4016
        lda #0
        sta $4016
        ldx #8
@b:     lda $4016
        lsr a
        ror pad
        lda $4017
        lsr a
        ror pad2
        dex
        bne @b
        lda pad_prev
        eor #$FF
        and pad
        sta pad_new
        lda pad2_prev
        eor #$FF
        and pad2
        sta pad2_new
        rts

; 8 位 Galois LFSR
rnd:
        lda lfsr
        lsr a
        bcc @nx
        eor #$B4
@nx:    sta lfsr
        rts

; ============================================================================
; 缓冲写入辅助
; ============================================================================

; 开始一条缓冲记录:A=addr_hi X=addr_lo Y=len。返回 Y=数据起始下标
bput_hdr:
        sty tmp7
        ldy buf_w
        sta ppu_buf,y
        iny
        txa
        sta ppu_buf,y
        iny
        lda tmp7
        sta ppu_buf,y
        iny
        rts

; 收尾:Y=当前下标
bput_end:
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; 缓冲写字符串:A=hi X=lo,ptr=串(0 结尾,≤32)
buf_str:
        sty tmp6
        ldy #0
@len:   lda (ptr_lo),y
        beq @got
        iny
        bne @len
@got:   sty tmp5                ; 长度
        cpy #0
        beq @rts
        lda buf_w
        clc
        adc tmp5
        cmp #150
        bcs @rts                ; 缓冲不够,丢弃(下帧靠 dirty 重试)
        ldy tmp5
        jsr bput_hdr
        sty tmp7
        ldy #0
@cp:    lda (ptr_lo),y
        sta tmp4
        sty tmp6
        ldy tmp7
        lda tmp4
        sta ppu_buf,y
        inc tmp7
        ldy tmp6
        iny
        cpy tmp5
        bne @cp
        ldy tmp7
        jsr bput_end
@rts:   rts

; 缓冲写 2 位十进制:A=值(0-99),tmp2=addr_hi tmp3=addr_lo
buf_num2:
        pha
        ldx #0
        pla
@t:     cmp #10
        bcc @o
        sec
        sbc #10
        inx
        bne @t
@o:     sta tmp4
        txa
        clc
        adc #'0'
        sta tmp5
        lda tmp4
        clc
        adc #'0'
        sta tmp6
        lda tmp2
        ldx tmp3
        ldy #2
        jsr bput_hdr
        lda tmp5
        sta ppu_buf,y
        iny
        lda tmp6
        sta ppu_buf,y
        iny
        jmp bput_end

; ============================================================================
; 直写辅助(渲染关闭时)
; ============================================================================

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

; A=hi X=lo Y=数量 tmp0=瓦片
fill_run:
        jsr set_addr
        lda tmp0
@f:     sta $2007
        dey
        bne @f
        rts

; 串地址装入 ptr:X=串号
str_ptr:
        lda str_lo,x
        sta ptr_lo
        lda str_hi,x
        sta ptr_hi
        rts

; ============================================================================
; 调色板:pal_work 重建(对手色/黑骑士化)+ 淡入淡出
; ============================================================================

pal_rebuild:
        lda scene
        beq @day
        ldx #0
@cpd:   lda pal_dusk,x
        sta pal_work,x
        inx
        cpx #32
        bne @cpd
        beq @tint
@day:   ldx #0
@cp:    lda pal_base,x
        sta pal_work,x
        inx
        cpx #32
        bne @cp
@tint:  ; 对手罩袍色 → sp1 c2($3F15 → pal_work+21)
        lda opp_color
        sta pal_work+21
        ; 玩家失德变暗(荣誉 <20 → 蓝袍转黑)
        lda vs_mode
        ora demo_on
        bne @rts
        lda honor
        cmp #20
        bcs @rts
        lda #$00
        sta pal_work+17
@rts:   rts

; 渲染关闭时整套写入(按 fade_step 暗化)
load_palettes:
        lda #$3F
        ldx #$00
        jsr set_addr
        lda fade_step
        asl a
        asl a
        asl a
        asl a
        sta tmp0
        ldy #0
@p:     lda pal_work,y
        sec
        sbc tmp0
        bcs @ok
        lda #$0F
@ok:    sta $2007
        iny
        cpy #32
        bne @p
        rts

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
        sta fade_mode
        lda fade_next
        cmp #1
        bne @n1
        jmp enter_title
@n1:    cmp #2
        bne @n2
        jmp enter_game
@n2:    cmp #3
        bne @n3
        jmp enter_inter
@n3:    cmp #4
        bne @n4
        jmp enter_end
@n4:    jmp enter_howto

fade_emit:
        lda buf_w
        cmp #150
        bcs @rts
        lda #$3F
        ldx #$00
        ldy #32
        jsr bput_hdr
        sty tmp1
        lda fade_step
        asl a
        asl a
        asl a
        asl a
        sta tmp0
        ldy #0
@l:     lda pal_work,y
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
        jsr bput_end
@rts:   rts

clear_nts:
        lda #$20
        ldx #$00
        jsr set_addr
        ldx #8
        ldy #0
        lda #$00
@c:     sta $2007
        iny
        bne @c
        dex
        bne @c
        rts

ppu_off:
        lda #0
        sta $2001
        rts

ppu_on:
        bit $2002
@w:     bit $2002
        bpl @w
        lda #PPUCTRL_BASE
        sta $2000
        lda #0
        sta $2005
        sta $2005
        lda #$1E
        sta $2001
        rts

oam_clear:
        ldx #0
        lda #$F8
@l:     sta $0200,x
        inx
        inx
        inx
        inx
        bne @l
        lda #0
        sta oam_i
        rts

; 放一个精灵:A=y X=tile Y=attr,tmp0=x
put_spr:
        sty tmp1
        ldy oam_i
        sta $0200,y
        iny
        txa
        sta $0200,y
        iny
        lda tmp1
        sta $0200,y
        iny
        lda tmp0
        sta $0200,y
        iny
        sty oam_i
        rts

; ============================================================================
; 标题
; ============================================================================

enter_title:
        jsr ppu_off
        jsr oam_clear
        jsr clear_nts
        lda #0
        sta vs_mode
        sta demo_on
        sta scene
        sta pen_t
        sta ov_t
        sta shake_t
        sta idle_t
        sta idle_t_hi
        sta st_t
        sta st_t_hi
        sta rdir
        sta ranim
        sta ranim+1
        sta rsalute
        sta rsalute+1
        sta jg_ptr
        lda #$FF
        sta jg_ptr
        lda #1
        sta rdir+1              ; 标题:两骑对望
        lda #$10
        sta opp_color
        jsr pal_rebuild
        jsr load_palettes

        ; 行 0:城堡天际线;行 1:飘旗;行 2:彩旗横幅
        lda #$20
        ldx #$00
        jsr set_addr
        ldy #0
@sky:   tya
        and #$03
        tax
        lda castle_pat,x
        sta $2007
        iny
        cpy #32
        bne @sky
        lda #$20
        ldx #$20
        jsr set_addr
        ldy #0
@pen:   tya
        and #$01
        tax
        lda pen_pat,x
        sta $2007
        iny
        cpy #32
        bne @pen
        lda #$20
        ldx #$40
        ldy #32
        lda #$0B
        sta tmp0
        lda #$20
        jsr fill_run

        ; 「比武大会」16×16 ×4,行 5-6,列 12-19
        lda #$20
        ldx #$AC
        jsr set_addr
        ldx #0
@h1:    lda hanzi_top,x
        sta $2007
        inx
        cpx #8
        bne @h1
        lda #$20
        ldx #$CC
        jsr set_addr
        ldx #0
@h2:    lda hanzi_bot,x
        sta $2007
        inx
        cpx #8
        bne @h2

        ; GRAND TOURNEY(大字 TOURNEY 行 9-10 列 9-22;GRAND 小字行 8)
        lda #$21
        ldx #$0D
        jsr set_addr
        ldx #S_GRAND
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$29
        jsr set_addr
        ldx #0
@t1:    lda big_top,x
        sta $2007
        inx
        cpx #14
        bne @t1
        lda #$21
        ldx #$49
        jsr set_addr
        ldx #0
@t2:    lda big_bot,x
        sta $2007
        inx
        cpx #14
        bne @t2

        ; 菜单与说明
        lda #$21
        ldx #$E8
        jsr set_addr
        ldx #S_MENU1
        jsr str_ptr
        jsr draw_str
        lda #$22
        ldx #$28
        jsr set_addr
        ldx #S_MENU2
        jsr str_ptr
        jsr draw_str
        lda #$22
        ldx #$88
        jsr set_addr
        ldx #S_CTRL1
        jsr str_ptr
        jsr draw_str
        lda #$22
        ldx #$A6
        jsr set_addr
        ldx #S_CTRL2
        jsr str_ptr
        jsr draw_str
        lda #$23
        ldx #$02
        jsr set_addr
        ldx #S_MOTTO
        jsr str_ptr
        jsr draw_str

        ; 属性:整屏 pal0,汉字区 pal3(金),大字区 pal1
        lda #$23
        ldx #$C0
        jsr set_addr
        ldx #64
        lda #$00
@at:    sta $2007
        dex
        bne @at
        lda #$23
        ldx #$CB
        jsr set_addr
        lda #$FF
        sta $2007
        sta $2007
        sta $2007
        sta $2007

        lda #ST_TITLE
        sta game_state
        lda #1
        sta mus_on
        lda #0
        sta mus_i1
        sta mus_i2
        lda #1
        sta mus_t1
        sta mus_t2
        jsr ppu_on
        rts

tick_title:
        ; 标题双骑对望(装饰,置于题字两侧)
        jsr oam_clear
        lda #216
        sta tmp0
        ldx #0
        jsr draw_rider_static
        lda #40
        sta tmp0
        ldx #1
        jsr draw_rider_static
        inc idle_t
        bne @ni
        inc idle_t_hi
@ni:    lda fade_mode
        beq @in
        rts
@in:    lda pad_new
        and #BTN_STA
        beq @nsta
        lda #0
        sta vs_mode
        sta demo_on
        sta bout_idx
        lda #40
        sta honor
        lda #0
        sta rematch_ok
        lda #3
        jsr fade_begin
        jsr sfx_ready
        rts
@nsta:  lda pad_new
        and #BTN_SEL
        beq @nsel
        lda #1
        sta vs_mode
        lda #0
        sta demo_on
        sta bout_idx
        lda #2
        jsr fade_begin
        jsr sfx_ready
        rts
@nsel:  lda idle_t_hi
        cmp #3                  ; ~10 秒 → 演示
        bcc @rts
        lda #5
        jsr fade_begin
@rts:   rts

; 标题装饰骑手:tmp0=中心x X=骑手号(定色/朝向)
draw_rider_static:
        stx cur_r
        lda tmp0
        sta ms_x
        lda #44
        sta ms_y
        jsr horse_draw
        jsr knight_draw
        rts

; ============================================================================
; 教学卡(演示前)
; ============================================================================

enter_howto:
        jsr ppu_off
        jsr oam_clear
        jsr clear_nts
        lda #0
        sta scene
        jsr pal_rebuild
        jsr load_palettes
        lda #$20
        ldx #$C6
        jsr set_addr
        ldx #S_HOW1
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$02
        jsr set_addr
        ldx #S_HOW2
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$41
        jsr set_addr
        ldx #S_HOW3
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$81
        jsr set_addr
        ldx #S_HOW4
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$C1
        jsr set_addr
        ldx #S_HOW5
        jsr str_ptr
        jsr draw_str
        lda #$22
        ldx #$22
        jsr set_addr
        ldx #S_HOW6
        jsr str_ptr
        jsr draw_str
        lda #$22
        ldx #$84
        jsr set_addr
        ldx #S_HOW7
        jsr str_ptr
        jsr draw_str
        lda #$23
        ldx #$C0
        jsr set_addr
        ldx #64
        lda #$00
@at:    sta $2007
        dex
        bne @at
        lda #ST_HOWTO
        sta game_state
        lda #0
        sta st_t
        sta st_t_hi
        sta mus_on
        jsr ppu_on
        rts

tick_howto:
        lda fade_mode
        beq @a
        rts
@a:     lda pad_new
        bne @skip
        lda st_t_hi
        cmp #2                  ; ~8.5 秒
        bcc @rts
@skip:  lda #1
        sta demo_on
        inc att_n               ; 演示轮换(白日/黄昏)
        lda #0
        sta vs_mode
        lda frame
        and #$03
        clc
        adc #2                  ; 演示对手 2-5 号中取
        sta bout_idx
        lda #$5A
        sta lfsr                ; 演示确定性种子
        lda #2
        jsr fade_begin
@rts:   rts

; ============================================================================
; 竞技场 + 开赛
; ============================================================================

enter_game:
        jsr ppu_off
        jsr oam_clear
        jsr clear_nts

        ; 场景:战役后两战黄昏,演示逢双轮黄昏,对战白日
        lda #0
        sta scene
        lda demo_on
        beq @sc_c
        lda att_n
        and #$01
        sta scene
        jmp @sc_d
@sc_c:  lda vs_mode
        bne @sc_d
        lda bout_idx
        cmp #5
        bcc @sc_d
        lda #1
        sta scene
@sc_d:
        ; 载入对手
        jsr load_opp
        jsr pal_rebuild
        jsr load_palettes
        jsr draw_arena
        jsr hud_static

        lda #ST_GAME
        sta game_state
        lda #0
        sta mus_on
        sta pass_idx
        sta saluted
        sta contact_done
        sta win_by_fall
        sta dq_who
        sta ev_snap
        sta ev_mercyok
        sta msg_t
        sta msg2_t
        sta star_t
        sta shardA_t
        sta shardB_t
        sta shardC_t
        sta shardD_t
        sta dust_t
        sta plumeoff_t
        sta hd_t
        sta hd_t+1
        sta hd_t+2
        sta streak_t
        sta ov_t
        sta shake_t
        sta pen_t
        lda #$FF
        sta dq_who
        sta bout_winner
        lda #1
        sta clean_bout
        lda #3
        sta pass_max
        ldx #0
@ri:    lda #0
        sta rscore,x
        sta rlow_n,x
        sta warn_flag,x
        sta rfall,x
        sta rsalute,x
        sta rflash,x
        sta rrecoil,x
        lda rseat_max,x
        sta rseat,x
        inx
        cpx #2
        bne @ri
        jsr pass_setup
        lda demo_on
        beq @nod
        lda #M_DEMO
        jsr msg_show2
@nod:   lda #1
        sta hud_dirty
        jsr ppu_on
        rts

; 每回合初始化(位置/方向/瞄准清空)
pass_setup:
        lda #PS_READY
        sta pass_st
        lda #0
        sta ps_t
        sta contact_done
        ldx #0
@r:     lda #0
        sta raim,x
        sta rcq,x
        sta rv_lo,x
        sta rv_hi,x
        sta ranim,x
        sta ranim_lo,x
        sta rsalute,x
        lda #2
        sta rguard,x
        sta rgshow,x
        lda #1
        sta rlance,x
        sta rshield,x
        inx
        cpx #2
        bne @r
        ; 方向:偶数回合 0 左→右;奇数互换
        lda pass_idx
        and #$01
        beq @even
        ldx #X_RIGHT
        stx rx_hi
        ldx #X_LEFT
        stx rx_hi+1
        lda #1
        sta rdir
        lda #0
        sta rdir+1
        jmp @dirs
@even:  ldx #X_LEFT
        stx rx_hi
        ldx #X_RIGHT
        stx rx_hi+1
        lda #0
        sta rdir
        lda #1
        sta rdir+1
@dirs:  lda #0
        sta rx_lo
        sta rx_lo+1
        ; 断盾事件:战役 2/4 号对手第 2 回合
        lda #0
        sta ev_snap
        lda vs_mode
        ora demo_on
        bne @noev
        lda pass_idx
        cmp #1
        bne @noev
        lda opp_event
        beq @noev
        lda #1
        sta ev_snap
        sta ev_mercyok
        lda #0
        sta rshield+1
        lda #M_SNAP
        jsr msg_show
@noev:  ; AI 本回合计划
        jsr ai_plan
        rts

load_opp:
        lda bout_idx
        asl a
        asl a
        asl a
        asl a                   ; ×16
        tax
        lda opp_tab,x
        sta opp_aimh
        lda opp_tab+1,x
        sta opp_aiml
        lda opp_tab+2,x
        sta opp_gdh
        lda opp_tab+3,x
        sta opp_tell
        lda opp_tab+4,x
        sta opp_feint
        lda opp_tab+5,x
        sta opp_react
        lda opp_tab+6,x
        sta opp_seat
        lda opp_tab+7,x
        sta opp_vlo
        lda opp_tab+8,x
        sta opp_vhi
        lda opp_tab+9,x
        sta opp_salute
        lda opp_tab+10,x
        sta opp_color
        lda opp_tab+11,x
        sta opp_event
        ; 座力/速度
        lda #SEAT_P
        sta rseat_max
        lda opp_seat
        sta rseat_max+1
        lda #$60
        sta rvmax_lo
        lda #$02
        sta rvmax_hi
        lda opp_vlo
        sta rvmax_lo+1
        lda opp_vhi
        sta rvmax_hi+1
        ; 2P:对手=玩家镜像
        lda vs_mode
        beq @rts
        lda #SEAT_P
        sta rseat_max+1
        lda #$60
        sta rvmax_lo+1
        lda #$02
        sta rvmax_hi+1
        lda #$16
        sta opp_color
@rts:   rts

; AI 回合计划:瞄准/持盾/假盾/固枪距
ai_plan:
        jsr rnd
        lda lfsr
        cmp opp_aiml
        bcc @low
        jsr rnd
        lda lfsr
        cmp opp_aimh
        bcc @high
        lda #AIM_MID
        bne @aimd
@low:   ; 已被警告则不再低刺
        lda warn_flag+1
        beq @lowok
        lda #AIM_MID
        bne @aimd
@lowok: lda #AIM_LOW
        bne @aimd
@high:  lda #AIM_HIGH
@aimd:  sta ai_plan_aim         ; 固枪时才生效(那一刻才亮牌)
        ; 盾
        jsr rnd
        lda lfsr
        cmp opp_gdh
        bcc @gh
        lda #2
        bne @gd
@gh:    lda #1
@gd:    sta rguard+1
        sta rgshow+1
        ; 假盾
        lda #0
        sta ai_feint
        jsr rnd
        lda lfsr
        cmp opp_feint
        bcs @nof
        lda #1
        sta ai_feint
        lda rguard+1
        eor #$03                ; 1↔2
        sta rgshow+1
@nof:   ; 固枪距离:tell 附近 ±8
        jsr rnd
        lda lfsr
        and #$0F
        clc
        adc opp_tell
        sta ai_couch_d
        ; 演示:0 号骑手固枪距
        jsr rnd
        lda lfsr
        and #$1F
        clc
        adc #30
        sta p0_ai_cd
        rts

; ---------------- 竞技场静态画面 ----------------

draw_arena:
        ; 行 0:远景城堡天际线(4 瓦片图案循环)
        lda #$20
        ldx #$00
        jsr set_addr
        ldy #0
@sky:   tya
        and #$03
        tax
        lda castle_pat,x
        sta $2007
        iny
        cpy #32
        bne @sky
        ; 行 1:飘旗绳(交替两相)
        lda #$20
        ldx #$20
        jsr set_addr
        ldy #0
@pen:   tya
        and #$01
        tax
        lda pen_pat,x
        sta $2007
        iny
        cpy #32
        bne @pen
        ; 行 2-4:人群(后排暗 + 两排错落)
        lda #$20
        ldx #$40
        ldy #32
        lda #$66
        sta tmp0
        lda #$20
        jsr fill_run
        lda #$20
        ldx #$60
        ldy #32
        lda #$08
        sta tmp0
        lda #$20
        jsr fill_run
        lda #$20
        ldx #$80
        ldy #32
        lda #$09
        sta tmp0
        lda #$20
        jsr fill_run
        ; 王座包厢 行 1-4:条纹华盖 + 帷幔 + 流苏 + 栏杆
        lda #$20
        ldx #$2D
        jsr set_addr
        lda #$0C
        sta $2007
        lda #$02
        sta $2007
        sta $2007
        sta $2007
        sta $2007
        lda #$0D
        sta $2007
        lda #$20
        ldx #$4C
        jsr set_addr
        lda #$67
        sta $2007
        lda #$0E
        sta $2007
        lda #$05
        sta $2007
        sta $2007
        sta $2007
        sta $2007
        lda #$0E
        sta $2007
        lda #$67
        sta $2007
        lda #$20
        ldx #$6C
        jsr set_addr
        lda #$67
        sta $2007
        lda #$0E
        sta $2007
        lda #$00
        sta $2007
        sta $2007
        sta $2007
        sta $2007
        lda #$0E
        sta $2007
        lda #$67
        sta $2007
        lda #$20
        ldx #$8C
        jsr set_addr
        lda #$67
        sta $2007
        ldy #6
        lda #$0F
@rb:    sta $2007
        dey
        bne @rb
        lda #$67
        sta $2007
        ; 行 5-6:木架横梁;行 7:垂旗
        lda #$20
        ldx #$A0
        ldy #32
        lda #$0A
        sta tmp0
        lda #$20
        jsr fill_run
        lda #$20
        ldx #$C0
        ldy #32
        lda #$0A
        sta tmp0
        lda #$20
        jsr fill_run
        lda #$20
        ldx #$E0
        ldy #32
        lda #$0B
        sta tmp0
        lda #$20
        jsr fill_run
        ; 行 8-9:草地;行 10:割草带;行 11:草丛花点
        lda #$21
        ldx #$00
        jsr set_addr
        ldy #64
        lda #$10
@g1:    sta $2007
        dey
        bne @g1
        lda #$21
        ldx #$40
        ldy #32
        lda #$6E
        sta tmp0
        lda #$21
        jsr fill_run
        lda #$21
        ldx #$60
        ldy #32
        lda #$6D
        sta tmp0
        lda #$21
        jsr fill_run
        ; 行 12:草坡沿;行 13-14:远沙亮带;行 15:沙中带
        lda #$21
        ldx #$80
        ldy #32
        lda #$12
        sta tmp0
        lda #$21
        jsr fill_run
        lda #$21
        ldx #$A0
        jsr set_addr
        ldy #64
        lda #$69
@s1:    sta $2007
        dey
        bne @s1
        lda #$21
        ldx #$E0
        ldy #32
        lda #$11
        sta tmp0
        lda #$21
        jsr fill_run
        ; 行 16:耙纹;行 17:蹄痕带(马蹄线)
        lda #$22
        ldx #$00
        ldy #32
        lda #$6C
        sta tmp0
        lda #$22
        jsr fill_run
        lda #$22
        ldx #$20
        ldy #32
        lda #$6B
        sta tmp0
        lda #$22
        jsr fill_run
        ; 行 18-19:tilt 栅栏
        lda #$22
        ldx #$40
        ldy #32
        lda #$14
        sta tmp0
        lda #$22
        jsr fill_run
        lda #$22
        ldx #$60
        ldy #32
        lda #$15
        sta tmp0
        lda #$22
        jsr fill_run
        ; 立柱
        lda #$22
        ldx #$64
        jsr set_addr
        lda #$16
        sta $2007
        lda #$22
        ldx #$6C
        jsr set_addr
        lda #$16
        sta $2007
        lda #$22
        ldx #$74
        jsr set_addr
        lda #$16
        sta $2007
        lda #$22
        ldx #$7C
        jsr set_addr
        lda #$16
        sta $2007
        ; 行 20:栏影→草;行 21:草丛;行 22-23:草
        lda #$22
        ldx #$80
        ldy #32
        lda #$13
        sta tmp0
        lda #$22
        jsr fill_run
        lda #$22
        ldx #$A0
        ldy #32
        lda #$6D
        sta tmp0
        lda #$22
        jsr fill_run
        lda #$22
        ldx #$C0
        ldy #32
        lda #$10
        sta tmp0
        lda #$22
        jsr fill_run
        lda #$22
        ldx #$E0
        ldy #32
        lda #$6D
        sta tmp0
        lda #$22
        jsr fill_run
        ; 行 24:面板顶边;行 25-29:黑
        lda #$23
        ldx #$00
        ldy #32
        lda #$04
        sta tmp0
        lda #$23
        jsr fill_run
        lda #$23
        ldx #$20
        jsr set_addr
        ldx #0
        ldy #160
        lda #$01
@pn:    sta $2007
        dey
        bne @pn
        ; 属性表
        jsr arena_attr
        rts

arena_attr:
        lda #$23
        ldx #$C0
        jsr set_addr
        ldx #0
@a:     lda attr_tab,x
        sta $2007
        inx
        cpx #64
        bne @a
        rts

; HUD 静态标签
hud_static:
        lda #$23
        ldx #$21
        jsr set_addr
        lda vs_mode
        beq @you
        ldx #S_HAZ
        bne @lbl
@you:   ldx #S_HYOU
@lbl:   jsr str_ptr
        jsr draw_str
        ; 对手短名(行 25 右)
        lda vs_mode
        beq @cname
        ldx #S_H2P
        jsr str_ptr
        jmp @nm
@cname: ldx bout_idx
        lda sname_lo,x
        sta ptr_lo
        lda sname_hi,x
        sta ptr_hi
@nm:    lda #$23
        ldx #$37
        jsr set_addr
        jsr draw_str
        ; 行 26 SEAT 标签
        lda #$23
        ldx #$4D
        jsr set_addr
        ldx #S_SEAT
        jsr str_ptr
        jsr draw_str
        ; 行 27 HONOR/PASS
        lda vs_mode
        ora demo_on
        bne @rts
        lda #$23
        ldx #$61
        jsr set_addr
        ldx #S_HONOR
        jsr str_ptr
        jsr draw_str
@rts:   rts

; ============================================================================
; 游戏主 tick
; ============================================================================

tick_game:
        ; 演示中任意键回标题
        lda demo_on
        beq @play
        lda pad_new
        and #BTN_STA|BTN_A|BTN_B|BTN_SEL
        beq @play
        lda fade_mode
        bne @play
        lda #1
        jsr fade_begin
@play:  jsr pass_machine
        jsr riders_move
        jsr fx_tick
        jsr hud_tick
        jsr build_oam
        rts

; ---------------- 回合状态机 ----------------

pass_machine:
        lda fade_mode
        beq @go
        rts                     ; 转场期间冻结(防重复推进)
@go:    lda pass_st
        cmp #PS_READY
        bne @n0
        jmp ps_ready
@n0:    cmp #PS_CHARGE
        bne @n1
        jmp ps_charge
@n1:    cmp #PS_RIDEOUT
        bne @n2
        jmp ps_rideout
@n2:    cmp #PS_RESULT
        bne @n3
        jmp ps_result
@n3:    cmp #PS_BOUTEND
        bne @n4
        jmp ps_boutend
@n4:    cmp #PS_HELP
        bne @n5
        jmp ps_help
@n5:    cmp #PS_HELPSCENE
        bne @n6
        jmp ps_helpscene
@n6:    jmp ps_retry

ps_ready:
        inc ps_t
        lda ps_t
        cmp #1
        bne @nr
        lda #M_READY
        jsr msg_show
@nr:    ; 致意窗口:第一回合按 B
        lda pass_idx
        bne @go
        lda demo_on
        beq @pb
        ; 演示:AI 玩家也致意
        lda ps_t
        cmp #30
        bne @foe
        jsr do_salute
        jmp @foe
@pb:    lda pad_new
        and #BTN_B
        beq @foe
        lda saluted
        bne @foe
        jsr do_salute
@foe:   ; 有礼的对手在 60 帧回礼
        lda ps_t
        cmp #60
        bne @go
        lda saluted
        beq @go
        lda opp_salute
        beq @go
        lda vs_mode
        bne @go
        lda #30
        sta rsalute+1
        lda #M_RETSAL
        jsr msg_show2
@go:    lda ps_t
        cmp #110
        bcc @rts
        lda #PS_CHARGE
        sta pass_st
        lda #0
        sta ps_t
        jsr sfx_charge
@rts:   rts

do_salute:
        lda #1
        sta saluted
        lda #40
        sta rsalute
        lda vs_mode
        ora demo_on
        bne @nomsg
        lda #3
        jsr honor_add
        lda #M_SALUTE
        jsr msg_show
        jsr sfx_salute
        rts
@nomsg: lda #M_SALUTE
        jsr msg_show
        jsr sfx_salute
        rts

ps_charge:
        ; 加速
        ldx #0
        jsr accel_rider
        ldx #1
        jsr accel_rider
        ; 输入/AI
        lda demo_on
        beq @p1h
        jsr ai_player_tick
        jmp @foe
@p1h:   jsr player_input
@foe:   lda vs_mode
        beq @ai
        jsr p2_input
        jmp @coll
@ai:    jsr ai_foe_tick
@coll:  ; 交锋检测
        lda contact_done
        bne @rts
        jsr rider_dist
        cmp #CONTACT_D
        bcs @rts
        jsr resolve_contact
        lda #1
        sta contact_done
        lda #PS_RIDEOUT
        sta pass_st
        lda #0
        sta ps_t
@rts:   rts

accel_rider:
        lda rv_hi,x
        cmp rvmax_hi,x
        bcc @add
        bne @rts
        lda rv_lo,x
        cmp rvmax_lo,x
        bcs @rts
@add:   lda rv_lo,x
        clc
        adc #10
        sta rv_lo,x
        bcc @rts
        inc rv_hi,x
@rts:   rts

; 距离(中心)→ A
rider_dist:
        lda rx_hi
        sec
        sbc rx_hi+1
        bcs @p
        eor #$FF
        clc
        adc #1
@p:     rts

; 玩家输入(骑手 0):B 举盾,A+方向 固枪
player_input:
        lda pad
        and #BTN_B
        beq @gmid
        lda #1
        bne @gset
@gmid:  lda #2
@gset:  sta rguard
        sta rgshow
        lda raim
        bne @rts                ; 已固枪
        lda pad_new
        and #BTN_A
        beq @rts
        jsr rider_dist
        cmp #CW_MAX
        bcs @rts                ; 太远
        sta tmp0
        lda pad
        and #BTN_UP
        beq @ndu
        lda #AIM_HIGH
        bne @aset
@ndu:   lda pad
        and #BTN_DN
        beq @amid
        lda #AIM_LOW
        bne @aset
@amid:  lda #AIM_MID
@aset:  sta raim
        lda tmp0
        jsr couch_quality
        sta rcq
        jsr sfx_couch
        ldx #0
        jsr streak_arm
        ; 高手看破早枪
        lda tmp0
        cmp #CW_EARLY
        bcc @rts
        lda vs_mode
        ora demo_on
        bne @rts
        lda opp_react
        beq @rts
        lda raim
        cmp #AIM_LOW
        beq @rts
        lda raim
        sta rguard+1
        sta rgshow+1
@rts:   rts

; 2P 输入(骑手 1)
p2_input:
        lda pad2
        and #BTN_B
        beq @gmid
        lda #1
        bne @gset
@gmid:  lda #2
@gset:  sta rguard+1
        sta rgshow+1
        lda raim+1
        bne @rts
        lda pad2_new
        and #BTN_A
        beq @rts
        jsr rider_dist
        cmp #CW_MAX
        bcs @rts
        sta tmp0
        lda pad2
        and #BTN_UP
        beq @ndu
        lda #AIM_HIGH
        bne @aset
@ndu:   lda pad2
        and #BTN_DN
        beq @amid
        lda #AIM_LOW
        bne @aset
@amid:  lda #AIM_MID
@aset:  sta raim+1
        lda tmp0
        jsr couch_quality
        sta rcq+1
        jsr sfx_couch
        ldx #1
        jsr streak_arm
@rts:   rts

; A=固枪距 → 品质
couch_quality:
        cmp #CW_LATE
        bcc @late
        cmp #CW_EARLY
        bcc @perf
        lda #Q_CLEAN
        rts
@perf:  lda #Q_PERFECT
        rts
@late:  lda #Q_GLANCE
        rts

; X=骑手号:完美固枪 → 枪尖速度线
streak_arm:
        lda rcq,x
        cmp #Q_PERFECT
        bne @rts
        lda #10
        sta streak_t
        lda rdir,x
        sta streak_d
        ldy raim,x
        lda streak_ytab-1,y
        sta streak_y
        lda rdir,x
        bne @l
        lda rx_hi,x
        clc
        adc #18
        jmp @s
@l:     lda rx_hi,x
        sec
        sbc #18
@s:     sta streak_x
@rts:   rts

; AI(对手,骑手 1)
ai_foe_tick:
        ; 假盾:近了亮出真盾
        lda ai_feint
        beq @couch
        jsr rider_dist
        cmp #44
        bcs @couch
        lda rguard+1
        sta rgshow+1
        lda #0
        sta ai_feint
@couch: lda raim+1
        bne @rts
        jsr rider_dist
        cmp ai_couch_d
        bcs @rts
        sta tmp0
        lda ai_plan_aim
        sta raim+1
        lda tmp0
        jsr couch_quality
        sta rcq+1
        jsr sfx_couch
        ldx #1
        jsr streak_arm
@rts:   rts

; 演示:骑手 0 由 AI 操控(稳健流:读对手盾,反着打)
ai_player_tick:
        lda raim
        bne @guard
        jsr rider_dist
        cmp p0_ai_cd
        bcs @guard
        sta tmp0
        ; 反盾瞄准:对手盾高→打中,盾中→打盔
        lda rgshow+1
        cmp #1
        beq @mid
        lda #AIM_HIGH
        bne @set
@mid:   lda #AIM_MID
@set:   sta raim
        lda tmp0
        jsr couch_quality
        sta rcq
        jsr sfx_couch
        ldx #0
        jsr streak_arm
@guard: ; 对手已固枪则对位举盾
        lda raim+1
        beq @rts
        lda raim+1
        cmp #AIM_HIGH
        bne @gm
        lda #1
        sta rguard
        sta rgshow
        rts
@gm:    lda #2
        sta rguard
        sta rgshow
@rts:   rts

; ---------------- 交锋结算 ----------------

resolve_contact:
        ; 快照双方参数(strike 内会改守方状态,须用快照)
        lda raim
        sta sn_aim0
        lda raim+1
        sta sn_aim1
        lda rguard
        sta sn_g0
        lda rguard+1
        sta sn_g1
        ; 特效:交锋点(先定位,坠马落点用)
        lda rx_hi
        clc
        adc rx_hi+1
        ror a
        sta star_x
        lda #Y_KNIGHT+6
        sta star_y
        ; 0 打 1
        ldx #0
        lda sn_aim0
        sta sk_aim
        lda sn_g1
        sta sk_grd
        lda rshield+1
        sta sk_shl
        jsr strike
        ; 1 打 0
        ldx #1
        lda sn_aim1
        sta sk_aim
        lda sn_g0
        sta sk_grd
        lda rshield
        sta sk_shl
        jsr strike
        ; 有交手才有星与响
        lda sn_aim0
        ora sn_aim1
        beq @quiet
        lda #12
        sta star_t
        jsr sfx_impact
@quiet: ; 断盾回合:玩家没打 → 骑士风度
        lda ev_snap
        beq @rts
        lda sn_aim0
        bne @hit
        lda ev_mercyok
        beq @rts
        lda #0
        sta ev_mercyok
        lda #6
        jsr honor_add
        lda #M_MERCY
        jsr msg_show
        jsr cheer_big
        rts
@hit:   lda #0
        sta ev_mercyok
        lda vs_mode
        ora demo_on
        bne @rts
        lda #4
        jsr honor_sub
        lda #M_MERCYHIT
        jsr msg_show2
@rts:   rts

; 消息按攻方分行:X=0 → 行1,X=1 → 行2(保 X/Y)
msg_auto:
        sta tmp0
        txa
        pha
        tya
        pha
        cpx #0
        bne @l2
        lda tmp0
        jsr msg_show
        jmp @out
@l2:    lda tmp0
        jsr msg_show2
@out:   pla
        tay
        pla
        tax
        rts

; 一方打击:X=攻方号,sk_aim/sk_grd(守方盾位)/sk_shl(守方有盾)
; 守方号 = X^1
strike:
        lda sk_aim
        bne @has
        rts                     ; 未固枪
@has:   lda rlance,x
        bne @lance_ok
        rts
@lance_ok:
        txa
        eor #$01
        tay                     ; Y=守方
        lda sk_aim
        cmp #AIM_LOW
        bne @notlow
        ; —— 低刺:不设防,重创,失德 ——
        lda #0
        sta sk_pts
        lda #8
        sta sk_dmg
        inc rlow_n,x
        cpx #0
        bne @lowmsg
        lda vs_mode
        ora demo_on
        bne @lowmsg
        lda #8
        jsr honor_sub           ; 破坏 X/Y;本分支恒 X=0 Y=1,重装
        ldx #0
        ldy #1
        lda #0
        sta clean_bout
@lowmsg:
        lda #M_LOW
        jsr msg_auto
        jsr boo_start
        jsr lance_break
        ; 裁判:警告/取消资格
        lda rlow_n,x
        cmp #2
        bcc @warn1
        stx dq_who
        jmp @dmg
@warn1: lda warn_flag,x
        bne @dmg
        lda #1
        sta warn_flag,x
        txa
        pha
        tya
        pha
        lda #M_WARN
        jsr msg_show2
        pla
        tay
        pla
        tax
        jmp @dmg
@notlow:
        ; 盾防:守方有盾且瞄准=盾位 → 断枪于盾
        lda sk_shl
        beq @open
        lda sk_aim
        cmp sk_grd
        bne @open
        lda #1
        sta sk_pts
        lda #2
        sta sk_dmg
        lda #M_BLOCK
        jsr msg_auto
        jsr lance_break
        jmp @dmg
@open:  lda sk_aim
        cmp #AIM_HIGH
        bne @breast
        lda #2
        sta sk_pts
        lda #6
        sta sk_dmg
        lda #M_HELM
        jsr msg_auto
        jsr plume_fly
        jsr lance_break
        jsr sfx_clang
        lda #6
        sta shake_t
        jmp @dmg
@breast:
        lda #1
        sta sk_pts
        lda #4
        sta sk_dmg
        lda #M_BREAST
        jsr msg_auto
        jsr lance_break
@dmg:   ; 品质修正
        lda rcq,x
        cmp #Q_GLANCE
        bne @nq1
        lsr sk_pts
        lsr sk_dmg
        lda #M_GLANCE
        jsr msg_auto
@nq1:   lda rcq,x
        cmp #Q_PERFECT
        bne @nq2
        inc sk_dmg
        inc sk_dmg
@nq2:   ; 记分与伤
        lda rscore,x
        clc
        adc sk_pts
        sta rscore,x
        ; 守方受击白闪 + 后仰
        lda #8
        sta rflash,y
        lda #14
        sta rrecoil,y
        lda rseat,y
        sec
        sbc sk_dmg
        beq @fall
        bcs @seatok
@fall:  lda #0
        sta rseat,y
        lda #90
        sta rfall,y
        lda #16
        sta shake_t
        ; 低刺致坠 = 击马犯规,攻方取消资格;否则光明正大的坠马胜
        lda sk_aim
        cmp #AIM_LOW
        bne @fair
        stx dq_who
        txa
        pha
        tya
        pha
        lda #M_HHIT
        jsr msg_show
        jsr sfx_fall
        pla
        tay
        pla
        tax
        jmp @dust
@fair:  stx bout_winner
        lda #1
        sta win_by_fall
        txa
        pha
        tya
        pha
        lda #M_UNHORSE
        jsr msg_show
        jsr sfx_fall
        pla
        tay
        pla
        tax
@dust:  lda rx_hi,y
        sta dust_x
        lda #60
        sta dust_t
        jmp @done
@seatok:
        sta rseat,y
@done:  lda #1
        sta hud_dirty
        rts

lance_break:
        lda #0
        sta rlance,x
        ; 断枪四屑:抛物弧四向飞散
        lda rx_hi,x
        sta shardA_x
        sta shardC_x
        clc
        adc #8
        sta shardB_x
        sta shardD_x
        lda #Y_KNIGHT+4
        sta shardA_y
        sta shardB_y
        lda #Y_KNIGHT
        sta shardC_y
        sta shardD_y
        lda #14
        sta shardA_t
        lda #13
        sta shardB_t
        lda #12
        sta shardC_t
        lda #10
        sta shardD_t
        rts

plume_fly:
        lda rx_hi,y
        sta plumeoff_x
        lda #Y_KNIGHT-8
        sta plumeoff_y
        lda #50
        sta plumeoff_t
        rts

; ---------------- 冲过 → 结果 ----------------

ps_rideout:
        inc ps_t
        ; 两骑减速滑行到端点
        ldx #0
        jsr coast_rider
        ldx #1
        jsr coast_rider
        lda ps_t
        cmp #120
        bcc @rts
        lda #PS_RESULT
        sta pass_st
        lda #0
        sta ps_t
        jsr eval_pass_end
@rts:   rts

coast_rider:
        ; 到端点急减速
        lda rdir,x
        bne @left
        lda rx_hi,x
        cmp #X_RIGHT
        bcc @keep
        jmp @stop
@left:  lda rx_hi,x
        cmp #X_LEFT+1
        bcs @keep
@stop:  lda #0
        sta rv_lo,x
        sta rv_hi,x
        rts
@keep:  rts

; 回合终点判定:坠马/DQ/回合数
eval_pass_end:
        lda dq_who
        cmp #$FF
        bne @dq
        lda bout_winner
        cmp #$FF
        bne @fall
        inc pass_idx
        lda pass_idx
        cmp pass_max
        bcc @next
        ; 回合打满:比点
        lda rscore
        cmp rscore+1
        beq @tie
        bcs @p0w
        lda #1
        sta bout_winner
        bne @endb
@p0w:   lda #0
        sta bout_winner
        beq @endb
@tie:   ; 平局:加赛至 5 回合,再平按荣誉裁决
        lda pass_max
        cmp #5
        bcs @judge
        inc pass_max
        lda #M_EXTRA
        jsr msg_show
        jsr sfx_ready
        jmp @next
@judge: lda #M_TIEJ
        jsr msg_show
        lda vs_mode
        bne @j2p
        lda honor
        cmp #50
        bcs @jw
        lda #1
        sta bout_winner
        bne @endb
@jw:    lda #0
        sta bout_winner
        beq @endb
@j2p:   ; 2P 平局:低刺少者胜
        lda rlow_n
        cmp rlow_n+1
        bcc @jw
        lda #1
        sta bout_winner
        bne @endb
@dq:    ; DQ:对方胜
        lda dq_who
        eor #$01
        sta bout_winner
        lda #M_DQ
        jsr msg_show
        jmp @endb
@fall:
@endb:  lda bout_winner
        cmp #$FF
        bne @tobend
@next:  jsr pass_setup
        rts
@tobend:
        lda #PS_BOUTEND
        sta pass_st
        lda #0
        sta ps_t
        jsr bout_end_begin
        rts

ps_result:
        ; (占位:结果并入 rideout 后直接进下一回合/终局)
        lda #PS_READY
        sta pass_st
        rts

; ---------------- 场终 ----------------

bout_end_begin:
        lda #1
        sta hud_dirty
        lda bout_winner
        bne @lose
        ; 玩家胜
        lda vs_mode
        beq @w1p
        lda #M_VSWIN1
        jsr msg_show
        jsr jingle_win
        jsr cheer_big
        rts
@w1p:   lda #M_WINB
        jsr msg_show
        jsr jingle_win
        jsr cheer_big
        lda vs_mode
        ora demo_on
        bne @rts
        lda #2
        jsr honor_add
        ; 干净击败黑棘
        lda bout_idx
        cmp #3
        bne @rts
        lda clean_bout
        beq @rts
        lda #10
        jsr honor_add
        lda #M_CLEANV
        jsr msg_show2
@rts:   rts
@lose:  lda vs_mode
        beq @l1p
        lda #M_VSWIN2
        jsr msg_show
        jsr jingle_win
        rts
@l1p:   lda #M_LOSEB
        jsr msg_show
        jsr jingle_lose
        rts

ps_boutend:
        inc ps_t
        lda ps_t
        cmp #200
        bcc @rts
        ; 2P/演示 → 回标题
        lda vs_mode
        beq @nvs
        lda pad_new
        and #BTN_STA|BTN_A
        beq @vsb
        lda #2
        jsr fade_begin          ; 再战
        rts
@vsb:   lda pad_new
        and #BTN_B
        beq @rts
        lda #1
        jsr fade_begin          ; 回标题
        rts
@nvs:   lda demo_on
        beq @camp
        lda #1
        jsr fade_begin
        rts
@camp:  lda bout_winner
        bne @loss
        ; 胜:坠马胜且非低刺致胜 → 扶人抉择
        lda win_by_fall
        beq @adv
        lda #PS_HELP
        sta pass_st
        lda #0
        sta ps_t
        lda #M_HELPQ
        jsr msg_show
        rts
@adv:   jsr advance_bout
        rts
@loss:  ; 负:冠军场高荣誉可再战
        lda bout_idx
        cmp #6
        bne @retry
        lda honor
        cmp #60
        bcc @retry
        lda rematch_ok
        bne @retry
        lda #1
        sta rematch_ok
        lda #M_REMATCH
        jsr msg_show
        lda #PS_RETRY
        sta pass_st
        lda #0
        sta ps_t
        rts
@retry: lda #M_RETRY
        jsr msg_show
        lda #PS_RETRY
        sta pass_st
        lda #0
        sta ps_t
@rts:   rts

advance_bout:
        inc bout_idx
        lda bout_idx
        cmp #7
        bcc @inter
        lda #4
        jsr fade_begin          ; 通关 → 结局
        rts
@inter: lda #3
        jsr fade_begin
        rts

ps_help:
        inc ps_t
        lda pad_new
        and #BTN_A
        beq @nb
        ; 扶
        lda #1
        sta help_choice
        lda #5
        jsr honor_add
        lda #M_HELPED
        jsr msg_show
        jsr cheer_big
        lda #PS_HELPSCENE
        sta pass_st
        lda #0
        sta ps_t
        rts
@nb:    lda pad_new
        and #BTN_B
        beq @rts
        lda #0
        sta help_choice
        lda #M_NOHELP
        jsr msg_show
        lda #PS_HELPSCENE
        sta pass_st
        lda #0
        sta ps_t
@rts:   rts

ps_helpscene:
        inc ps_t
        lda ps_t
        cmp #170
        bcc @rts
        jsr advance_bout
@rts:   rts

ps_retry:
        inc ps_t
        lda ps_t
        cmp #40
        bcc @rts
        lda pad_new
        and #BTN_A|BTN_STA
        beq @nb
        lda #2
        jsr fade_begin          ; 重赛本场
        rts
@nb:    lda pad_new
        and #BTN_B
        beq @rts
        lda #1
        jsr fade_begin
@rts:   rts

; ---------------- 移动与动画 ----------------

riders_move:
        lda pass_st
        cmp #PS_CHARGE
        beq @mv
        cmp #PS_RIDEOUT
        beq @mv
        rts
@mv:    ldx #0
        jsr move_one
        ldx #1
        jsr move_one
        rts

move_one:
        lda rdir,x
        bne @left
        lda rx_lo,x
        clc
        adc rv_lo,x
        sta rx_lo,x
        lda rx_hi,x
        adc rv_hi,x
        cmp #X_RIGHT
        bcc @str
        lda #X_RIGHT
@str:   sta rx_hi,x
        jmp @anim
@left:  lda rx_lo,x
        sec
        sbc rv_lo,x
        sta rx_lo,x
        lda rx_hi,x
        sbc rv_hi,x
        cmp #X_LEFT
        bcs @stl
        lda #X_LEFT
@stl:   sta rx_hi,x
@anim:  ; 奔跑相位 & 马蹄声
        lda ranim_lo,x
        clc
        adc rv_lo,x
        sta ranim_lo,x
        lda ranim,x
        adc rv_hi,x
        sta ranim,x
        lda ranim,x
        lsr a
        lsr a
        lsr a
        and #$01
        cmp gal_prev,x
        beq @rts
        sta gal_prev,x
        jsr sfx_hoof
@rts:   rts

; ---------------- 特效 tick ----------------

fx_tick:
        lda star_t
        beq @sh
        dec star_t
@sh:    lda shardA_t
        beq @sb
        dec shardA_t
        lda shardA_t
        cmp #9
        bcc @saDn
        dec shardA_y
        jmp @saX
@saDn:  inc shardA_y
        inc shardA_y
@saX:   dec shardA_x
@sb:    lda shardB_t
        beq @sc
        dec shardB_t
        lda shardB_t
        cmp #9
        bcc @sbDn
        dec shardB_y
        jmp @sbX
@sbDn:  inc shardB_y
        inc shardB_y
@sbX:   inc shardB_x
        inc shardB_x
@sc:    lda shardC_t
        beq @sd
        dec shardC_t
        lda shardC_t
        cmp #6
        bcc @scDn
        dec shardC_y
        dec shardC_y
        jmp @scX
@scDn:  inc shardC_y
@scX:   dec shardC_x
        dec shardC_x
@sd:    lda shardD_t
        beq @du
        dec shardD_t
        lda shardD_t
        cmp #6
        bcc @sdDn
        dec shardD_y
        dec shardD_y
        jmp @sdX
@sdDn:  inc shardD_y
@sdX:   inc shardD_x
        inc shardD_x
        inc shardD_x
@du:    lda dust_t
        beq @pl
        dec dust_t
@pl:    lda plumeoff_t
        beq @fl
        dec plumeoff_t
        dec plumeoff_y
        inc plumeoff_x
@fl:    ldx #0
@floop: lda rfall,x
        beq @nf
        dec rfall,x
@nf:    lda rsalute,x
        beq @n2
        dec rsalute,x
@n2:    lda rflash,x
        beq @n3
        dec rflash,x
@n3:    lda rrecoil,x
        beq @nx
        dec rrecoil,x
@nx:    inx
        cpx #2
        bne @floop
        lda streak_t
        beq @st_d
        dec streak_t
@st_d:  ldx #2
@hdd:   lda hd_t,x
        beq @hdd_n
        dec hd_t,x
@hdd_n: dex
        bpl @hdd
        ; 蹄尘生成:冲锋中每 8 帧一朵(双骑错开)
        lda pass_st
        cmp #PS_CHARGE
        bne @nhsp
        lda frame
        and #$07
        bne @h1
        ldx #0
        beq @hsp
@h1:    cmp #$04
        bne @nhsp
        ldx #1
@hsp:   lda rv_hi,x
        beq @nhsp
        stx tmp3
        ldy hd_n
        iny
        cpy #3
        bcc @hn
        ldy #0
@hn:    sty hd_n
        ldx tmp3
        lda rdir,x
        bne @hL
        lda rx_hi,x
        sec
        sbc #12
        jmp @hx
@hL:    lda rx_hi,x
        clc
        adc #12
@hx:    ldy hd_n
        sta hd_x,y
        lda #8
        sta hd_t,y
@nhsp:
        ; 飘旗:游戏/标题下每 32 帧换相
        lda fade_mode
        bne @pen_d
        lda game_state
        cmp #ST_GAME
        beq @pen_g
        cmp #ST_TITLE
        bne @pen_d
@pen_g: inc pen_t
        lda pen_t
        and #$1F
        bne @pen_d
        lda buf_w
        cmp #110
        bcs @pen_d
        lda pen_ph
        eor #$01
        sta pen_ph
        jsr pen_rows_emit
@pen_d:
        ; 观众起立浪(大欢呼:举臂两行,浪毕恢复)
        lda ov_t
        beq @ov_d
        lda game_state
        cmp #ST_GAME
        beq @ov_g
        lda #0
        sta ov_t
        beq @ov_d
@ov_g:  dec ov_t
        lda ov_t
        cmp #118
        bne @o2
        lda #$65
        ldx #0
        jsr crowd_row_emit
        jmp @ov_d
@o2:    cmp #116
        bne @o3
        lda #$65
        ldx #1
        jsr crowd_row_emit
        jmp @ov_d
@o3:    cmp #4
        bne @o4
        lda #$08
        ldx #0
        jsr crowd_row_emit
        jmp @ov_d
@o4:    cmp #2
        bne @ov_d
        lda #$09
        ldx #1
        jsr crowd_row_emit
@ov_d:  rts

; 飘旗行重写:两段(跳过包厢列 13-18)
pen_rows_emit:
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda #$20
        sta ppu_buf,y
        iny
        lda #13
        sta ppu_buf,y
        iny
        ldx #0
@p1:    txa
        clc
        adc pen_ph
        and #$01
        stx tmp4
        tax
        lda pen_pat,x
        ldx tmp4
        sta ppu_buf,y
        iny
        inx
        cpx #13
        bne @p1
        lda #$20
        sta ppu_buf,y
        iny
        lda #$33
        sta ppu_buf,y
        iny
        lda #13
        sta ppu_buf,y
        iny
        ldx #0
@p2:    txa
        clc
        adc pen_ph
        and #$01
        stx tmp4
        tax
        lda pen_pat,x
        ldx tmp4
        sta ppu_buf,y
        iny
        inx
        cpx #13
        bne @p2
        lda #$FF
        sta ppu_buf,y
        sty buf_w
        rts

; A=瓦片 X=0(行3)/1(行4):人群行两段重写(跳过包厢列 12-19)
crowd_row_emit:
        sta tmp4
        stx tmp5
        lda buf_w
        cmp #110
        bcs @rts
        ldy buf_w
        lda #$20
        sta ppu_buf,y
        iny
        lda tmp5
        beq @r3a
        lda #$80
        bne @r3b
@r3a:   lda #$60
@r3b:   sta ppu_buf,y
        iny
        lda #12
        sta ppu_buf,y
        iny
        ldx #12
@f1:    lda tmp4
        sta ppu_buf,y
        iny
        dex
        bne @f1
        lda #$20
        sta ppu_buf,y
        iny
        lda tmp5
        beq @r4a
        lda #$94
        bne @r4b
@r4a:   lda #$74
@r4b:   sta ppu_buf,y
        iny
        lda #12
        sta ppu_buf,y
        iny
        ldx #12
@f2:    lda tmp4
        sta ppu_buf,y
        iny
        dex
        bne @f2
        lda #$FF
        sta ppu_buf,y
        sty buf_w
@rts:   rts

; ============================================================================
; HUD
; ============================================================================

hud_tick:
        ; 消息计时
        lda msg_t
        beq @m2
        dec msg_t
        bne @m2
        jsr msg_clear
@m2:    lda msg2_t
        beq @hd
        dec msg2_t
        bne @hd
        jsr msg2_clear
@hd:    lda hud_dirty
        beq @rts
        lda buf_w
        cmp #90
        bcs @rts                ; 缓冲紧张下帧再画
        lda #0
        sta hud_dirty
        jsr hud_scores
        jsr hud_seats
        jsr hud_honor
@rts:   rts

hud_scores:
        ; 行 25:比分 "P 05   PASS 2/3   05 F"
        lda #$23
        sta tmp2
        lda #$25
        sta tmp3
        lda rscore
        jsr buf_num2
        lda #$23
        sta tmp2
        lda #$33
        sta tmp3
        lda rscore+1
        jsr buf_num2
        ; PASS n/m(行 25 中)
        lda buf_w
        clc
        adc #8
        cmp #180
        bcs @rts
        lda #$23
        ldx #$2C
        ldy #5
        jsr bput_hdr
        lda #'P'
        sta ppu_buf,y
        iny
        lda pass_idx
        clc
        adc #'1'
        cmp #'0'+9
        bcc @pn
        lda #'!'
@pn:    sta ppu_buf,y
        iny
        lda #'/'
        sta ppu_buf,y
        iny
        lda pass_max
        clc
        adc #'0'
        sta ppu_buf,y
        iny
        lda #' '
        sta ppu_buf,y
        iny
        jsr bput_end
@rts:   rts

hud_seats:
        ; 行 26:两条 8 格座力条
        lda #$23
        ldx #$41
        ldy #8
        jsr bput_hdr
        ldx #0
        stx tmp5
@b1:    lda tmp5
        asl a                   ; 格值 = i*2 <? seat
        cmp rseat
        bcs @e1
        lda #$1B
        bne @w1
@e1:    lda #$1A
@w1:    sta ppu_buf,y
        iny
        inc tmp5
        lda tmp5
        cmp #8
        bne @b1
        jsr bput_end
        ; 对手
        lda #$23
        ldx #$57
        ldy #8
        jsr bput_hdr
        ldx #0
        stx tmp5
@b2:    lda tmp5
        asl a
        cmp rseat+1
        bcs @e2
        lda #$1B
        bne @w2
@e2:    lda #$1A
@w2:    sta ppu_buf,y
        iny
        inc tmp5
        lda tmp5
        cmp #8
        bne @b2
        jsr bput_end
        rts

hud_honor:
        lda vs_mode
        ora demo_on
        beq @go
        rts
@go:    ; 行 27:10 面三角旗 = honor/10
        lda #$23
        ldx #$68
        ldy #10
        jsr bput_hdr
        lda honor
        lsr a
        lsr a
        lsr a
        adc #0                  ; ≈ /10 → /8 近似再截 10
        cmp #11
        bcc @k
        lda #10
@k:     sta tmp5
        ldx #0
@h:     cpx tmp5
        bcs @dim
        lda #$1C
        bne @w
@dim:   lda #$1D
@w:     sta ppu_buf,y
        iny
        inx
        cpx #10
        bne @h
        jsr bput_end
        rts

honor_add:
        clc
        adc honor
        cmp #100
        bcc @s
        lda #99
@s:     sta honor
        lda #1
        sta hud_dirty
        jsr pal_rebuild
        jsr fade_emit_now
        rts

honor_sub:
        sta tmp0
        lda honor
        sec
        sbc tmp0
        bcs @s
        lda #0
@s:     sta honor
        lda #1
        sta hud_dirty
        jsr pal_rebuild
        jsr fade_emit_now
        rts

; 立即按当前 fade_step 重发调色板(荣誉变色用)
fade_emit_now:
        lda fade_mode
        bne @rts                ; 转场中勿扰
        jmp fade_emit
@rts:   rts

; ---------------- 消息行 ----------------

msg_show:
        pha
        lda #$23
        sta tmp2
        lda #$82
        sta tmp3
        pla
        jsr msg_draw
        lda #160
        sta msg_t
        rts

msg_show2:
        pha
        lda #$23
        sta tmp2
        lda #$A2
        sta tmp3
        pla
        jsr msg_draw
        lda #160
        sta msg2_t
        rts

; A=串号 → 居中写 28 格
msg_draw:
        tax
        jsr str_ptr
        ; 长度
        ldy #0
@l:     lda (ptr_lo),y
        beq @got
        iny
        bne @l
@got:   sty tmp5
        lda buf_w
        clc
        adc #32
        cmp #155
        bcs @rts
        lda tmp2
        ldx tmp3
        ldy #28
        jsr bput_hdr
        ; 前空格
        lda #28
        sec
        sbc tmp5
        lsr a
        sta tmp6                ; 左空
        ldx #0
@sp1:   cpx tmp6
        bcs @body
        lda #' '
        sta ppu_buf,y
        iny
        inx
        bne @sp1
@body:  sty tmp7
        ldy #0
@cp:    cpy tmp5
        bcs @sp2
        lda (ptr_lo),y
        sty tmp4
        ldy tmp7
        sta ppu_buf,y
        inc tmp7
        ldy tmp4
        iny
        bne @cp
@sp2:   ; 尾空格补满 28
        txa
        clc
        adc tmp5
        tax
        ldy tmp7
@sp2l:  cpx #28
        bcs @end
        lda #' '
        sta ppu_buf,y
        iny
        inx
        bne @sp2l
@end:   jsr bput_end
@rts:   rts

msg_clear:
        lda buf_w
        cmp #150
        bcs @rts
        lda #$23
        ldx #$82
        ldy #28
        jsr bput_hdr
        ldx #28
        lda #' '
@l:     sta ppu_buf,y
        iny
        dex
        bne @l
        jsr bput_end
@rts:   rts

msg2_clear:
        lda buf_w
        cmp #150
        bcs @rts
        lda #$23
        ldx #$A2
        ldy #28
        jsr bput_hdr
        ldx #28
        lda #' '
@l:     sta ppu_buf,y
        iny
        dex
        bne @l
        jsr bput_end
@rts:   rts

; ============================================================================
; OAM 组装
; ============================================================================

build_oam:
        jsr oam_clear
        ; 帮扶场景单独画
        lda pass_st
        cmp #PS_HELPSCENE
        bne @riders
        jmp helpscene_oam
@riders:
        ; 近(0)后画先?低下标在上层:玩家在上
        ldx #0
        jsr draw_rider
        ldx #1
        jsr draw_rider
        ; 特效:交锋爆裂(16×16 三帧:白芯→尖环→火花)
        lda star_t
        beq @sh
        cmp #9
        bcc @b2
        lda #$4A
        bne @bgo
@b2:    cmp #5
        bcc @b3
        lda #$4C
        bne @bgo
@b3:    lda #$4E
@bgo:   sta ms_t
        lda star_x
        sec
        sbc #8
        sta tmp0
        lda star_y
        sec
        sbc #8
        sta tmp2
        ldx ms_t
        ldy #$03
        lda tmp2
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx ms_t
        inx
        ldy #$03
        lda tmp2
        jsr put_spr
        lda tmp0
        sec
        sbc #8
        sta tmp0
        lda ms_t
        clc
        adc #$10
        sta ms_t
        tax
        ldy #$03
        lda tmp2
        clc
        adc #8
        sta tmp2
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx ms_t
        inx
        ldy #$03
        lda tmp2
        jsr put_spr
@sh:    lda shardA_t
        beq @sb
        lda shardA_x
        sta tmp0
        lda shardA_y
        ldx #$0F
        ldy #$03
        jsr put_spr
@sb:    lda shardB_t
        beq @sc
        lda shardB_x
        sta tmp0
        lda shardB_y
        ldx #$1B
        ldy #$03
        jsr put_spr
@sc:    lda shardC_t
        beq @sd
        lda shardC_x
        sta tmp0
        lda shardC_y
        ldx #$0F
        ldy #$43
        jsr put_spr
@sd:    lda shardD_t
        beq @du
        lda shardD_x
        sta tmp0
        lda shardD_y
        ldx #$1B
        ldy #$43
        jsr put_spr
@du:    lda dust_t
        beq @pl
        lda dust_x
        sta tmp0
        lda dust_t
        and #$08
        bne @d2
        ldx #$1C
        bne @dgo
@d2:    ldx #$1D
@dgo:   lda #Y_HORSE+8
        ldy #$03
        jsr put_spr
        ; 蹄下扬尘(三槽)
@hd:    ldx #2
@hdl:   stx tmp3
        lda hd_t,x
        beq @hdn
        lda hd_x,x
        sta tmp0
        ldx tmp3
        lda hd_t,x
        cmp #5
        bcs @hda
        ldx #$3D
        bne @hdt
@hda:   ldx #$3C
@hdt:   ldy #$02
        lda #Y_HORSE+9
        jsr put_spr
@hdn:   ldx tmp3
        dex
        bpl @hdl
        ; 完美固枪速度线(枪尖拖尾两段)
        lda streak_t
        beq @str_n
        lda streak_x
        sta tmp0
        lda streak_y
        ldx #$3E
        ldy #$03
        jsr put_spr
        lda streak_d
        beq @str_r
        lda streak_x
        clc
        adc #8
        jmp @str_s
@str_r: lda streak_x
        sec
        sbc #8
@str_s: sta tmp0
        lda streak_y
        ldx #$3E
        ldy #$03
        jsr put_spr
@str_n:
@pl:    lda plumeoff_t
        beq @roy
        lda plumeoff_x
        sta tmp0
        lda plumeoff_y
        ldx #$0E
        ldy #$01
        jsr put_spr
@roy:   ; 王座:国王+贵妇
        lda #122
        sta tmp0
        lda #19
        ldx #$38
        ldy #$03
        jsr put_spr
        lda #138
        sta tmp0
        lda #19
        ldx #$37
        ldy #$01
        jsr put_spr
        rts

; 画骑手 X(0/1):马+骑士+枪盾;坠马时空马奔+骑士翻滚
draw_rider:
        stx cur_r
        lda rx_hi,x
        sta ms_x
        lda #Y_HORSE
        sta ms_y
        lda rfall,x
        beq @norm
        jmp draw_fallen
@norm:  jsr horse_draw
        jsr knight_draw
        jsr gear_draw
        rts

; —— 马 6 块(3×2)。ms_x=中心 ms_y=顶。向左时列序镜像+每块 H 翻 ——
horse_draw:
        ldx cur_r
        lda ranim,x
        lsr a
        lsr a
        and #$03
        tay
        lda hframe_tab,y
        sta ms_t
        lda rdir,x
        beq @fr
        lda #$42
        bne @fat
@fr:    lda #$02
@fat:   sta ms_at
        lda rflash,x
        beq @nfl
        lda ms_at
        ora #$03
        sta ms_at
@nfl:
        lda #0
        sta ms_i
@loop:  lda ms_i
        cmp #3
        bcc @r0
        sec
        sbc #3
        sta tmp0                ; 列
        lda #1
        bne @rr
@r0:    sta tmp0
        lda #0
@rr:    sta tmp1                ; 行
        ldx cur_r
        lda rdir,x
        beq @xr
        lda #2
        sec
        sbc tmp0
        jmp @xm
@xr:    lda tmp0
@xm:    asl a
        asl a
        asl a
        clc
        adc ms_x
        sec
        sbc #12
        sta tmp2                ; 屏幕 x
        lda tmp1
        beq @t0
        lda ms_t
        clc
        adc #$10
        jmp @t1
@t0:    lda ms_t
@t1:    clc
        adc tmp0
        tax                     ; tile
        lda tmp1
        beq @y0
        lda ms_y
        clc
        adc #8
        jmp @y1
@y0:    lda ms_y
@y1:    sta tmp3
        lda tmp2
        sta tmp0
        lda tmp3
        ldy ms_at
        jsr put_spr
        inc ms_i
        lda ms_i
        cmp #6
        bne @loop
        rts

; —— 骑士 4 块(2×2),kny = ms_y-14 ——
knight_draw:
        ldx cur_r
        lda ms_y
        sec
        sbc #14
        sta kny
        cpx #0
        bne @c1
        lda #$00
        beq @c2
@c1:    lda #$01
@c2:    sta ms_at
        ; 受击后仰姿态 + 白闪
        lda rrecoil,x
        beq @kb_n
        lda #$48
        bne @kb_s
@kb_n:  lda #$08
@kb_s:  sta kb0
        ora #$10
        sta kb1
        lda rflash,x
        beq @kf_n
        lda ms_at
        ora #$03
        sta ms_at
@kf_n:
        lda rdir,x
        beq @right
        lda ms_at
        ora #$40
        sta ms_at
        ; 向左:躯干中心-6,列序镜像($09 左 $08 右)
        lda ms_x
        sec
        sbc #6
        sta ms_t
        lda ms_t
        sta tmp0
        lda kny
        ldx kb0
        inx
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        ldx kb0
        ldy ms_at
        jsr put_spr
        lda ms_t
        sta tmp0
        lda kny
        clc
        adc #8
        ldx kb1
        inx
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        clc
        adc #8
        ldx kb1
        ldy ms_at
        jsr put_spr
        rts
@right: lda ms_x
        sec
        sbc #10
        sta ms_t
        lda ms_t
        sta tmp0
        lda kny
        ldx kb0
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        ldx kb0
        inx
        ldy ms_at
        jsr put_spr
        lda ms_t
        sta tmp0
        lda kny
        clc
        adc #8
        ldx kb1
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        clc
        adc #8
        ldx kb1
        inx
        ldy ms_at
        jsr put_spr
        rts

; —— 羽饰/盾/枪(用 knight_draw 留下的 ms_at/kny)——
gear_draw:
        ldx cur_r
        ; 羽饰:盔顶随风向后飘
        lda rdir,x
        beq @pr
        lda ms_x
        clc
        adc #2
        jmp @ps
@pr:    lda ms_x
        sec
        sbc #10
@ps:    sta tmp0
        lda kny
        sec
        sbc #5
        ldx #$0E
        ldy ms_at
        jsr put_spr
        ; 盾:前侧,位置=显示盾位
        ldx cur_r
        lda rdir,x
        beq @sr
        lda ms_x
        sec
        sbc #14
        jmp @ss
@sr:    lda ms_x
        clc
        adc #6
@ss:    sta tmp0
        lda rgshow,x
        cmp #1
        beq @shi
        lda kny
        clc
        adc #8
        jmp @sy
@shi:   lda kny
        clc
        adc #2
@sy:    ldx #$0D
        ldy ms_at
        jsr put_spr
        ; 枪
        ldx cur_r
        lda rsalute,x
        beq @nosal
        ; 致意:竖枪高举
        jsr lance_vx
        lda kny
        sec
        sbc #14
        ldx #$0A
        ldy ms_at
        jsr put_spr
        jsr lance_vx
        lda kny
        sec
        sbc #6
        ldx #$1A
        ldy ms_at
        jsr put_spr
        rts
@nosal: ldx cur_r
        lda raim,x
        bne @couched
        ; 休枪:竖持
        jsr lance_vx
        lda kny
        sec
        sbc #4
        ldx #$0A
        ldy ms_at
        jsr put_spr
        jsr lance_vx
        lda kny
        clc
        adc #4
        ldx #$1A
        ldy ms_at
        jsr put_spr
        rts
@couched:
        cmp #AIM_HIGH
        bne @c1
        lda kny
        clc
        adc #2
        jmp @cy
@c1:    cmp #AIM_MID
        bne @c2
        lda kny
        clc
        adc #8
        jmp @cy
@c2:    lda kny
        clc
        adc #16
@cy:    sta ms_t                ; 枪线 y
        ldx cur_r
        lda rdir,x
        beq @hr
        ; 向左:尖在最左
        lda ms_x
        sec
        sbc #22
        sta tmp0
        lda ms_t
        ldx #$0C
        ldy ms_at
        jsr put_spr
        lda ms_x
        sec
        sbc #14
        sta tmp0
        lda ms_t
        ldx #$0B
        ldy ms_at
        jsr put_spr
        rts
@hr:    lda ms_x
        clc
        adc #6
        sta tmp0
        lda ms_t
        ldx #$0B
        ldy ms_at
        jsr put_spr
        lda ms_x
        clc
        adc #14
        sta tmp0
        lda ms_t
        ldx #$0C
        ldy ms_at
        jsr put_spr
        rts

; 竖枪 x → tmp0(向右+4 / 向左-12)
lance_vx:
        ldx cur_r
        lda rdir,x
        beq @r
        lda ms_x
        sec
        sbc #12
        sta tmp0
        rts
@r:     lda ms_x
        clc
        adc #4
        sta tmp0
        rts

; 坠马:空马继续跑 + 骑士在交锋点翻滚落地
draw_fallen:
        jsr horse_draw
        ldx cur_r
        lda #90
        sec
        sbc rfall,x
        lsr a
        cmp #24
        bcc @dy
        lda #24
@dy:    sta ms_t                ; 下落量
        cpx #0
        bne @a1
        lda #$00
        beq @a2
@a1:    lda #$01
@a2:    sta ms_at
        lda rfall,x
        and #$04
        beq @nf
        lda ms_at
        ora #$C0
        sta ms_at
@nf:    lda #Y_KNIGHT
        clc
        adc ms_t
        sta kny
        lda star_x
        sec
        sbc #8
        sta ms_t                ; 左 x
        lda ms_t
        sta tmp0
        lda kny
        ldx #$20
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        ldx #$21
        ldy ms_at
        jsr put_spr
        lda ms_t
        sta tmp0
        lda kny
        clc
        adc #8
        ldx #$30
        ldy ms_at
        jsr put_spr
        lda ms_t
        clc
        adc #8
        sta tmp0
        lda kny
        clc
        adc #8
        ldx #$31
        ldy ms_at
        jsr put_spr
        rts

helpscene_oam:
        ; 胜者立于坠者旁
        lda star_x
        sec
        sbc #20
        sta tmp0
        lda #Y_KNIGHT
        sta tmp2
        ; 站立骑士 2×3
        ldx #$22
        lda tmp2
        ldy #$00
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx #$23
        lda tmp2
        ldy #$00
        jsr put_spr
        lda tmp0
        sec
        sbc #8
        sta tmp0
        ldx #$32
        lda tmp2
        clc
        adc #8
        ldy #$00
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx #$33
        lda tmp2
        clc
        adc #8
        ldy #$00
        jsr put_spr
        lda tmp0
        sec
        sbc #8
        sta tmp0
        ldx #$42
        lda tmp2
        clc
        adc #16
        ldy #$00
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx #$43
        lda tmp2
        clc
        adc #16
        ldy #$00
        jsr put_spr
        ; 坠地对手
        lda star_x
        clc
        adc #6
        sta tmp0
        ldx #$24
        lda #Y_KNIGHT+8
        ldy #$01
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx #$25
        lda #Y_KNIGHT+8
        ldy #$01
        jsr put_spr
        lda star_x
        clc
        adc #6
        sta tmp0
        ldx #$34
        lda #Y_KNIGHT+16
        ldy #$01
        jsr put_spr
        lda tmp0
        clc
        adc #8
        sta tmp0
        ldx #$35
        lda #Y_KNIGHT+16
        ldy #$01
        jsr put_spr
        rts

; ============================================================================
; 对手卡 / 结局
; ============================================================================

enter_inter:
        jsr ppu_off
        jsr oam_clear
        jsr clear_nts
        ; 战报卡随下一战场景着色(后两战黄昏)
        lda #0
        sta scene
        lda vs_mode
        ora demo_on
        bne @sc_d
        lda bout_idx
        cmp #5
        bcc @sc_d
        lda #1
        sta scene
@sc_d:  jsr load_opp
        jsr pal_rebuild
        jsr load_palettes
        ; BOUT n
        lda #$20
        ldx #$CB
        jsr set_addr
        ldx #S_BOUT
        jsr str_ptr
        jsr draw_str
        lda bout_idx
        clc
        adc #'1'
        sta $2007
        lda #' '
        sta $2007
        lda #'/'
        sta $2007
        lda #' '
        sta $2007
        lda #'7'
        sta $2007
        ; 名字(行 9 中)
        ldx bout_idx
        lda name_lo,x
        sta ptr_lo
        lda name_hi,x
        sta ptr_hi
        lda #$21
        ldx #$2B
        jsr set_addr
        jsr draw_str
        ; 绰号(行 12)
        ldx bout_idx
        lda epi_lo,x
        sta ptr_lo
        lda epi_hi,x
        sta ptr_hi
        lda #$21
        ldx #$83
        jsr set_addr
        jsr draw_str
        ; 荣誉(行 16)
        lda #$22
        ldx #$0A
        jsr set_addr
        ldx #S_HONOR
        jsr str_ptr
        jsr draw_str
        lda #' '
        sta $2007
        lda honor
        jsr dec2_direct
        ; PRESS START(行 20)
        lda #$22
        ldx #$8A
        jsr set_addr
        ldx #S_PRESS
        jsr str_ptr
        jsr draw_str
        ; 属性全 pal0
        lda #$23
        ldx #$C0
        jsr set_addr
        ldx #64
        lda #$00
@at:    sta $2007
        dex
        bne @at
        lda #ST_INTER
        sta game_state
        lda #0
        sta st_t
        sta st_t_hi
        jsr ppu_on
        rts

; A=0-99 直写两位
dec2_direct:
        ldx #0
@t:     cmp #10
        bcc @o
        sec
        sbc #10
        inx
        bne @t
@o:     sta tmp4
        txa
        clc
        adc #'0'
        sta $2007
        lda tmp4
        clc
        adc #'0'
        sta $2007
        rts

tick_inter:
        jsr oam_clear
        lda fade_mode
        beq @in
        rts
@in:    lda pad_new
        and #BTN_STA|BTN_A
        beq @rts
        lda #2
        jsr fade_begin
        jsr sfx_ready
@rts:   rts

enter_end:
        jsr ppu_off
        jsr oam_clear
        jsr clear_nts
        jsr pal_rebuild
        jsr load_palettes
        lda #$20
        ldx #$C9
        jsr set_addr
        ldx #S_CHAMP
        jsr str_ptr
        jsr draw_str
        ; 按荣誉分支
        lda honor
        cmp #60
        bcc @mid
        ldx #S_END_T1
        stx tmp5
        ldx #S_END_T2
        stx tmp6
        jmp @wr
@mid:   cmp #20
        bcc @low
        ldx #S_END_N1
        stx tmp5
        ldx #S_END_N2
        stx tmp6
        jmp @wr
@low:   ldx #S_END_H1
        stx tmp5
        ldx #S_END_H2
        stx tmp6
@wr:    lda #$21
        ldx #$44
        jsr set_addr
        ldx tmp5
        jsr str_ptr
        jsr draw_str
        lda #$21
        ldx #$C4
        jsr set_addr
        ldx tmp6
        jsr str_ptr
        jsr draw_str
        ; 荣誉数值
        lda #$22
        ldx #$4B
        jsr set_addr
        ldx #S_HONOR
        jsr str_ptr
        jsr draw_str
        lda #' '
        sta $2007
        lda honor
        jsr dec2_direct
        lda #$22
        ldx #$CA
        jsr set_addr
        ldx #S_PRESS
        jsr str_ptr
        jsr draw_str
        lda #$23
        ldx #$C0
        jsr set_addr
        ldx #64
        lda #$00
@at:    sta $2007
        dex
        bne @at
        lda #ST_END
        sta game_state
        lda #0
        sta st_t
        sta st_t_hi
        jsr jingle_win
        jsr ppu_on
        rts

tick_end:
        jsr oam_clear
        ; 王冠精灵一枚
        lda #124
        sta tmp0
        lda #56
        ldx #$2E
        ldy #$03
        jsr put_spr
        lda fade_mode
        beq @in
        rts
@in:    lda pad_new
        and #BTN_STA
        beq @rts
        lda #1
        jsr fade_begin
@rts:   rts

; ============================================================================
; 音效 / 音乐
; ============================================================================

sfx_hoof:
        ; 马蹄:短噪声(速度越快越响)
        lda burst_t
        bne @rts
        lda rv_hi,x
        ora #$30
        sta $400C
        lda #$09
        sta $400E
        lda #$08
        sta $400F
@rts:   rts

sfx_couch:
        lda #6
        sta sq2_t
        lda #$86
        sta $4004
        lda #<340
        sta $4006
        lda #>340
        ora #$08
        sta $4007
        rts

sfx_clang:
        lda #10
        sta sq2_t
        lda #$8A
        sta $4004
        lda #<120
        sta $4006
        lda #>120
        ora #$08
        sta $4007
        rts

sfx_impact:
        lda #10
        sta burst_t
        lda #10
        sta tri_t
        jsr cheer_small
        rts

sfx_fall:
        lda #14
        sta burst_t
        lda #12
        sta tri_t
        rts

sfx_charge:
        jsr jingle_charge
        lda #40
        sta cheer_t
        rts

sfx_ready:
        lda #8
        sta sq2_t
        lda #$88
        sta $4004
        lda #<190
        sta $4006
        lda #>190
        ora #$08
        sta $4007
        rts

sfx_salute:
        jsr jingle_salute
        rts

cheer_small:
        lda cheer_t
        cmp #40
        bcs @rts
        lda #50
        sta cheer_t
@rts:   rts

cheer_big:
        lda #110
        sta cheer_t
        lda #120
        sta ov_t                ; 观众起立浪
        rts

boo_start:
        lda #90
        sta boo_t
        rts

jingle_win:
        lda #JG_WIN
        sta jg_ptr
        lda #1
        sta jg_t
        rts

jingle_lose:
        lda #JG_LOSE
        sta jg_ptr
        lda #1
        sta jg_t
        rts

jingle_salute:
        lda #JG_SAL
        sta jg_ptr
        lda #1
        sta jg_t
        rts

jingle_charge:
        lda #JG_CHG
        sta jg_ptr
        lda #1
        sta jg_t
        rts

sound_tick:
        ; --- sq1:标题音乐 or 一击乐句 ---
        lda mus_on
        beq @jg
        jmp music_tick
@jg:    lda jg_ptr
        cmp #$FF
        beq @sq1off
        dec jg_t
        bne @sq2
        ldx jg_ptr
        lda jingles,x
        bne @jnote
        ; 段尾
        lda #$FF
        sta jg_ptr
        lda #$B0
        sta $4000
        jmp @sq2
@jnote: tax
        lda note_lo,x
        sta $4002
        lda note_hi,x
        ora #$08
        sta $4003
        lda #$B8
        sta $4000
        ldx jg_ptr
        lda jingles+1,x
        sta jg_t
        inx
        inx
        stx jg_ptr
        jmp @sq2
@sq1off:
        lda #$30
        sta $4000
@sq2:   ; --- sq2:短促效果自灭 ---
        lda sq2_t
        beq @sq2off
        dec sq2_t
        bne @tri
@sq2off:
        lda #$30
        sta $4004
@tri:   ; --- 三角:闷响 ---
        lda tri_t
        beq @trioff
        dec tri_t
        lda #$FF
        sta $4008
        lda #12
        sec
        sbc tri_t
        tax
        lda thump_per,x
        sta $400A
        lda #$09
        sta $400B
        jmp @noise
@trioff:
        lda #$80
        sta $4008
@noise: ; --- 噪声优先级:撞击 > 嘘声 > 欢呼 ---
        lda burst_t
        beq @boo
        dec burst_t
        lda burst_t
        lsr a
        ora #$30
        sta $400C
        lda #$0C
        sta $400E
        rts
@boo:   lda boo_t
        beq @cheer
        dec boo_t
        lda boo_t
        lsr a
        lsr a
        lsr a
        and #$03
        clc
        adc #1
        ora #$30
        sta $400C
        lda #$0E
        sta $400E
        rts
@cheer: lda cheer_t
        beq @nq
        dec cheer_t
        lda cheer_t
        lsr a
        lsr a
        lsr a
        cmp #6
        bcc @cv
        lda #6
@cv:    ora #$30
        sta $400C
        lda #$03
        sta $400E
        rts
@nq:    lda #$30
        sta $400C
        rts

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
        ora #$08
        sta $4003
        lda #$B6
        sta $4000
        bne @m2
@r1:    lda #$B0
        sta $4000
@m2:    dec mus_t2
        bne @rest
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
        ora #$08
        sta $4007
        lda #$74
        sta $4004
        bne @rest
@r2:    lda #$30
        sta $4004
@rest:  ; 标题三角低音跟 sq2 根音、噪声关
        lda #$30
        sta $400C
        lda #$80
        sta $4008
        rts

; ============================================================================
.segment "RODATA"

pal_base:
        ; BG:0 面板/字 1 看台 2 草地 3 沙地/栅栏/王座
        .byte $22,$0F,$16,$30
        .byte $22,$0F,$27,$16
        .byte $22,$0F,$19,$29
        .byte $22,$0F,$27,$37
        ; SPR:0 玩家蓝 1 对手(c2 动态) 2 马 3 金效果
        .byte $22,$0F,$12,$30
        .byte $22,$0F,$16,$30
        .byte $22,$0F,$17,$27
        .byte $22,$0F,$28,$30

pal_dusk:
        ; 黄昏决赛:橙天/暖沙/长影
        .byte $26,$0F,$16,$30
        .byte $26,$0F,$27,$06
        .byte $26,$0F,$08,$18
        .byte $26,$0F,$17,$27
        .byte $26,$0F,$12,$30
        .byte $26,$0F,$16,$30
        .byte $26,$0F,$07,$17
        .byte $26,$0F,$28,$30

; 城堡天际线图案 / 飘旗两相 / 震动衰减表 / 奔跑四相帧基址
castle_pat: .byte $61,$60,$61,$62
pen_pat:    .byte $63,$64
shk_tab:    .byte 1,255,1,255,2,254,2,254,3,253,3,253,2,254,3,253
hframe_tab: .byte $00,$04,$40,$44
streak_ytab:.byte Y_KNIGHT+2,Y_KNIGHT+7,Y_KNIGHT+13

; 属性表 64 字节(每字节 2×2 瓦片象限,4 列/字节)
attr_tab:
        ; 行 0-3:看台 pal1;包厢列 12-19(字节 3-4)→ pal3
        .byte $55,$55,$55,$FF,$FF,$55,$55,$55
        ; 行 4-7:看台下沿 pal1;包厢栏杆(行 4-5 列 12-19)上象限 pal3
        .byte $55,$55,$55,$5F,$5F,$55,$55,$55
        ; 行 8-11:草地 pal2
        .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
        ; 行 12-15:沙地 pal3(沙褐/米白)
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        ; 行 16-19:沙 + 栅栏,全 pal3
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        ; 行 20-23:草 pal2
        .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
        ; 行 24-29:面板 pal0
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00

; 大字 TOURNEY(上排/下排瓦片号)
big_top: .byte $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD
big_bot: .byte $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD
hanzi_top: .byte $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7
hanzi_bot: .byte $F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7

; 对手表:aimh,aiml,gdh,tell,feint,react,seat,vlo,vhi,salute,color,event + pad
opp_tab:
        .byte 60,  0,100,110,  0,0, 8,$10,$02,1,$27,0, 0,0,0,0  ; SIR STRAW
        .byte 70,  0,170, 88,  0,0,10,$30,$02,1,$17,0, 0,0,0,0  ; SIR BRONZE
        .byte 150, 0, 90, 68,  0,0,10,$50,$02,1,$1A,1, 0,0,0,0  ; GREEN GALLANT
        .byte 60, 90, 80, 48, 40,0,11,$60,$02,0,$00,0, 0,0,0,0  ; BLACK THORN
        .byte 120, 0,128, 60,120,1,10,$70,$02,1,$10,1, 0,0,0,0  ; LADY SILVER
        .byte 110,20,128, 52, 60,1,13,$80,$02,1,$2D,0, 0,0,0,0  ; IRON COUNT
        .byte 130, 0,128, 40,150,1,14,$98,$02,1,$28,0, 0,0,0,0  ; CHAMPION

; 名字/绰号
n0: .byte "SIR STRAW",0
n1: .byte "SIR BRONZE",0
n2: .byte "GREEN GALLANT",0
n3: .byte "BLACK THORN",0
n4: .byte "LADY SILVER",0
n5: .byte "IRON COUNT",0
n6: .byte "KINGS CHAMPION",0
name_lo: .byte <n0,<n1,<n2,<n3,<n4,<n5,<n6
name_hi: .byte >n0,>n1,>n2,>n3,>n4,>n5,>n6
e0: .byte "SLOW OF ARM, HONEST OF HEART",0
e1: .byte "HIS SHIELD RIDES HIGH",0
e2: .byte "AIMS FOR THE HELM",0
e3: .byte "HE STRIKES LOW AND LAUGHS",0
e4: .byte "SHE READS AN EARLY LANCE",0
e5: .byte "AN IRON SEAT, A COLD EYE",0
e6: .byte "PERFECTION OR NOTHING",0
epi_lo: .byte <e0,<e1,<e2,<e3,<e4,<e5,<e6
epi_hi: .byte >e0,>e1,>e2,>e3,>e4,>e5,>e6
; HUD 短名(≤8)
sn0: .byte "STRAW",0
sn1: .byte "BRONZE",0
sn2: .byte "GALLANT",0
sn3: .byte "THORN",0
sn4: .byte "SILVER",0
sn5: .byte "IRON",0
sn6: .byte "CHAMPION",0
sname_lo: .byte <sn0,<sn1,<sn2,<sn3,<sn4,<sn5,<sn6
sname_hi: .byte >sn0,>sn1,>sn2,>sn3,>sn4,>sn5,>sn6

; 串表
S_GRAND  = 0
S_MENU1  = 1
S_MENU2  = 2
S_CTRL1  = 3
S_CTRL2  = 4
S_MOTTO  = 5
S_HYOU   = 6
S_SEAT   = 7
S_HONOR  = 8
S_PRESS  = 9
S_BOUT   = 10
S_CHAMP  = 11
S_END_T1 = 12
S_END_T2 = 13
S_END_N1 = 14
S_END_N2 = 15
S_END_H1 = 16
S_END_H2 = 17
S_H2P    = 18
S_HOW1   = 19
S_HOW2   = 20
S_HOW3   = 21
S_HOW4   = 22
S_HOW5   = 23
S_HOW6   = 24
S_HOW7   = 25
; 之后接消息 id(M_* 从 26 起映射)
SM_BASE  = 26

s00: .byte "GRAND",0
s01: .byte "START : CAMPAIGN",0
s02: .byte "SELECT: 2P VERSUS",0
s03: .byte "B HOLD SHIELD HIGH",0
s04: .byte "A + UP/DN COUCH THE LANCE",0
s05: .byte "STRIKE LOW, LOSE YOUR HONOR",0
s06: .byte "YOU",0
s07: .byte "SEAT",0
s08: .byte "HONOR",0
s09: .byte "PRESS START",0
s10: .byte "BOUT ",0
s11: .byte "THE CROWN IS YOURS",0
s12: .byte "A TRUE KNIGHT, CROWNED IN",0
s13: .byte "HONOR. THE LADY SMILES.",0
s14: .byte "A CHAMPION BY THE LANCE.",0
s15: .byte "THE CROWD IS SATISFIED.",0
s16: .byte "THE CROWN WEIGHS COLD ON",0
s17: .byte "A KNIGHT WITHOUT HONOR.",0
s18: .byte "CRIMSON",0
s19: .byte "THE ART OF THE JOUST",0
s20: .byte "READ HIS SHIELD. STRIKE PAST",0
s21: .byte "HELM 2 PTS  BREAST 1  BLOCK 1",0
s22: .byte "COUCH LATE FOR A PERFECT BLOW",0
s23: .byte "TOO EARLY AND HE WILL READ YOU",0
s24: .byte "PRESS B AT THE START: SALUTE",0
s25: .byte "WATCH THE DEMONSTRATION",0
; 消息
m01: .byte "READY YOUR LANCE",0
m02: .byte "LANCE BREAKS ON SHIELD",0
m03: .byte "A HIT UPON THE BREAST",0
m04: .byte "CLEAN STRIKE ON THE HELM",0
m05: .byte "A GLANCING BLOW",0
m06: .byte "A COWARDS BLOW! BOOS RAIN",0
m07: .byte "HERALD: ONCE MORE, FORFEIT",0
m08: .byte "FORFEIT! DISHONOR",0
m09: .byte "UNHORSED!",0
m10: .byte "YOU SALUTE THE CROWD",0
m11: .byte "THE SALUTE IS RETURNED",0
m12: .byte "HIS SHIELD STRAP SNAPS!",0
m13: .byte "COURTESY! THE CROWD ROARS",0
m14: .byte "HE WAS UNSHIELDED...",0
m15: .byte "HELP HIM UP? A:AYE B:NAY",0
m16: .byte "A KNIGHT INDEED!",0
m17: .byte "THE CROWD MURMURS...",0
m18: .byte "THE BOUT IS YOURS",0
m19: .byte "THE BOUT IS LOST",0
m20: .byte "CLEAN LANCE BEATS A CHEAT +10",0
m21: .byte "JUDGES WEIGH THE RIDERS...",0
m22: .byte "AN EXTRA PASS!",0
m23: .byte "THE CROWD DEMANDS ANOTHER!",0
m24: .byte "AGAIN? A:AYE B:WITHDRAW",0
m25: .byte "DEMONSTRATION",0
m26: .byte "HONOR TIPS THE SCALES",0
m27: .byte "SIR AZURE TAKES THE BOUT",0
m28: .byte "SIR CRIMSON TAKES THE BOUT",0
m29: .byte "HIS CONDUCT FORFEITS ALL",0
saz: .byte "AZURE",0
mhh: .byte "A BLOW TO THE HORSE! FORFEIT",0

str_lo:
        .byte <s00,<s01,<s02,<s03,<s04,<s05,<s06,<s07,<s08,<s09
        .byte <s10,<s11,<s12,<s13,<s14,<s15,<s16,<s17,<s18,<s19
        .byte <s20,<s21,<s22,<s23,<s24,<s25
        .byte <m01,<m02,<m03,<m04,<m05,<m06,<m07,<m08,<m09,<m10
        .byte <m11,<m12,<m13,<m14,<m15,<m16,<m17,<m18,<m19,<m20
        .byte <m21,<m22,<m23,<m24,<m25,<m26,<m27,<m28,<m29,<saz,<mhh
str_hi:
        .byte >s00,>s01,>s02,>s03,>s04,>s05,>s06,>s07,>s08,>s09
        .byte >s10,>s11,>s12,>s13,>s14,>s15,>s16,>s17,>s18,>s19
        .byte >s20,>s21,>s22,>s23,>s24,>s25
        .byte >m01,>m02,>m03,>m04,>m05,>m06,>m07,>m08,>m09,>m10
        .byte >m11,>m12,>m13,>m14,>m15,>m16,>m17,>m18,>m19,>m20
        .byte >m21,>m22,>m23,>m24,>m25,>m26,>m27,>m28,>m29,>saz,>mhh

; 音符表(1 起):C3 F3 G3 C4 E4 F4 G4 A4 B4 C5 D5 E5 G5 D4 B3 A3
note_lo: .byte 0,<852,<639,<568,<426,<338,<319,<284,<253,<225,<213,<189,<168,<142,<380,<452,<508
note_hi: .byte 0,>852,>639,>568,>426,>338,>319,>284,>253,>225,>213,>189,>168,>142,>380,>452,>508

thump_per:  .byte $60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0,$FF,$FF,$FF

; 标题乐:纹章号角风
mus_sq1:
        .byte 4,9, 4,3, 4,9, 4,3, 7,18, 5,6
        .byte 7,9, 7,3, 7,9, 7,3, 10,18, 8,6
        .byte 12,9,12,3, 10,9, 8,3, 7,18, 5,6
        .byte 4,9, 5,3, 7,9, 9,3, 10,30, 0,6
        .byte $FF
mus_sq2:
        .byte 1,24, 3,24, 4,24, 1,24
        .byte 3,24, 16,24, 1,36, 3,12
        .byte $FF

; 一击乐句(idx→jingles 表偏移,0 结尾)
jingles:
jg_w:   .byte 4,5, 7,5, 10,5, 13,15, 0                  ; 胜
jg_l:   .byte 7,8, 6,8, 5,8, 1,18, 0                    ; 负
jg_s:   .byte 7,4, 7,4, 10,12, 0                        ; 致意
jg_c:   .byte 3,5, 3,3, 4,14, 0                         ; 冲锋号
JG_WIN  = jg_w - jingles
JG_LOSE = jg_l - jingles
JG_SAL  = jg_s - jingles
JG_CHG  = jg_c - jingles

.segment "VECTORS"
        .word nmi
        .word reset
        .word irq

.segment "CHR"
        .incbin "build/chr.bin"
