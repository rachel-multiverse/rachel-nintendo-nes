; =============================================================================
; NES EQUATES AND CONSTANTS
; =============================================================================

; PPU Registers
PPU_CTRL    = $2000
PPU_MASK    = $2001
PPU_STATUS  = $2002
OAM_ADDR    = $2003
OAM_DATA    = $2004
PPU_SCROLL  = $2005
PPU_ADDR    = $2006
PPU_DATA    = $2007
OAM_DMA     = $4014

; APU Registers
APU_PULSE1  = $4000
APU_PULSE2  = $4004
APU_TRI     = $4008
APU_NOISE   = $400C
APU_DMC_CTRL = $4010
APU_STATUS  = $4015
APU_FRAME   = $4017

; Controller
CTRL_PORT1  = $4016
CTRL_PORT2  = $4017

; Controller bits
BTN_A       = %10000000
BTN_B       = %01000000
BTN_SELECT  = %00100000
BTN_START   = %00010000
BTN_UP      = %00001000
BTN_DOWN    = %00000100
BTN_LEFT    = %00000010
BTN_RIGHT   = %00000001

; RUBP Protocol
RUBP_VERSION    = 1
MSG_HELLO       = $01
MSG_GAME_STATE  = $10
MSG_PLAY_CARD   = $20
MSG_DRAW_CARD   = $21
PAYLOAD_START   = 16
PAYLOAD_SIZE    = 48

; Platform identification
PLATFORM_ID_HI  = $00
PLATFORM_ID_LO  = $C0       ; 192 = NES

; Game states
STATE_TITLE     = 0
STATE_CONNECT   = 1
STATE_LOBBY     = 2
STATE_GAME      = 3

; Screen layout (32x30 tiles)
SCREEN_WIDTH    = 32
SCREEN_HEIGHT   = 30
