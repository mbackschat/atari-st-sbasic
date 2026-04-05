#!/usr/bin/env python3
"""Decode tokenized Atari ST BASIC files (.BAS / FBAS.TXT format)."""

import sys
import struct

# Token table: index -> keyword (uppercase)
# Token class $01 (TOKEN1): indices 0x00-0x71
TOKEN1 = {
    0x00: "PRINT", 0x01: "DIM", 0x02: "LIST", 0x03: "SAVE",
    0x04: "LOAD", 0x05: "RUN", 0x06: "CLR", 0x07: "GOTO",
    0x08: "INT", 0x09: "FOR", 0x0A: "TO", 0x0B: "STEP",
    0x0C: "NEXT", 0x0D: "ENDPROC", 0x0E: "GOSUB", 0x0F: "RETURN",
    0x10: "IF", 0x11: "THEN", 0x12: "ELSE", 0x13: "FRE",
    0x14: "CREATE", 0x15: "STRFRE", 0x16: "MERGE", 0x17: "REM",
    0x18: "STOP", 0x19: "HELP", 0x1A: "NEW", 0x1B: "DEF",
    0x1C: "FN", 0x1D: "INPUT", 0x1E: "ON", 0x1F: "OPEN",
    0x20: "CLOSE", 0x21: "SPC", 0x22: "TAB", 0x23: "DATA",
    0x24: "READ", 0x25: "RESTORE", 0x26: "GET", 0x27: "LEN",
    0x28: "STR$", 0x29: "VAL", 0x2A: "FUNCTION", 0x2B: "ASC",
    0x2C: "CHR$", 0x2D: "LEFT$", 0x2E: "RIGHT$", 0x2F: "MID$",
    0x30: "POS", 0x31: "NOT", 0x32: "CMD", 0x33: "POKE",
    0x34: "PEEK", 0x35: "SIN", 0x36: "COS", 0x37: "SQR",
    0x38: "LOG", 0x39: "LN", 0x3A: "EXP10", 0x3B: "TAN",
    0x3C: "ATN", 0x3D: "EXP", 0x3E: "SGN", 0x3F: "ABS",
    0x40: "RND", 0x41: "SYS", 0x42: "CONT", 0x43: "CLS",
    0x44: "WPEEK", 0x45: "WPOKE", 0x46: "LPEEK", 0x47: "LPOKE",
    0x48: "ATANPT", 0x49: "MOD", 0x4A: "GEMDOS", 0x4B: "BIOS",
    0x4C: "XBIOS", 0x4D: "VARPTR", 0x4E: "DIR", 0x4F: "HEX$",
    0x50: "BIN$", 0x51: "CURSOR", 0x52: "PROC", 0x53: "END",
    0x54: "LOCAL", 0x55: "DELETE", 0x56: "INKEY$", 0x57: "WAIT",
    0x58: "SWAP", 0x59: "TRON", 0x5A: "TROFF", 0x5B: "INSTR$",
    0x5C: "CALL", 0x5D: "AESCTRL", 0x5E: "AESINTIN", 0x5F: "AESINTOUT",
    0x60: "AESADRIN", 0x61: "AESADROUT", 0x62: "VDICTRL", 0x63: "VDIINTIN",
    0x64: "VDIINTOUT", 0x65: "VDIPTSIN", 0x66: "VDIPTSOUT", 0x67: "AES",
    0x68: "VDI", 0x69: "CONVERT", 0x6A: "DUMP", 0x6B: "TRACE",
    0x6C: "AND", 0x6D: "OR", 0x6E: "EOR", 0x6F: "AUTO",
    0x70: "EDTAB", 0x71: "LINE",
}

# Token class $02 (TOKEN2)
TOKEN2 = {
    0x00: "LINE",
}

# Token class $03 (TOKEN3)
TOKEN3 = {
    0x00: "LINE",
}

TOKEN_TABLES = {0x01: TOKEN1, 0x02: TOKEN2, 0x03: TOKEN3}

HEADER_MAGIC = b'HEAD'


def decode_file(filepath):
    """Decode a tokenized BASIC file and return list of (line_number, text) tuples."""
    with open(filepath, 'rb') as f:
        data = f.read()

    # Check for HEADER magic
    if data[:4] == HEADER_MAGIC:
        data = data[4:]  # Skip header
        print(f"[Header 'HEAD' found, skipping 4 bytes]", file=sys.stderr)

    lines = []
    pos = 0

    while pos < len(data):
        # Read next-line pointer (4 bytes, big-endian)
        if pos + 8 > len(data):
            break
        next_ptr = struct.unpack('>I', data[pos:pos+4])[0]
        line_num = struct.unpack('>I', data[pos+4:pos+8])[0]

        if next_ptr == 0 or next_ptr == 0xFFFFFFFF:
            break  # End of program

        # Tokenized data starts at pos+8
        data_start = pos + 8
        # Data ends at the next_ptr position (relative to start of data after header)
        # Actually, next_ptr is absolute address - but we're reading from file so
        # compute line data length from next_ptr offset
        if next_ptr > pos:
            line_end = next_ptr
        else:
            # next_ptr might be relative
            line_end = pos + next_ptr

        # Line data extends from data_start to just before next_ptr
        # (minus trailing NUL bytes that terminate the line)
        raw_end = next_ptr
        if raw_end > len(data):
            raw_end = len(data)
        line_data = data[data_start:raw_end]
        # Strip trailing NUL bytes
        while line_data and line_data[-1] == 0:
            line_data = line_data[:-1]
        text = decode_tokens(line_data)
        lines.append((line_num, text))

        # Move to next line
        if next_ptr <= pos:
            break
        pos = next_ptr

    return lines


def decode_tokens(line_data):
    """Decode a tokenized line into readable BASIC text."""
    result = []
    i = 0
    in_string = False
    while i < len(line_data):
        b = line_data[i]

        if in_string:
            if b == 0x22:  # closing quote
                result.append('"')
                in_string = False
            else:
                result.append(chr(b) if 32 <= b < 127 else f'\\x{b:02x}')
            i += 1
            continue

        if b == 0x22:  # opening quote
            result.append('"')
            in_string = True
            i += 1
            continue

        if b in TOKEN_TABLES and i + 1 < len(line_data):
            token_class = b
            token_index = line_data[i + 1]
            table = TOKEN_TABLES[token_class]
            keyword = table.get(token_index, f'?TOKEN{token_class:02x}:{token_index:02x}?')
            result.append(keyword)
            i += 2
            continue

        # Regular character
        if 32 <= b < 127:
            result.append(chr(b))
        elif b == 0:
            break  # end of line
        else:
            result.append(f'\\x{b:02x}')
        i += 1

    return ''.join(result)


def main():
    for filepath in sys.argv[1:]:
        print(f"\n{'='*60}")
        print(f"FILE: {filepath}")
        print(f"{'='*60}")
        lines = decode_file(filepath)
        for line_num, text in lines:
            print(f"{line_num} {text}")


if __name__ == '__main__':
    main()
