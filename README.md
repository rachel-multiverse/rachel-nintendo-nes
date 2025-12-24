# Rachel - Nintendo NES Client

A Rachel card game client for the Nintendo Entertainment System.

## Platform Details

- **CPU**: Ricoh 2A03 (6502 without decimal mode)
- **RAM**: 2KB internal (the ultimate constraint!)
- **VRAM**: 2KB for nametables
- **Display**: 256x240, tile-based via PPU
- **Controller**: Standard NES controller
- **Platform ID**: 0x00C0 (192)

## Building

Requires cc65 suite (ca65 assembler, ld65 linker):

```bash
# Install cc65 (macOS)
brew install cc65

# Build
make
```

Output: `build/rachel.nes` (iNES format ROM)

## Controls

- **D-Pad Left/Right**: Move cursor
- **A**: Toggle card selection
- **B**: Play selected cards
- **Select**: Draw card
- **Start**: Begin game (title screen)

## Hardware Setup

The NES has no built-in serial port. This client assumes a theoretical
controller port adapter that provides ESP8266 WiFi connectivity via
bit-banged serial on controller port 2.

## Architecture Notes

The NES presents unique challenges:

- **2KB RAM**: RUBP buffers alone use 128 bytes (6.25% of RAM!)
- **No text mode**: All graphics via tile-based PPU
- **CHR-ROM**: Font stored in dedicated character ROM
- **Mapper 0 (NROM)**: Simplest mapper, 16KB PRG + 8KB CHR

## Memory Budget

```
Zero Page ($00-$FF):     ~32 bytes used
Stack ($100-$1FF):       256 bytes reserved
RAM ($200-$7FF):         ~1.5KB available
  - Network buffers:     128 bytes
  - Game state:          ~100 bytes
  - Remaining:           ~1.3KB
```

## Files

- `src/main.asm` - Entry point and game loop
- `src/header.asm` - iNES ROM header
- `src/init.asm` - Hardware initialization
- `src/equates.asm` - Constants and hardware addresses
- `src/display.asm` - PPU text rendering
- `src/input.asm` - Controller reading
- `src/game.asm` - Game logic and rendering
- `src/rubp.asm` - Protocol implementation
- `src/net/serial.asm` - Serial via controller port
- `src/chr.asm` - Character ROM (font)
- `rachel.cfg` - Linker configuration

## Protocol

Uses RUBP (Rachel Universal Binary Protocol):
- 64-byte fixed-size messages
- "RACH" magic header
- Platform ID: 0x00C0 (NES)

## License

MIT License - See LICENSE file
