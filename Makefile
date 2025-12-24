# Nintendo NES Rachel Client Makefile
# Uses ca65/ld65 from cc65 suite

CA65 = ca65
LD65 = ld65

SRC_DIR = src
BUILD_DIR = build
TARGET = $(BUILD_DIR)/rachel.nes

SOURCES = $(SRC_DIR)/main.asm $(SRC_DIR)/chr.asm
OBJECTS = $(BUILD_DIR)/main.o $(BUILD_DIR)/chr.o
CONFIG = rachel.cfg

.PHONY: all clean

all: $(BUILD_DIR) $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/main.o: $(SRC_DIR)/main.asm $(SRC_DIR)/header.asm $(SRC_DIR)/init.asm \
                     $(SRC_DIR)/equates.asm $(SRC_DIR)/display.asm $(SRC_DIR)/input.asm \
                     $(SRC_DIR)/game.asm $(SRC_DIR)/rubp.asm $(SRC_DIR)/net/serial.asm
	$(CA65) -o $@ $(SRC_DIR)/main.asm

$(BUILD_DIR)/chr.o: $(SRC_DIR)/chr.asm
	$(CA65) -o $@ $(SRC_DIR)/chr.asm

$(TARGET): $(OBJECTS) $(CONFIG)
	$(LD65) -o $@ -C $(CONFIG) $(OBJECTS)

clean:
	rm -rf $(BUILD_DIR)
