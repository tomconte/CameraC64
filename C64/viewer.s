; Camera C64's viewer for pictures in the standard VIC-II modes: standard,
; multicolour and extended colour text, and hires and multicolour bitmaps.
;
; The program loads at $0801 and starts with SYS 2061. The parameters follow
; the code, filled in by C64Core's .prg writer (Program.swift), and the
; picture's data follows them:
;
;   parameters+0   values for $d011, $d016, $d018, $d020, $d021, $d022,
;                  $d023 and $d024
;   parameters+8   the VIC-II bank, as bits 0-1 of $dd00 (0 is $c000-$ffff)
;   parameters+9   the number of blocks to copy, at least 1
;   parameters+10  per block, 7 bytes: source, destination, length (each
;                  low byte first), then the value for $01 during the copy
;
; The program copies each block into place, shows the picture, and resets
; the C64 when a key is pressed.

        .setcpu "6502"

entry   = $f7                   ; the current block's entry in the table
count   = $f9                   ; blocks left to copy
pages   = $fa                   ; whole pages left in the current block
source  = $fb
target  = $fd

        .segment "CODE"

        ; 10 SYS 2061
        .word basic_end, 10
        .byte $9e, "2061", 0
basic_end:
        .word 0

start:  sei
        cld
        lda #<blocks
        sta entry
        lda #>blocks
        sta entry+1
        lda block_count
        sta count

next_block:
        ldy #0
        lda (entry),y
        sta source
        iny
        lda (entry),y
        sta source+1
        iny
        lda (entry),y
        sta target
        iny
        lda (entry),y
        sta target+1
        iny
        lda (entry),y           ; length, low byte: bytes after the pages
        tax
        iny
        lda (entry),y           ; length, high byte: whole pages
        sta pages
        iny
        lda (entry),y
        sta $01

        ldy #0
        lda pages
        beq partial_page
whole_page:
        lda (source),y
        sta (target),y
        iny
        bne whole_page
        inc source+1
        inc target+1
        dec pages
        bne whole_page
partial_page:
        cpx #0
        beq block_done
last_bytes:
        lda (source),y
        sta (target),y
        iny
        dex
        bne last_bytes
block_done:
        lda #$37                ; BASIC, KERNAL and I/O visible again
        sta $01

        lda entry
        clc
        adc #7
        sta entry
        bcc :+
        inc entry+1
:       dec count
        bne next_block

        lda $dd00
        and #%11111100
        ora bank
        sta $dd00
        lda #0
        sta $d015               ; no sprites
        lda registers+1
        sta $d016
        lda registers+2
        sta $d018
        lda registers+3
        sta $d020
        lda registers+4
        sta $d021
        lda registers+5
        sta $d022
        lda registers+6
        sta $d023
        lda registers+7
        sta $d024
        lda registers+0         ; last, as it turns the display on
        sta $d011

        ; Wait until no key is down, as RETURN may still be from RUN, then
        ; for a key, and reset.
        lda #0
        sta $dc00               ; read every column of the keyboard
released:
        lda $dc01
        cmp #$ff
        bne released
pressed:
        lda $dc01
        cmp #$ff
        beq pressed
        jmp ($fffc)

; Filled in by the .prg writer.
parameters:
registers = parameters
bank = parameters + 8
block_count = parameters + 9
blocks = parameters + 10
