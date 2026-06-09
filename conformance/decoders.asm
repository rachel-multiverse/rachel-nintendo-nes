; =============================================================================
; RUBP DECODER CONFORMANCE HARNESS (Nintendo NES)
; =============================================================================
; Drives the REAL client parsers from ../src/rubp.asm with the golden fixture
; vectors (loaded into net_buffer_rx) and captures the variables they extract,
; so the host can check the parser pulled the right value from the right offset.
;
; Input vectors come from build/vectors.inc, which run.py regenerates from
; rubp-messages-v1.json each run — the bytes fed in are always the golden bytes,
; with no hand-transcription drift.
;
; Capture region (NES RAM):
;   $0500  WELCOME    : playerID lo/hi, gameID lo/hi, playerCount, connState
;   $0510  GAME_STATE : currentTurn, direction, topCard, nominatedSuit,
;                       pendingDraws, deckCount, playerCounts[8], gameOver,
;                       winnerIndex, observedHash[8], hashValid
;   $05FF  done marker = $AA once every test has run
;
; Boots straight from the reset vector (no OS); run headless under emu198x-nes,
; then memory_read the regions and diff. See run.py.

.include "../src/equates.asm"

; The codec's variables, pinned at fixed RAM addresses (the real client puts
; these in its BSS; here we pin them so the capture region can't collide).
net_buffer_tx = $0300       ; encoders reference it; unused here
net_buffer_rx = $0340
msg_sequence  = $0380
player_id     = $0382
game_id       = $0384
observed_hash = $0386       ; 8
hash_valid    = $038E
hand_count    = $038F
hand_cards    = $0390       ; 20
hand_selected = $03A4       ; 20
hand_cursor   = $03B8
player_count  = $03B9
conn_state    = $03BA
current_turn  = $03BB
direction     = $03BC
discard_top   = $03BD
current_suit  = $03BE
draw_count    = $03BF
deck_count    = $03C0
player_counts = $03C1       ; 8
game_over     = $03C9
winner_index  = $03CA

temp1         = $10         ; zero-page scratch used by parse_cards
vec_ptr       = $04         ; zero-page pointer for the vector copy

DCAP_WELCOME = $0500
DCAP_GS      = $0510
DCAP_DONE    = $05FF

; -----------------------------------------------------------------------------
; iNES header: NROM (mapper 0), 32KB PRG, CHR-RAM
; -----------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2                  ; 2 x 16KB PRG-ROM
    .byte 0                  ; 0 CHR banks -> CHR-RAM
    .byte $00, $00
    .byte 0, 0, 0, 0, 0, 0, 0, 0

.segment "CODE"

reset:
    sei
    cld
    ldx #$ff
    txs
    lda #0
    sta PPU_CTRL
    sta PPU_MASK

    jsr test_welcome
    jsr test_game_state

    lda #$aa
    sta DCAP_DONE
park:
    jmp park

; -----------------------------------------------------------------------------
; WELCOME: feed the golden welcome vector, capture what parse_welcome extracts.
; -----------------------------------------------------------------------------
.proc test_welcome
    lda #<welcome_msg
    ldx #>welcome_msg
    jsr load_rx

    jsr parse_welcome

    lda player_id+0
    sta DCAP_WELCOME+0
    lda player_id+1
    sta DCAP_WELCOME+1
    lda game_id+0
    sta DCAP_WELCOME+2
    lda game_id+1
    sta DCAP_WELCOME+3
    lda player_count
    sta DCAP_WELCOME+4
    lda conn_state
    sta DCAP_WELCOME+5
    rts
.endproc

; -----------------------------------------------------------------------------
; GAME_STATE: clear the hash state first so we prove the parser sets it, then
; feed the golden vector and capture everything parse_game_state extracts.
; -----------------------------------------------------------------------------
.proc test_game_state
    lda #0
    sta hash_valid
    ldx #0
:   sta observed_hash,x
    inx
    cpx #8
    bne :-

    lda #<game_state_msg
    ldx #>game_state_msg
    jsr load_rx

    jsr parse_game_state

    lda current_turn
    sta DCAP_GS+0
    lda direction
    sta DCAP_GS+1
    lda discard_top
    sta DCAP_GS+2
    lda current_suit
    sta DCAP_GS+3
    lda draw_count
    sta DCAP_GS+4
    lda deck_count
    sta DCAP_GS+5
    ldx #0
:   lda player_counts,x
    sta DCAP_GS+6,x
    inx
    cpx #8
    bne :-                   ; DCAP_GS+6 .. +13
    lda game_over
    sta DCAP_GS+14
    lda winner_index
    sta DCAP_GS+15
    ldx #0
:   lda observed_hash,x
    sta DCAP_GS+16,x
    inx
    cpx #8
    bne :-                   ; DCAP_GS+16 .. +23
    lda hash_valid
    sta DCAP_GS+24
    rts
.endproc

; -----------------------------------------------------------------------------
; Copy 64 bytes from A/X (lo/hi) into net_buffer_rx.
; -----------------------------------------------------------------------------
.proc load_rx
    sta vec_ptr
    stx vec_ptr+1
    ldy #0
:   lda (vec_ptr),y
    sta net_buffer_rx,y
    iny
    cpy #64
    bne :-
    rts
.endproc

; Serial stubs — the codec references these; we want no real I/O.
.proc net_send
    rts
.endproc
.proc net_recv
    rts
.endproc

; The real client codec under test.
.include "../src/rubp.asm"

.include "build/vectors.inc"

.segment "VECTORS"
    .word park              ; NMI
    .word reset             ; RESET
    .word park              ; IRQ
