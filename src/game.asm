; =============================================================================
; NES GAME MODULE
; Game state and rendering
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Process game state from network
; -----------------------------------------------------------------------------
.proc process_game_state
    ldx #0
    lda net_buffer_rx+PAYLOAD_START
    sta current_turn
    lda net_buffer_rx+PAYLOAD_START+1
    sta my_index
    lda net_buffer_rx+PAYLOAD_START+2
    sta discard_top
    lda net_buffer_rx+PAYLOAD_START+3
    sta current_suit
    lda net_buffer_rx+PAYLOAD_START+4
    sta draw_count
    lda net_buffer_rx+PAYLOAD_START+5
    sta hand_count

    ; Copy hand cards
    ldx #0
:   lda net_buffer_rx+PAYLOAD_START+6,x
    sta hand_cards,x
    inx
    cpx #20
    bne :-

    ; Clear selection
    ldx #0
    lda #0
:   sta hand_selected,x
    inx
    cpx #20
    bne :-

    lda #0
    sta hand_cursor
    rts
.endproc

; -----------------------------------------------------------------------------
; Render game screen
; -----------------------------------------------------------------------------
.proc render_game
    jsr display_clear

    ; Discard pile
    ldx #2
    ldy #2
    jsr set_cursor
    lda #<lbl_discard
    sta ptr1
    lda #>lbl_discard
    sta ptr1+1
    jsr print_string
    lda discard_top
    jsr print_card

    ; Current suit
    ldx #2
    ldy #4
    jsr set_cursor
    lda #<lbl_suit
    sta ptr1
    lda #>lbl_suit
    sta ptr1+1
    jsr print_string
    lda current_suit
    jsr print_suit

    ; Draw penalty
    lda draw_count
    beq no_draw
    ldx #2
    ldy #6
    jsr set_cursor
    lda #<lbl_draw
    sta ptr1
    lda #>lbl_draw
    sta ptr1+1
    jsr print_string
    lda draw_count
    jsr print_decimal

no_draw:
    ; Render hand
    jsr render_hand

    ; Status line
    ldx #1
    ldy #26
    jsr set_cursor
    lda current_turn
    cmp my_index
    bne show_waiting
    lda #<lbl_your_turn
    sta ptr1
    lda #>lbl_your_turn
    sta ptr1+1
    jmp show_status
show_waiting:
    lda #<lbl_waiting
    sta ptr1
    lda #>lbl_waiting
    sta ptr1+1
show_status:
    jsr print_string
    rts
.endproc

; -----------------------------------------------------------------------------
; Render hand of cards
; -----------------------------------------------------------------------------
.proc render_hand
    ldx #1
    ldy #18
    jsr set_cursor

    ldx #0
render_loop:
    cpx hand_count
    beq done

    ; Cursor indicator
    cpx hand_cursor
    bne not_cursor
    lda #'['
    jsr print_char
    jmp show_card
not_cursor:
    lda #' '
    jsr print_char

show_card:
    lda hand_cards,x
    jsr print_card

    ; Selected indicator
    lda hand_selected,x
    beq not_selected
    lda #'*'
    jsr print_char
    jmp next_card
not_selected:
    lda #' '
    jsr print_char

next_card:
    inx
    cpx #10                 ; Max cards per row
    bne render_loop
done:
    rts
.endproc

; -----------------------------------------------------------------------------
; Print card (A = card byte)
; -----------------------------------------------------------------------------
.proc print_card
    pha
    lsr a
    lsr a                   ; Divide by 4 for rank
    tax
    lda ranks,x
    jsr print_char
    pla
    and #$03                ; Suit
    jsr print_suit
    rts
.endproc

; -----------------------------------------------------------------------------
; Print suit (A = suit 0-3)
; -----------------------------------------------------------------------------
.proc print_suit
    and #$03
    tax
    lda suits,x
    jsr print_char
    rts
.endproc

; -----------------------------------------------------------------------------
; Handle game input
; -----------------------------------------------------------------------------
.proc handle_game_input
    ; Left
    lda #BTN_LEFT
    jsr button_pressed
    beq not_left
    lda hand_cursor
    beq not_left
    dec hand_cursor
    jsr render_game
not_left:

    ; Right
    lda #BTN_RIGHT
    jsr button_pressed
    beq not_right
    lda hand_cursor
    clc
    adc #1
    cmp hand_count
    bcs not_right
    inc hand_cursor
    jsr render_game
not_right:

    ; A = select
    lda #BTN_A
    jsr button_pressed
    beq not_select
    ldx hand_cursor
    lda hand_selected,x
    eor #$FF
    sta hand_selected,x
    jsr render_game
not_select:

    ; B = play selected
    lda #BTN_B
    jsr button_pressed
    beq not_play
    jsr play_selected_cards
not_play:

    ; Select = draw
    lda #BTN_SELECT
    jsr button_pressed
    beq not_draw
    lda #0                  ; reason: cannot play
    jsr send_draw
not_draw:
    rts
.endproc

; -----------------------------------------------------------------------------
; Play selected cards
; -----------------------------------------------------------------------------
.proc play_selected_cards
    ; send_play_card now reads hand_selected itself and plays every flagged
    ; card; pass the nominated suit ($FF = none, no Ace nomination on NES yet).
    lda #$FF
    jsr send_play_card
    rts
.endproc

.segment "RODATA"

ranks:
    .byte "A23456789TJQK"

suits:
    .byte "HDCS"            ; Hearts, Diamonds, Clubs, Spades

lbl_discard:
    .byte 9
    .byte "DISCARD: "

lbl_suit:
    .byte 6
    .byte "SUIT: "

lbl_draw:
    .byte 6
    .byte "DRAW: "

lbl_your_turn:
    .byte 24
    .byte "YOUR TURN - B:PLAY SEL:DRAW"

lbl_waiting:
    .byte 11
    .byte "WAITING..."
