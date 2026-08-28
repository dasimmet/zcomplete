//! Cross-platform binary section extractor.
//! Uses the Zig standard library (`std.elf`, `std.macho`, `std.coff`) to parse and extract
//! embedded .zcomplete WebAssembly sections from ELF, Mach-O, and PE/COFF executables.

const std = @import("std");
const elf = std.elf;
const macho = std.macho;
const coff = std.coff;

pub const BinaryFormat = enum {
    elf,
    macho,
    pe_coff,
    unknown,
};

fn readStruct(comptime T: type, bytes: []const u8, offset: usize) ?T {
    if (offset + @sizeOf(T) > bytes.len) return null;
    var res: T = undefined;
    @memcpy(std.mem.asBytes(&res), bytes[offset .. offset + @sizeOf(T)]);
    return res;
}

pub fn detectFormat(bytes: []const u8) BinaryFormat {
    if (bytes.len < 4) return .unknown;

    if (std.mem.startsWith(u8, bytes, elf.MAGIC)) {
        return .elf;
    }

    if (std.mem.startsWith(u8, bytes, "MZ")) {
        return .pe_coff;
    }

    const magic = std.mem.readInt(u32, bytes[0..4], .little);
    const magic_be = std.mem.readInt(u32, bytes[0..4], .big);

    if (magic == macho.MH_MAGIC_64 or magic == macho.MH_MAGIC or
        magic == macho.MH_CIGAM_64 or magic == macho.MH_CIGAM or
        magic_be == macho.FAT_MAGIC or magic_be == macho.FAT_CIGAM or
        magic_be == macho.FAT_MAGIC_64 or magic_be == macho.FAT_CIGAM_64)
    {
        return .macho;
    }

    return .unknown;
}

pub fn matchSectionName(found: []const u8, target: []const u8) bool {
    const trimmed_found = std.mem.trim(u8, found, "\x00 ");
    const trimmed_target = std.mem.trim(u8, target, "\x00 ");

    if (std.mem.eql(u8, trimmed_found, trimmed_target)) return true;

    // Handle Mach-O segment/section name conventions: "__DATA,__zcomplete", "__zcomplete", "zcomplete"
    if (std.mem.lastIndexOfScalar(u8, trimmed_found, ',')) |comma| {
        const sect = trimmed_found[comma + 1 ..];
        if (matchSectionName(sect, target)) return true;
    }

    const clean_found = std.mem.trimStart(u8, trimmed_found, "._");
    const clean_target = std.mem.trimStart(u8, trimmed_target, "._");

    if (std.mem.eql(u8, clean_found, clean_target)) return true;

    // Handle 8-byte truncation in COFF (e.g. ".zcomple" for ".zcomplete")
    if (clean_found.len >= 5 and std.mem.startsWith(u8, clean_target, clean_found)) return true;
    if (clean_target.len >= 5 and std.mem.startsWith(u8, clean_found, clean_target)) return true;

    return false;
}

pub fn extractSection(gpa: std.mem.Allocator, bytes: []const u8, section_name: []const u8) !?[]u8 {
    return switch (detectFormat(bytes)) {
        .elf => extractElf(gpa, bytes, section_name),
        .macho => extractMachO(gpa, bytes, section_name),
        .pe_coff => extractPeCoff(gpa, bytes, section_name),
        .unknown => null,
    };
}

pub fn extractSectionFromFile(io: std.Io, gpa: std.mem.Allocator, file_path: []const u8, section_name: []const u8) !?[]u8 {
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const file_bytes = std.Io.Dir.cwd().readFileAlloc(
        io,
        file_path,
        arena,
        .unlimited,
    ) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };

    return extractSection(gpa, file_bytes, section_name);
}

fn extractElf(gpa: std.mem.Allocator, bytes: []const u8, section_name: []const u8) !?[]u8 {
    var reader = std.Io.Reader.fixed(bytes);
    const header = elf.Header.read(&reader) catch return null;

    var it = header.iterateSectionHeadersBuffer(bytes);

    // Locate section string table
    var strtab: []const u8 = &.{};
    var idx: usize = 0;
    while (it.next() catch null) |shdr| : (idx += 1) {
        if (idx == header.shstrndx) {
            if (shdr.sh_offset + shdr.sh_size <= bytes.len) {
                strtab = bytes[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size];
            }
            break;
        }
    }

    if (strtab.len == 0) return null;

    it = header.iterateSectionHeadersBuffer(bytes);
    while (it.next() catch null) |shdr| {
        if (shdr.sh_name < strtab.len) {
            const name_slice = strtab[shdr.sh_name..];
            const name_len = std.mem.indexOfScalar(u8, name_slice, 0) orelse name_slice.len;
            const name = name_slice[0..name_len];

            if (matchSectionName(name, section_name)) {
                if (shdr.sh_offset + shdr.sh_size <= bytes.len) {
                    return try gpa.dupe(u8, bytes[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size]);
                }
            }
        }
    }

    return null;
}

fn extractMachO(gpa: std.mem.Allocator, bytes: []const u8, section_name: []const u8) !?[]u8 {
    if (bytes.len < @sizeOf(macho.mach_header)) return null;

    const magic_be = std.mem.readInt(u32, bytes[0..4], .big);

    // Universal FAT binary
    if (magic_be == macho.FAT_MAGIC or magic_be == macho.FAT_CIGAM) {
        const fat_hdr = readStruct(macho.fat_header, bytes, 0) orelse return null;
        const nfat = std.mem.bigToNative(u32, fat_hdr.nfat_arch);
        var offset: usize = @sizeOf(macho.fat_header);

        for (0..nfat) |_| {
            const arch = readStruct(macho.fat_arch, bytes, offset) orelse break;
            const arch_offset = std.mem.bigToNative(u32, arch.offset);
            const arch_size = std.mem.bigToNative(u32, arch.size);
            offset += @sizeOf(macho.fat_arch);

            if (arch_offset + arch_size <= bytes.len) {
                if (try extractMachO(gpa, bytes[arch_offset .. arch_offset + arch_size], section_name)) |res| {
                    return res;
                }
            }
        }
        return null;
    }

    const magic_le = std.mem.readInt(u32, bytes[0..4], .little);
    const is_64 = (magic_le == macho.MH_MAGIC_64 or magic_be == macho.MH_MAGIC_64 or magic_le == macho.MH_CIGAM_64);
    const is_be = (magic_be == macho.MH_MAGIC_64 or magic_be == macho.MH_MAGIC);
    const endian: std.builtin.Endian = if (is_be) .big else .little;

    const header_size: usize = if (is_64) @sizeOf(macho.mach_header_64) else @sizeOf(macho.mach_header);
    if (bytes.len < header_size) return null;

    const ncmds = if (is_64) blk: {
        const hdr = readStruct(macho.mach_header_64, bytes, 0) orelse return null;
        break :blk if (is_be) @byteSwap(hdr.ncmds) else hdr.ncmds;
    } else blk: {
        const hdr = readStruct(macho.mach_header, bytes, 0) orelse return null;
        break :blk if (is_be) @byteSwap(hdr.ncmds) else hdr.ncmds;
    };

    var offset: usize = header_size;

    for (0..ncmds) |_| {
        const lc = readStruct(macho.load_command, bytes, offset) orelse break;
        const cmd: u32 = if (is_be) @byteSwap(@intFromEnum(lc.cmd)) else @intFromEnum(lc.cmd);
        const cmdsize: u32 = if (is_be) @byteSwap(lc.cmdsize) else lc.cmdsize;
        if (cmdsize < @sizeOf(macho.load_command) or offset + cmdsize > bytes.len) break;

        if (is_64 and cmd == @intFromEnum(macho.LC.SEGMENT_64)) {
            if (readStruct(macho.segment_command_64, bytes, offset)) |seg| {
                const nsects = if (endian != @import("builtin").target.cpu.arch.endian())
                    @byteSwap(seg.nsects)
                else
                    seg.nsects;

                var sect_offset = offset + @sizeOf(macho.segment_command_64);
                for (0..nsects) |_| {
                    const sec = readStruct(macho.section_64, bytes, sect_offset) orelse break;

                    const sectname_raw = &sec.sectname;
                    const sectname_len = std.mem.indexOfScalar(u8, sectname_raw, 0) orelse sectname_raw.len;
                    const sectname = sectname_raw[0..sectname_len];

                    const size = if (endian != @import("builtin").target.cpu.arch.endian()) @byteSwap(sec.size) else sec.size;
                    const file_offset = if (endian != @import("builtin").target.cpu.arch.endian()) @byteSwap(sec.offset) else sec.offset;

                    if (matchSectionName(sectname, section_name)) {
                        if (file_offset + size <= bytes.len) {
                            return try gpa.dupe(u8, bytes[file_offset .. file_offset + size]);
                        }
                    }
                    sect_offset += @sizeOf(macho.section_64);
                }
            }
        } else if (!is_64 and cmd == @intFromEnum(macho.LC.SEGMENT)) {
            if (readStruct(macho.segment_command, bytes, offset)) |seg| {
                const nsects = if (endian != @import("builtin").target.cpu.arch.endian())
                    @byteSwap(seg.nsects)
                else
                    seg.nsects;

                var sect_offset = offset + @sizeOf(macho.segment_command);
                for (0..nsects) |_| {
                    const sec = readStruct(macho.section, bytes, sect_offset) orelse break;

                    const sectname_raw = &sec.sectname;
                    const sectname_len = std.mem.indexOfScalar(u8, sectname_raw, 0) orelse sectname_raw.len;
                    const sectname = sectname_raw[0..sectname_len];

                    const size = if (endian != @import("builtin").target.cpu.arch.endian()) @byteSwap(sec.size) else sec.size;
                    const file_offset = if (endian != @import("builtin").target.cpu.arch.endian()) @byteSwap(sec.offset) else sec.offset;

                    if (matchSectionName(sectname, section_name)) {
                        if (file_offset + size <= bytes.len) {
                            return try gpa.dupe(u8, bytes[file_offset .. file_offset + size]);
                        }
                    }
                    sect_offset += @sizeOf(macho.section);
                }
            }
        }

        offset += cmdsize;
    }

    return null;
}

fn extractPeCoff(gpa: std.mem.Allocator, bytes: []const u8, section_name: []const u8) !?[]u8 {
    if (bytes.len < 0x40) return null;

    const pe_offset = std.mem.readInt(u32, bytes[0x3C..0x40], .little);
    if (pe_offset + 4 + @sizeOf(coff.Header) > bytes.len) return null;

    if (!std.mem.eql(u8, bytes[pe_offset .. pe_offset + 4], "PE\x00\x00")) {
        return null;
    }

    const coff_header_offset = pe_offset + 4;
    const header = readStruct(coff.Header, bytes, coff_header_offset) orelse return null;

    const num_sections = header.number_of_sections;
    const symtab_ptr = header.pointer_to_symbol_table;
    const num_symbols = header.number_of_symbols;
    const opt_header_size = header.size_of_optional_header;

    const strtab_offset: ?usize = if (symtab_ptr > 0 and num_symbols > 0)
        symtab_ptr + num_symbols * 18
    else
        null;

    const section_headers_offset = coff_header_offset + @sizeOf(coff.Header) + opt_header_size;

    for (0..num_sections) |i| {
        const sec_offset = section_headers_offset + i * @sizeOf(coff.SectionHeader);
        const sec = readStruct(coff.SectionHeader, bytes, sec_offset) orelse break;

        const name_bytes = &sec.name;
        var name_buf: [256]u8 = undefined;
        var name: []const u8 = "";

        if (name_bytes[0] == '/' and strtab_offset != null and strtab_offset.? < bytes.len) {
            const offset_str = std.mem.trim(u8, name_bytes[1..], "\x00 ");
            if (std.fmt.parseInt(usize, offset_str, 10)) |str_idx| {
                const strtab = bytes[strtab_offset.?..];
                if (str_idx < strtab.len) {
                    const str_slice = strtab[str_idx..];
                    const len = std.mem.indexOfScalar(u8, str_slice, 0) orelse str_slice.len;
                    name = str_slice[0..len];
                }
            } else |_| {}
        }

        if (name.len == 0) {
            const len = std.mem.indexOfScalar(u8, name_bytes, 0) orelse name_bytes.len;
            @memcpy(name_buf[0..len], name_bytes[0..len]);
            name = name_buf[0..len];
        }

        const virt_size = sec.virtual_size;
        const raw_size = sec.size_of_raw_data;
        const raw_ptr = sec.pointer_to_raw_data;

        if (matchSectionName(name, section_name)) {
            const actual_size: usize = if (virt_size > 0 and virt_size <= raw_size) virt_size else raw_size;
            if (raw_ptr + actual_size <= bytes.len) {
                return try gpa.dupe(u8, bytes[raw_ptr .. raw_ptr + actual_size]);
            }
        }
    }

    return null;
}

test "detect binary formats" {
    try std.testing.expectEqual(BinaryFormat.elf, detectFormat("\x7fELF\x02\x01\x01\x00" ++ "\x00" ** 8));
    try std.testing.expectEqual(BinaryFormat.pe_coff, detectFormat("MZ\x90\x00" ++ "\x00" ** 8));
    try std.testing.expectEqual(BinaryFormat.macho, detectFormat(&[_]u8{ 0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01 }));
}

test "match section names" {
    try std.testing.expect(matchSectionName(".zcomplete", ".zcomplete"));
    try std.testing.expect(matchSectionName("__zcomplete", ".zcomplete"));
    try std.testing.expect(matchSectionName("__DATA,__zcomplete", ".zcomplete"));
    try std.testing.expect(matchSectionName(".zcomple", ".zcomplete"));
    try std.testing.expect(matchSectionName(".zcomplete\x00\x00", ".zcomplete"));
}

test "extractSection from synthetic ELF64" {
    var buf = [_]u8{0} ** 512;
    // ELF Header (64-bit LE)
    @memcpy(buf[0..4], elf.MAGIC);
    buf[elf.EI.CLASS] = elf.ELFCLASS64;
    buf[elf.EI.DATA] = elf.ELFDATA2LSB;
    buf[elf.EI.VERSION] = 1;
    std.mem.writeInt(u64, buf[40..48], 64, .little); // e_shoff = 64
    std.mem.writeInt(u16, buf[58..60], @sizeOf(elf.Elf64_Shdr), .little); // e_shentsize
    std.mem.writeInt(u16, buf[60..62], 3, .little); // e_shnum = 3
    std.mem.writeInt(u16, buf[62..64], 1, .little); // e_shstrndx = 1

    // Section 1: .shstrtab
    const sec1 = 64 + @sizeOf(elf.Elf64_Shdr);
    std.mem.writeInt(u64, buf[sec1 + 24 .. sec1 + 32], 256, .little); // sh_offset = 256
    std.mem.writeInt(u64, buf[sec1 + 32 .. sec1 + 40], 24, .little); // sh_size = 24

    // Section 2: .zcomplete
    const sec2 = sec1 + @sizeOf(elf.Elf64_Shdr);
    std.mem.writeInt(u32, buf[sec2 .. sec2 + 4], 11, .little); // sh_name = 11 (".zcomplete")
    std.mem.writeInt(u64, buf[sec2 + 24 .. sec2 + 32], 300, .little); // sh_offset = 300
    std.mem.writeInt(u64, buf[sec2 + 32 .. sec2 + 40], 12, .little); // sh_size = 12

    // Shstrtab data at 256: "\x00.shstrtab\x00.zcomplete\x00"
    const strtab = "\x00.shstrtab\x00.zcomplete\x00";
    @memcpy(buf[256 .. 256 + strtab.len], strtab);

    // Section data at 300
    const expected = "\x00asm\x01\x00\x00\x00test";
    @memcpy(buf[300 .. 300 + expected.len], expected);

    const extracted = try extractSection(std.testing.allocator, &buf, ".zcomplete");
    try std.testing.expect(extracted != null);
    defer std.testing.allocator.free(extracted.?);
    try std.testing.expectEqualStrings(expected, extracted.?);
}

test "extractSection from synthetic Mach-O 64" {
    var buf = [_]u8{0} ** 512;
    const cmd_size: u32 = @sizeOf(macho.segment_command_64) + @sizeOf(macho.section_64);

    // mach_header_64
    std.mem.writeInt(u32, buf[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, buf[16..20], 1, .little); // ncmds = 1
    std.mem.writeInt(u32, buf[20..24], cmd_size, .little); // sizeofcmds

    // LC_SEGMENT_64 at 32
    const seg_off = @sizeOf(macho.mach_header_64);
    std.mem.writeInt(u32, buf[seg_off .. seg_off + 4], @intFromEnum(macho.LC.SEGMENT_64), .little);
    std.mem.writeInt(u32, buf[seg_off + 4 .. seg_off + 8], cmd_size, .little);
    std.mem.writeInt(u32, buf[seg_off + 64 .. seg_off + 68], 1, .little); // nsects = 1

    // Data at 300
    const expected = "\x00asm\x01\x00\x00\x00macho";
    @memcpy(buf[300 .. 300 + expected.len], expected);

    // section_64
    const s_off = seg_off + @sizeOf(macho.segment_command_64);
    @memcpy(buf[s_off .. s_off + 11], "__zcomplete");
    std.mem.writeInt(u64, buf[s_off + 40 .. s_off + 48], expected.len, .little); // size
    std.mem.writeInt(u32, buf[s_off + 48 .. s_off + 52], 300, .little); // file_offset = 300

    const extracted = try extractSection(std.testing.allocator, &buf, ".zcomplete");
    try std.testing.expect(extracted != null);
    defer std.testing.allocator.free(extracted.?);
    try std.testing.expectEqualStrings(expected, extracted.?);
}

test "extractSection from synthetic PE/COFF" {
    var buf = [_]u8{0} ** 512;
    // DOS header
    @memcpy(buf[0..2], "MZ");
    std.mem.writeInt(u32, buf[0x3C..0x40], 64, .little); // e_lfanew = 64

    // PE signature at 64
    @memcpy(buf[64..68], "PE\x00\x00");

    // COFF Header at 68
    std.mem.writeInt(u16, buf[68 + 2 .. 68 + 4], 1, .little); // num_sections = 1
    std.mem.writeInt(u16, buf[68 + 16 .. 68 + 18], 0, .little); // opt_header_size = 0

    // Data at 300
    const expected = "\x00asm\x01\x00\x00\x00pe_cf";
    @memcpy(buf[300 .. 300 + expected.len], expected);

    // Section header at 68 + @sizeOf(coff.Header) = 88
    const s_off = 68 + @sizeOf(coff.Header);
    @memcpy(buf[s_off .. s_off + 8], ".zcomple");
    std.mem.writeInt(u32, buf[s_off + 8 .. s_off + 12], expected.len, .little); // virtual_size
    std.mem.writeInt(u32, buf[s_off + 16 .. s_off + 20], expected.len, .little); // raw_size
    std.mem.writeInt(u32, buf[s_off + 20 .. s_off + 24], 300, .little); // raw_ptr = 300

    const extracted = try extractSection(std.testing.allocator, &buf, ".zcomplete");
    try std.testing.expect(extracted != null);
    defer std.testing.allocator.free(extracted.?);
    try std.testing.expectEqualStrings(expected, extracted.?);
}
