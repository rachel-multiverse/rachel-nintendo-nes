; =============================================================================
; NES INPUT MODULE
; Controller reading
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Read controller 1
; Result in controller variable
; -----------------------------------------------------------------------------
.proc read_controller
    ; Save old state
    lda controller
    sta controller_old

    ; Strobe controller
    lda #$01
    sta CTRL_PORT1
    lda #$00
    sta CTRL_PORT1

    ; Read 8 buttons
    ldx #8
    lda #0
:   pha
    lda CTRL_PORT1
    and #$03                ; Handle both wired and wireless
    cmp #$01
    pla
    ror a                   ; Rotate carry into result
    dex
    bne :-

    sta controller
    rts
.endproc

; -----------------------------------------------------------------------------
; Check if button was just pressed (not held)
; A = button mask
; Returns: Z flag clear if just pressed
; -----------------------------------------------------------------------------
.proc button_pressed
    tax
    and controller          ; Is it pressed now?
    beq not_pressed
    txa
    and controller_old      ; Was it pressed before?
    bne not_pressed         ; If yes, not a new press
    txa                     ; Return with Z clear
    rts
not_pressed:
    lda #0                  ; Return with Z set
    rts
.endproc
