; =============================================================================
; NES DISPLAY MODULE
; PPU-based text rendering
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Clear screen
; -----------------------------------------------------------------------------
.proc display_clear
    lda PPU_STATUS          ; Reset latch
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    lda #$00                ; Space character
    ldx #$00
    ldy #$04                ; 4 x 256 = 1024 bytes
:   sta PPU_DATA
    inx
    bne :-
    dey
    bne :-
    rts
.endproc

; -----------------------------------------------------------------------------
; Set cursor position
; X = column, Y = row
; -----------------------------------------------------------------------------
.proc set_cursor
    stx cursor_x
    sty cursor_y

    ; Calculate PPU address: $2000 + (Y * 32) + X
    lda PPU_STATUS          ; Reset latch
    tya
    lsr a                   ; High 3 bits of row
    lsr a
    lsr a
    ora #$20                ; Base $2000
    sta PPU_ADDR

    tya
    asl a                   ; Low 5 bits of row * 32
    asl a
    asl a
    asl a
    asl a
    sta temp1
    txa
    ora temp1
    sta PPU_ADDR
    rts
.endproc

; -----------------------------------------------------------------------------
; Print string
; ptr1 = string address, first byte is length
; -----------------------------------------------------------------------------
.proc print_string
    ldy #0
    lda (ptr1),y            ; Get length
    tax
    beq done
    iny
:   lda (ptr1),y
    sta PPU_DATA
    iny
    dex
    bne :-
done:
    rts
.endproc

; -----------------------------------------------------------------------------
; Print character in A
; -----------------------------------------------------------------------------
.proc print_char
    sta PPU_DATA
    rts
.endproc

; -----------------------------------------------------------------------------
; Print decimal number in A (0-255)
; -----------------------------------------------------------------------------
.proc print_decimal
    ldx #0                  ; Hundreds flag
    cmp #100
    bcc skip_hundreds
    ldx #1
:   sbc #100
    cmp #100
    bcs :-
    pha
    txa
    clc
    adc #'0'
    sta PPU_DATA
    pla
skip_hundreds:
    ldx #0
    cmp #10
    bcc skip_tens
:   inx
    sbc #10
    cmp #10
    bcs :-
    pha
    txa
    clc
    adc #'0'
    sta PPU_DATA
    pla
skip_tens:
    clc
    adc #'0'
    sta PPU_DATA
    rts
.endproc

; -----------------------------------------------------------------------------
; Show title screen
; -----------------------------------------------------------------------------
.proc show_title
    jsr display_clear

    ldx #10
    ldy #8
    jsr set_cursor
    lda #<msg_title
    sta ptr1
    lda #>msg_title
    sta ptr1+1
    jsr print_string

    ldx #6
    ldy #14
    jsr set_cursor
    lda #<msg_press_start
    sta ptr1
    lda #>msg_press_start
    sta ptr1+1
    jsr print_string
    rts
.endproc

; -----------------------------------------------------------------------------
; Show connecting message
; -----------------------------------------------------------------------------
.proc show_connecting
    jsr display_clear

    ldx #7
    ldy #14
    jsr set_cursor
    lda #<msg_connecting
    sta ptr1
    lda #>msg_connecting
    sta ptr1+1
    jsr print_string
    rts
.endproc

.segment "RODATA"

msg_title:
    .byte 12
    .byte "RACHEL - NES"

msg_press_start:
    .byte 19
    .byte "PRESS START TO PLAY"

msg_connecting:
    .byte 18
    .byte "CONNECTING TO HOST"
