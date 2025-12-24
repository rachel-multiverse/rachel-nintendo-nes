; =============================================================================
; NES RUBP PROTOCOL MODULE
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Initialize RUBP
; -----------------------------------------------------------------------------
.proc rubp_init
    lda #0
    sta msg_sequence
    rts
.endproc

; -----------------------------------------------------------------------------
; Build message header
; A = message type
; -----------------------------------------------------------------------------
.proc build_header
    pha                     ; Save message type

    ; Magic "RACH"
    lda #'R'
    sta net_buffer_tx+0
    lda #'A'
    sta net_buffer_tx+1
    lda #'C'
    sta net_buffer_tx+2
    lda #'H'
    sta net_buffer_tx+3

    ; Version
    lda #RUBP_VERSION
    sta net_buffer_tx+4

    ; Message type
    pla
    sta net_buffer_tx+5

    ; Sequence
    lda msg_sequence
    sta net_buffer_tx+6
    inc msg_sequence

    ; Flags and reserved
    lda #0
    sta net_buffer_tx+7
    sta net_buffer_tx+8
    sta net_buffer_tx+9
    sta net_buffer_tx+10
    sta net_buffer_tx+11
    sta net_buffer_tx+12
    sta net_buffer_tx+13
    sta net_buffer_tx+14
    sta net_buffer_tx+15
    rts
.endproc

; -----------------------------------------------------------------------------
; Clear payload
; -----------------------------------------------------------------------------
.proc clear_payload
    ldx #PAYLOAD_SIZE-1
    lda #0
:   sta net_buffer_tx+PAYLOAD_START,x
    dex
    bpl :-
    rts
.endproc

; -----------------------------------------------------------------------------
; Send HELLO message
; -----------------------------------------------------------------------------
.proc send_hello
    lda #MSG_HELLO
    jsr build_header
    jsr clear_payload

    ; Copy player name
    ldx #0
:   lda player_name,x
    sta net_buffer_tx+PAYLOAD_START,x
    inx
    cpx #16
    bne :-

    ; Platform ID
    lda #PLATFORM_ID_HI
    sta net_buffer_tx+PAYLOAD_START+16
    lda #PLATFORM_ID_LO
    sta net_buffer_tx+PAYLOAD_START+17

    jsr net_send
    rts
.endproc

; -----------------------------------------------------------------------------
; Send DRAW message
; -----------------------------------------------------------------------------
.proc send_draw
    lda #MSG_DRAW_CARD
    jsr build_header
    jsr clear_payload
    jsr net_send
    rts
.endproc

; -----------------------------------------------------------------------------
; Send PLAY_CARD message
; A = card to play
; -----------------------------------------------------------------------------
.proc send_play_card
    pha
    lda #MSG_PLAY_CARD
    jsr build_header
    jsr clear_payload
    pla
    sta net_buffer_tx+PAYLOAD_START
    jsr net_send
    rts
.endproc

; -----------------------------------------------------------------------------
; Validate received RUBP message
; Returns: C clear if valid, C set if invalid
; -----------------------------------------------------------------------------
.proc rubp_validate
    lda net_buffer_rx+0
    cmp #'R'
    bne invalid
    lda net_buffer_rx+1
    cmp #'A'
    bne invalid
    lda net_buffer_rx+2
    cmp #'C'
    bne invalid
    lda net_buffer_rx+3
    cmp #'H'
    bne invalid
    clc
    rts
invalid:
    sec
    rts
.endproc

; -----------------------------------------------------------------------------
; Get message type
; Returns: A = message type
; -----------------------------------------------------------------------------
.proc get_message_type
    lda net_buffer_rx+5
    rts
.endproc

.segment "RODATA"

player_name:
    .byte "NES", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
