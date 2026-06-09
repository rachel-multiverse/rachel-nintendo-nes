; =============================================================================
; RUBP ENCODER CONFORMANCE HARNESS (Nintendo NES)
; =============================================================================
; Drives the REAL client encoders from ../src/rubp.asm with the field values
; from the golden fixtures and leaves each 64-byte message in a RAM capture
; region. Boots straight from the reset vector (no OS), runs every test, and
; parks. Run headless under emu198x-nes, then memory_read the regions and diff
; against rubp-messages-v1.json. See run.py.
;
; The encoders build into net_buffer_tx and call net_send; we stub net_send /
; net_recv to RTS so nothing touches the (theoretical) serial adapter — the
; built message still sits in net_buffer_tx, which we copy out.
;
; Capture region (NES RAM; PRG-ROM at $8000+ is read-only, so captures live low):
;   $0500  HELLO encoder output      (64)
;   $0540  PLAY_CARD encoder output  (64)
;   $0580  DRAW_CARD encoder output  (64)
;   $05FF  done marker = $AA once every test has run
;
; Build:  ca65 harness.asm -o build/harness.o && ld65 -C harness.cfg ... (see run.py)

.include "../src/equates.asm"

; The codec's variables, at fixed RAM addresses (the real client puts these in
; its BSS; here we pin them so the capture region can't collide).
net_buffer_tx = $0300
net_buffer_rx = $0340
msg_sequence  = $0380       ; 16-bit, little-endian in RAM
player_id     = $0382
game_id       = $0384
observed_hash = $0386
hash_valid    = $038E
hand_count    = $038F
hand_cards    = $0390       ; 20
hand_selected = $03A4       ; 20

cap_ptr       = $02         ; zero-page scratch pointer for the capture copy

CAP_HELLO = $0500
CAP_PLAY  = $0540
CAP_DRAW  = $0580
CAP_DONE  = $05FF

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
    sta PPU_CTRL            ; keep NMI disabled
    sta PPU_MASK            ; rendering off

    jsr test_hello
    jsr test_play
    jsr test_draw

    lda #$aa
    sta CAP_DONE
park:
    jmp park

; HELLO: name "NES" (the client's own), seq 0x0021, playerID 0xFFFF, gameID 0x0042
.proc test_hello
    lda #$21
    sta msg_sequence+0
    lda #$00
    sta msg_sequence+1
    lda #$ff
    sta player_id+0
    sta player_id+1
    lda #$42
    sta game_id+0
    lda #$00
    sta game_id+1
    jsr send_hello
    lda #<CAP_HELLO
    sta cap_ptr
    lda #>CAP_HELLO
    sta cap_ptr+1
    jmp copy_tx
.endproc

; PLAY_CARD: one card A-hearts (0x0E) selected, nominated suit clubs (0x02),
; seq 0x0022, playerID 0x0001, gameID 0x0042, observed hash = the play vector's
.proc test_play
    lda #$22
    sta msg_sequence+0
    lda #$00
    sta msg_sequence+1
    lda #$01
    sta player_id+0
    lda #$00
    sta player_id+1
    lda #$42
    sta game_id+0
    lda #$00
    sta game_id+1
    lda #$0e                ; hand[0] = A-hearts
    sta hand_cards+0
    lda #$01               ; hand[0] selected
    sta hand_selected+0
    lda #$01
    sta hand_count
    ldx #<hash_play
    ldy #>hash_play
    jsr load_obs_hash
    lda #$02               ; nominated suit = clubs
    jsr send_play_card
    lda #<CAP_PLAY
    sta cap_ptr
    lda #>CAP_PLAY
    sta cap_ptr+1
    jmp copy_tx
.endproc

; DRAW_CARD: reason 0 (cannot play), seq 0x0023, playerID 0x0001, gameID 0x0042
.proc test_draw
    lda #$23
    sta msg_sequence+0
    lda #$00
    sta msg_sequence+1
    lda #$01
    sta player_id+0
    lda #$00
    sta player_id+1
    lda #$42
    sta game_id+0
    lda #$00
    sta game_id+1
    ldx #<hash_draw
    ldy #>hash_draw
    jsr load_obs_hash
    lda #$00               ; reason = cannot play
    jsr send_draw
    lda #<CAP_DRAW
    sta cap_ptr
    lda #>CAP_DRAW
    sta cap_ptr+1
    jmp copy_tx
.endproc

; Load 8 bytes at X/Y (lo/hi) into observed_hash and mark it valid.
.proc load_obs_hash
    stx cap_ptr
    sty cap_ptr+1
    ldy #0
:   lda (cap_ptr),y
    sta observed_hash,y
    iny
    cpy #8
    bne :-
    lda #1
    sta hash_valid
    rts
.endproc

; Copy the 64-byte net_buffer_tx to (cap_ptr).
.proc copy_tx
    ldy #0
:   lda net_buffer_tx,y
    sta (cap_ptr),y
    iny
    cpy #64
    bne :-
    rts
.endproc

; Serial stubs — the encoders call these; we want no real I/O.
.proc net_send
    rts
.endproc
.proc net_recv
    rts
.endproc

; The real client codec under test.
.include "../src/rubp.asm"

.segment "RODATA"
hash_play:
    .byte $11, $22, $33, $44, $55, $66, $77, $88
hash_draw:
    .byte $88, $77, $66, $55, $44, $33, $22, $11

.segment "VECTORS"
    .word park              ; NMI
    .word reset             ; RESET
    .word park              ; IRQ
