; =============================================================================
; NES SERIAL MODULE
; Serial via controller port adapter (theoretical)
; =============================================================================

; The NES doesn't have a built-in serial port.
; This module assumes a custom adapter connected to controller port 2
; that provides serial communication via specific bit patterns.
;
; Protocol:
; - Write to $4016 bit 0 = data out
; - Read from $4017 bit 0 = data in
; - Uses software bit-banging at ~9600 baud

.segment "ZEROPAGE"
serial_byte:    .res 1
serial_count:   .res 1
net_status:     .res 1

.segment "CODE"

; -----------------------------------------------------------------------------
; Initialize serial
; -----------------------------------------------------------------------------
.proc net_init
    lda #0
    sta net_status
    rts
.endproc

; -----------------------------------------------------------------------------
; Connect to server (via AT commands)
; Returns: C clear on success, C set on failure
; -----------------------------------------------------------------------------
.proc net_connect
    ; Send AT+CIPSTART command
    lda #<at_cipstart
    sta ptr1
    lda #>at_cipstart
    sta ptr1+1
    jsr send_at_string

    ; Send IP address
    jsr send_ip_addr

    ; Send port
    lda #<at_port
    sta ptr1
    lda #>at_port
    sta ptr1+1
    jsr send_at_string

    ; Wait for OK response
    jsr wait_response
    rts
.endproc

; -----------------------------------------------------------------------------
; Send AT command string
; ptr1 = null-terminated string
; -----------------------------------------------------------------------------
.proc send_at_string
    ldy #0
:   lda (ptr1),y
    beq done
    jsr serial_write_byte
    iny
    bne :-
done:
    rts
.endproc

; -----------------------------------------------------------------------------
; Send IP address (hardcoded for now)
; -----------------------------------------------------------------------------
.proc send_ip_addr
    lda #'1'
    jsr serial_write_byte
    lda #'9'
    jsr serial_write_byte
    lda #'2'
    jsr serial_write_byte
    lda #'.'
    jsr serial_write_byte
    lda #'1'
    jsr serial_write_byte
    lda #'6'
    jsr serial_write_byte
    lda #'8'
    jsr serial_write_byte
    lda #'.'
    jsr serial_write_byte
    lda #'1'
    jsr serial_write_byte
    lda #'.'
    jsr serial_write_byte
    lda #'1'
    jsr serial_write_byte
    lda #'0'
    jsr serial_write_byte
    lda #'0'
    jsr serial_write_byte
    rts
.endproc

; -----------------------------------------------------------------------------
; Write byte via serial (bit-banged)
; A = byte to send
; -----------------------------------------------------------------------------
.proc serial_write_byte
    sta serial_byte
    ldx #8

    ; Start bit
    lda #0
    sta CTRL_PORT1
    jsr bit_delay

send_loop:
    lsr serial_byte
    lda #0
    bcc send_zero
    lda #1
send_zero:
    sta CTRL_PORT1
    jsr bit_delay
    dex
    bne send_loop

    ; Stop bit
    lda #1
    sta CTRL_PORT1
    jsr bit_delay
    rts
.endproc

; -----------------------------------------------------------------------------
; Read byte via serial
; Returns: A = byte, C set if timeout
; -----------------------------------------------------------------------------
.proc serial_read_byte
    ldx #8
    lda #0
    sta serial_byte

    ; Wait for start bit
    ldy #255
wait_start:
    lda CTRL_PORT2
    and #$01
    beq got_start
    dey
    bne wait_start
    sec                     ; Timeout
    rts

got_start:
    jsr half_bit_delay      ; Center in bit

read_loop:
    jsr bit_delay
    lda CTRL_PORT2
    and #$01
    clc
    ror a
    ror serial_byte
    dex
    bne read_loop

    ; Skip stop bit
    jsr bit_delay

    lda serial_byte
    clc
    rts
.endproc

; -----------------------------------------------------------------------------
; Bit timing delays (for ~9600 baud on NTSC NES)
; NTSC NES runs at ~1.79MHz, 9600 baud = ~186 cycles/bit
; -----------------------------------------------------------------------------
.proc bit_delay
    ldy #37                 ; Approx 186 cycles
:   dey
    bne :-
    rts
.endproc

.proc half_bit_delay
    ldy #18
:   dey
    bne :-
    rts
.endproc

; -----------------------------------------------------------------------------
; Wait for "OK" response
; Returns: C clear on success, C set on timeout
; -----------------------------------------------------------------------------
.proc wait_response
    ldx #200                ; Timeout counter
wait_loop:
    jsr serial_read_byte
    bcs next_try
    cmp #'O'
    bne next_try
    jsr serial_read_byte
    bcs next_try
    cmp #'K'
    bne next_try
    clc
    rts
next_try:
    dex
    bne wait_loop
    sec
    rts
.endproc

; -----------------------------------------------------------------------------
; Send 64-byte buffer
; -----------------------------------------------------------------------------
.proc net_send
    ; Send AT+CIPSEND=64
    lda #<at_cipsend
    sta ptr1
    lda #>at_cipsend
    sta ptr1+1
    jsr send_at_string

    ; Send buffer
    ldx #0
:   lda net_buffer_tx,x
    jsr serial_write_byte
    inx
    cpx #64
    bne :-
    rts
.endproc

; -----------------------------------------------------------------------------
; Receive into 64-byte buffer
; Returns: C clear if data received, C set if no data
; -----------------------------------------------------------------------------
.proc net_recv
    ldx #0
recv_loop:
    jsr serial_read_byte
    bcs recv_timeout
    sta net_buffer_rx,x
    inx
    cpx #64
    bne recv_loop
    clc
    rts
recv_timeout:
    cpx #0
    beq no_data
    clc                     ; Partial data
    rts
no_data:
    sec
    rts
.endproc

; -----------------------------------------------------------------------------
; Close connection
; -----------------------------------------------------------------------------
.proc net_close
    lda #<at_cipclose
    sta ptr1
    lda #>at_cipclose
    sta ptr1+1
    jsr send_at_string
    rts
.endproc

.segment "RODATA"

at_cipstart:
    .byte "AT+CIPSTART=", 34, "TCP", 34, ",", 34, 0

at_port:
    .byte 34, ",8765", 13, 0

at_cipsend:
    .byte "AT+CIPSEND=64", 13, 0

at_cipclose:
    .byte "AT+CIPCLOSE", 13, 0
