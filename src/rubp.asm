; =============================================================================
; NES RUBP PROTOCOL MODULE
; =============================================================================

.segment "CODE"

; -----------------------------------------------------------------------------
; Initialize RUBP
; -----------------------------------------------------------------------------
.proc rubp_init
    lda #0
    sta msg_sequence+0
    sta msg_sequence+1
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

    ; Sequence (big-endian: high byte first)
    lda msg_sequence+1
    sta net_buffer_tx+6
    lda msg_sequence+0
    sta net_buffer_tx+7
    inc msg_sequence
    bne :+
    inc msg_sequence+1
:

    ; Player ID (big-endian)
    lda player_id+1
    sta net_buffer_tx+8
    lda player_id+0
    sta net_buffer_tx+9

    ; Game ID (big-endian)
    lda game_id+1
    sta net_buffer_tx+10
    lda game_id+0
    sta net_buffer_tx+11

    ; Timestamp = 0
    lda #0
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

    ; SpecVersion (big-endian)
    lda #SPEC_VERSION_HI
    sta net_buffer_tx+PAYLOAD_START+18
    lda #SPEC_VERSION_LO
    sta net_buffer_tx+PAYLOAD_START+19

    jsr net_send
    rts
.endproc

; -----------------------------------------------------------------------------
; Send DRAW message
; A = reason (0=cannot play, 1=attack penalty)
; -----------------------------------------------------------------------------
.proc send_draw
    pha                     ; save reason
    lda #MSG_DRAW_CARD
    jsr build_header
    jsr clear_payload

    ; Reason @0
    pla
    sta net_buffer_tx+PAYLOAD_START+0
    ; Count @1 (always 1 for a manual draw)
    lda #1
    sta net_buffer_tx+PAYLOAD_START+1
    ; SpecVersion @2 (big-endian)
    lda #SPEC_VERSION_HI
    sta net_buffer_tx+PAYLOAD_START+2
    lda #SPEC_VERSION_LO
    sta net_buffer_tx+PAYLOAD_START+3
    ; Flags @4 + ObservedStateHash @5..12
    ldx #4
    jsr write_obs_hash

    jsr net_send
    rts
.endproc

; -----------------------------------------------------------------------------
; Write the Flags byte + ObservedStateHash into the TX payload.
; X = payload offset of the Flags byte; the 8-byte hash follows at X+1..X+8.
; If no state hash has been captured yet, the (cleared) flag/hash stay zero.
; -----------------------------------------------------------------------------
.proc write_obs_hash
    lda hash_valid
    beq done
    lda #$01                ; Flags bit0 = ObservedStateHash present
    sta net_buffer_tx+PAYLOAD_START,x
    ldy #0
copy:
    inx
    lda observed_hash,y
    sta net_buffer_tx+PAYLOAD_START,x
    iny
    cpy #8
    bne copy
done:
    rts
.endproc

; -----------------------------------------------------------------------------
; Send PLAY_CARD message
; A = nominated suit ($FF if none). Plays every card flagged in hand_selected.
; -----------------------------------------------------------------------------
.proc send_play_card
    pha                     ; save nominated suit
    lda #MSG_PLAY_CARD
    jsr build_header
    jsr clear_payload

    ; Copy selected cards to payload+1, counting them in Y
    ldx #0                  ; hand index
    ldy #0                  ; cards written (cards live at payload+1)
loop:
    cpx hand_count
    beq done
    lda hand_selected,x
    beq skip
    lda hand_cards,x
    sta net_buffer_tx+PAYLOAD_START+1,y
    iny
skip:
    inx
    bne loop
done:
    ; CardCount @0
    tya
    sta net_buffer_tx+PAYLOAD_START+0
    ; NominatedSuit @33
    pla
    sta net_buffer_tx+PAYLOAD_START+33
    ; SpecVersion @34 (big-endian)
    lda #SPEC_VERSION_HI
    sta net_buffer_tx+PAYLOAD_START+34
    lda #SPEC_VERSION_LO
    sta net_buffer_tx+PAYLOAD_START+35
    ; Flags @36 + ObservedStateHash @37..44
    ldx #36
    jsr write_obs_hash

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

; -----------------------------------------------------------------------------
; Parse WELCOME (0x02)
; Payload: AssignedPlayerID@0 (BE), GameID@2 (BE), PlayerCount@4, GameState@5,
;          SpecVersion@6 (BE). Stores the IDs (little-endian in RAM) and the
;          player count, and advances to the WAITING connection state.
; -----------------------------------------------------------------------------
.proc parse_welcome
    ; AssignedPlayerID (big-endian on the wire)
    lda net_buffer_rx+PAYLOAD_START+1
    sta player_id+0
    lda net_buffer_rx+PAYLOAD_START+0
    sta player_id+1
    ; GameID (big-endian)
    lda net_buffer_rx+PAYLOAD_START+3
    sta game_id+0
    lda net_buffer_rx+PAYLOAD_START+2
    sta game_id+1
    ; Player count
    lda net_buffer_rx+PAYLOAD_START+4
    sta player_count
    ; Connection state
    lda #CONN_WAITING
    sta conn_state
    rts
.endproc

; -----------------------------------------------------------------------------
; Parse GAME_STATE (0x07) — the public state summary.
; Captures the fields the UI needs and, when Flags bit0 says a state hash is
; present, latches the 8-byte hash into observed_hash so the next PLAY/DRAW
; echoes it. GAME_STATE carries no hand; cards arrive via GAME_START /
; CARD_DRAWN (parse_cards).
; -----------------------------------------------------------------------------
.proc parse_game_state
    lda net_buffer_rx+PAYLOAD_START+0   ; CurrentPlayer
    sta current_turn
    lda net_buffer_rx+PAYLOAD_START+1   ; Direction
    sta direction
    lda net_buffer_rx+PAYLOAD_START+2   ; TopCard
    sta discard_top
    lda net_buffer_rx+PAYLOAD_START+3   ; NominatedSuit
    sta current_suit
    lda net_buffer_rx+PAYLOAD_START+4   ; PendingDraws
    sta draw_count
    lda net_buffer_rx+PAYLOAD_START+6   ; DeckCount
    sta deck_count

    ; PlayerCardCounts @7..14
    ldx #0
:   lda net_buffer_rx+PAYLOAD_START+7,x
    sta player_counts,x
    inx
    cpx #8
    bne :-

    lda net_buffer_rx+PAYLOAD_START+15  ; IsGameOver
    sta game_over
    lda net_buffer_rx+PAYLOAD_START+16  ; WinnerIndex
    sta winner_index

    ; StateHash @24..31, present only when Flags(@23) bit0 is set.
    lda net_buffer_rx+PAYLOAD_START+23
    and #$01
    beq no_hash
    ldx #0
:   lda net_buffer_rx+PAYLOAD_START+24,x
    sta observed_hash,x
    inx
    cpx #8
    bne :-
    lda #1
    sta hash_valid
no_hash:
    rts
.endproc

; -----------------------------------------------------------------------------
; Parse GAME_START (0x03) / CARD_DRAWN (0x06) — both carry a private hand.
; Payload: CardCount@0, Cards@1.. . A = 0 replaces the hand (GAME_START);
; A != 0 appends (CARD_DRAWN). The hand is clamped to its 20-card capacity.
; -----------------------------------------------------------------------------
.proc parse_cards
    tay                     ; A = mode; 0 = replace
    bne append
    ; Replace: start a fresh hand and clear selection/cursor.
    lda #0
    sta hand_count
    sta hand_cursor
    ldx #0
:   sta hand_selected,x
    inx
    cpx #20
    bne :-
append:
    lda net_buffer_rx+PAYLOAD_START+0   ; cards in this message
    sta temp1
    ldx hand_count          ; destination index
    ldy #0                  ; source index
copy:
    cpy temp1
    beq done
    cpx #20                 ; stop at hand capacity
    beq done
    lda net_buffer_rx+PAYLOAD_START+1,y
    sta hand_cards,x
    inx
    iny
    jmp copy
done:
    stx hand_count
    rts
.endproc

.segment "RODATA"

player_name:
    .byte "NES", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
