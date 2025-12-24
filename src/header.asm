; =============================================================================
; NES iNES HEADER
; NROM mapper (mapper 0), 16KB PRG-ROM, 8KB CHR-ROM
; =============================================================================

.segment "HEADER"
    .byte "NES", $1A        ; iNES magic number
    .byte 1                  ; 16KB PRG-ROM (1 x 16KB)
    .byte 1                  ; 8KB CHR-ROM (1 x 8KB)
    .byte $00                ; Mapper 0 (NROM), vertical mirroring
    .byte $00                ; Mapper 0 continued
    .byte 0, 0, 0, 0, 0, 0, 0, 0  ; Padding
