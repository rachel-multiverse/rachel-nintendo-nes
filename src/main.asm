; =============================================================================
; NINTENDO NES RACHEL CLIENT
; Main entry point
; =============================================================================

.include "equates.asm"
.include "header.asm"

.segment "ZEROPAGE"
game_state:     .res 1
frame_count:    .res 1
controller:     .res 1
controller_old: .res 1
temp1:          .res 1
temp2:          .res 1
ptr1:           .res 2
cursor_x:       .res 1
cursor_y:       .res 1

.segment "BSS"
; RUBP buffers (128 bytes total - significant in 2KB!)
net_buffer_tx:  .res 64
net_buffer_rx:  .res 64

; Game state
current_turn:   .res 1
my_index:       .res 1
discard_top:    .res 1
current_suit:   .res 1       ; active suit nomination (GAME_STATE @3)
draw_count:     .res 1       ; pending draws (GAME_STATE @4)
direction:      .res 1       ; 0=clockwise, 1=counter-clockwise (GAME_STATE @1)
deck_count:     .res 1       ; cards left in deck (GAME_STATE @6)
player_counts:  .res 8       ; card count per player (GAME_STATE @7..14)
game_over:      .res 1       ; 0=playing, 1=over (GAME_STATE @15)
winner_index:   .res 1       ; winner seat, 0xFF if none (GAME_STATE @16)
hand_count:     .res 1
hand_cursor:    .res 1
hand_cards:     .res 20
hand_selected:  .res 20
msg_sequence:   .res 2       ; 16-bit, little-endian in RAM
player_id:      .res 2       ; assigned by WELCOME (16-bit, LE in RAM)
game_id:        .res 2       ; assigned by WELCOME (16-bit, LE in RAM)
player_count:   .res 1       ; total players (WELCOME @4)
conn_state:     .res 1       ; CONN_* connection state
observed_hash:  .res 8       ; last GAME_STATE hash, echoed in PLAY/DRAW
hash_valid:     .res 1       ; 1 once a state hash has been captured

.segment "CODE"

; -----------------------------------------------------------------------------
; Reset vector - entry point
; -----------------------------------------------------------------------------
.proc reset
    jsr init_hardware
    jsr init_ppu
    jsr rubp_init
    jsr net_init

    lda #STATE_TITLE
    sta game_state

main_loop:
    jsr wait_vblank
    inc frame_count

    jsr read_controller

    lda game_state
    cmp #STATE_TITLE
    beq do_title
    cmp #STATE_CONNECT
    beq do_connect
    cmp #STATE_GAME
    beq do_game
    jmp main_loop

do_title:
    jsr handle_title
    jmp main_loop

do_connect:
    jsr do_connect_state
    jmp main_loop

do_game:
    jsr process_game
    jmp main_loop
.endproc

; -----------------------------------------------------------------------------
; Title screen
; -----------------------------------------------------------------------------
.proc handle_title
    ; Check for START
    lda controller
    and #BTN_START
    beq done

    ; Transition to connect
    jsr show_connecting
    lda #STATE_CONNECT
    sta game_state
done:
    rts
.endproc

; -----------------------------------------------------------------------------
; Connection state
; -----------------------------------------------------------------------------
.proc do_connect_state
    jsr net_connect
    bcs connect_fail

    jsr send_hello
    lda #STATE_GAME
    sta game_state
    rts

connect_fail:
    lda #STATE_TITLE
    sta game_state
    rts
.endproc

; -----------------------------------------------------------------------------
; Game processing
; -----------------------------------------------------------------------------
.proc process_game
    ; Poll network
    jsr net_recv
    bcs no_data

    ; Validate RUBP
    jsr rubp_validate
    bcs no_data

    ; Dispatch on message type
    jsr get_message_type
    cmp #MSG_WELCOME
    bne not_welcome
    jsr parse_welcome
    jmp redraw
not_welcome:
    cmp #MSG_GAME_START
    bne not_start
    lda #0                  ; replace hand
    jsr parse_cards
    jmp redraw
not_start:
    cmp #MSG_CARD_DRAWN
    bne not_drawn
    lda #1                  ; append to hand
    jsr parse_cards
    jmp redraw
not_drawn:
    cmp #MSG_GAME_STATE
    bne no_data
    jsr parse_game_state
redraw:
    jsr render_game

no_data:
    ; Handle input
    jsr handle_game_input
    rts
.endproc

; -----------------------------------------------------------------------------
; NMI handler (vblank)
; -----------------------------------------------------------------------------
.proc nmi
    rti
.endproc

; -----------------------------------------------------------------------------
; IRQ handler
; -----------------------------------------------------------------------------
.proc irq
    rti
.endproc

; Include other modules
.include "init.asm"
.include "display.asm"
.include "input.asm"
.include "game.asm"
.include "rubp.asm"
.include "net/serial.asm"

; -----------------------------------------------------------------------------
; Vectors
; -----------------------------------------------------------------------------
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
