; =============================================================================
; NES HARDWARE INITIALIZATION
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Initialize NES hardware
; -----------------------------------------------------------------------------
.proc init_hardware
    sei                     ; Disable IRQs
    cld                     ; Clear decimal mode (not used on NES anyway)
    ldx #$40
    stx APU_FRAME           ; Disable APU frame IRQ
    ldx #$FF
    txs                     ; Set up stack
    inx                     ; X = 0
    stx PPU_CTRL            ; Disable NMI
    stx PPU_MASK            ; Disable rendering
    stx APU_DMC_CTRL        ; Disable DMC IRQs

    ; Wait for first vblank
    jsr wait_vblank

    ; Clear RAM
    lda #$00
clear_ram:
    sta $0000,x
    sta $0100,x
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear_ram

    ; Wait for second vblank (PPU is ready)
    jsr wait_vblank
    rts
.endproc

; -----------------------------------------------------------------------------
; Wait for vblank
; -----------------------------------------------------------------------------
.proc wait_vblank
:   bit PPU_STATUS
    bpl :-
    rts
.endproc

; -----------------------------------------------------------------------------
; Initialize PPU for text display
; -----------------------------------------------------------------------------
.proc init_ppu
    ; Set palette
    lda PPU_STATUS          ; Reset latch
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ; Background palette
    lda #$0F                ; Black
    sta PPU_DATA
    lda #$30                ; White
    sta PPU_DATA
    lda #$10                ; Light gray
    sta PPU_DATA
    lda #$00                ; Dark gray
    sta PPU_DATA

    ; Clear nametable
    lda PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    lda #$00
    ldx #$00
    ldy #$04
clear_nt:
    sta PPU_DATA
    inx
    bne clear_nt
    dey
    bne clear_nt

    ; Enable rendering
    lda #%00001000          ; BG pattern table at $1000
    sta PPU_CTRL
    lda #%00001010          ; Show background
    sta PPU_MASK

    rts
.endproc
