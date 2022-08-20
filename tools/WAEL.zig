//! Convert WAEL music file to bytecode stream
const std = @import("std");
const audio = @import("../src/audio.zig");
const music = audio.music;

const KB = 1024;
const MB = 1024 * KB;

const WAEL = @This();

step: std.build.Step,
builder: *std.build.Builder,
source_path: std.build.FileSource,
output_name: []const u8,
music_data: std.build.GeneratedFile,

pub fn create(b: *std.build.Builder, opt: struct {
    source_path: std.build.FileSource,
    output_name: []const u8,
}) *@This() {
    var result = b.allocator.create(WAEL) catch @panic("memory");
    result.* = WAEL{
        .step = std.build.Step.init(.custom, "convert and embed a ldtk map file", b.allocator, make),
        .builder = b,
        .source_path = opt.source_path,
        .output_name = opt.output_name,
        .music_data = undefined,
    };
    result.*.music_data = std.build.GeneratedFile{ .step = &result.*.step };
    return result;
}

fn make(step: *std.build.Step) !void {
    const this = @fieldParentPtr(WAEL, "step", step);

    const allocator = this.builder.allocator;
    const cwd = std.fs.cwd();

    // Get path to source and output
    const source_src = this.source_path.getPath(this.builder);
    const output = this.builder.getInstallPath(.lib, this.output_name);

    // Open ldtk file and read all of it into `source`
    const source_file = try cwd.openFile(source_src, .{});
    defer source_file.close();
    const source = try source_file.readToEndAlloc(allocator, 10 * MB);
    defer allocator.free(source);

    // TODO Parse WAEL file
    const music_data = try parse(allocator, source);

    // Create array to write data to
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    const writer = data.writer();

    // TODO write bytes into array
    try music_data.write(writer);

    // Open output file and write data into it
    cwd.makePath(this.builder.getInstallPath(.lib, "")) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    try cwd.writeFile(output, data.items);

    this.music_data.path = output;
}

const Event = music.Event;
const Flag = music.Flag;
const Song = music.Song;
const WriteContext = music.WriteContext;
const CursorChannel = music.CursorChannel;
const ControlEvent = music.ControlEvent;

// utility functions
const isDigit = std.ascii.isDigit;
const toLower = std.ascii.toLower;

/// Read locations
const Dynamic = enum(u8) { pp = 1, p = 3, mp = 6, mf = 12, f = 25, ff = 50, fff = 100 };

/// Notes in music are based on fractions of a bar
const Duration = enum(u8) {
    whole = 1,
    half = 2,
    quarter = 4,
    quarter_triplet = 6,
    eighth = 8,
    sixteenth = 16,
    thirtysecond = 32,
    sixtyfourth = 64,
};
const Time = struct {
    /// Length of bar in ticks
    bar: u32 = 0,
    tempo: u32,
    /// Beats in a bar
    beats: u32,
    /// Value of a beat
    beatValue: u32,

    currentTick: u32 = 0,
    tripletTicks: [3]u32 = .{ 0, 0, 0 },

    /// Tempo
    pub fn init() @This() {
        var self = @This(){
            .tempo = 112,
            .beats = 4,
            .beatValue = 4,
        };
        self.updateBar();
        return self;
    }

    pub fn reset(this: *@This()) void {
        this.currentTick = 0;
    }

    /// Appease the timing god by calling this with the proper duration
    pub fn tick(this: *@This(), duration: u32) u32 {
        var ret: u32 = 0;
        if (duration % 3 == 0) {
            // Triplet trouble
            if (this.tripletTicks[2] == 0) this.tripletTicks = this.triplets(duration);
            for (this.tripletTicks) |*tt| {
                if (tt.* == 0) continue;
                ret = tt.*;
                tt.* = 0;
                break;
            }
        } else {
            ret = this.getTicks(duration);
        }
        this.currentTick += ret;
        return ret;
    }

    pub fn barCheck(this: *@This()) bool {
        return this.currentTick % this.bar == 0;
    }

    pub fn setBar(this: *@This(), ticks: u32) void {
        this.bar = ticks;
    }

    pub fn setSpeed(this: *@This(), ticks: u32) void {
        this.setBar(ticks * this.beats);
    }

    fn updateBar(this: *@This()) void {
        this.bar = tempo2bar(this.tempo, this.beats);
    }

    pub fn setTempo(this: *@This(), tempo: u8) void {
        this.bar = (tempo * this.bar) / (this.beats * 60 * 60);
    }

    // TODO: Find out if this only makes sense when using tempo
    pub fn setSig(this: *@This(), beats: u8, beatValue: u8) void {
        const tempo = this.tempo;
        this.beats = beats;
        this.beatValue = beatValue;
        this.bar = @intCast(u8, tempo2bar(tempo, beats));
    }

    pub fn getTicks(this: @This(), duration: u32) u32 {
        return (this.bar * this.beatValue) / (this.beats * duration);
    }

    /// Triplets don't divide evenly, so everything sucks
    pub fn triplets(this: @This(), duration: u32) [3]u32 {
        // Rounds the number down
        const ticks = this.getTicks(duration);
        var ret = [_]u32{ ticks, ticks, ticks };
        // Get remainder
        const rem = ticks % duration;
        var correction = rem / (duration / 3);
        // Make a couple of the triplets longer to compensate for lack of
        // decimals
        var i: u8 = 0;
        while (correction > 0) : (i += 1) {
            ret[i] += 1;
            correction -= 1;
        }
        return ret;
    }
};

test "time keeping" {
    var time = Time.init();
    var tick: u32 = 0;

    // Testing triplets
    tick = time.tick(6);
    tick = time.tick(6);
    tick = time.tick(6);
    tick = time.tick(6);
    tick = time.tick(6);
    tick = time.tick(6);

    try std.testing.expectEqual(true, time.barCheck());

    time = Time.init();
    time.setTempo(112);
    try std.testing.expectEqual(@as(u32, 112), time.tempo);

    time = Time.init();
    time.setTempo(112);
    time.setSig(2, 4);
    try std.testing.expectEqual(@as(u32, 112), time.tempo);
}

const ReadToSymbol = enum { mode, a, d, s, r, freq, glide };
const ReadToGlobal = enum { spd, time, tempo };

const ReadMode = union(enum) {
    Define: u32,
    Set: struct { index: u32, read: ReadToSymbol },
    SetGlobal: ReadToGlobal,
    Part: u32,
    Top,
};

const Sfx = struct { flags: u8, a: u8, d: u8, s: u8, r: u8, freq: u8, glide: u8 };
const SfxList = std.ArrayList(Sfx);

const Instrument = struct { flags: u8, a: u8, d: u8, r: u8 };
const InstrumentList = std.ArrayList(Instrument);

const Part = struct { channel: CursorChannel, address: u16, is_pitched: bool };
const PartList = std.ArrayList(Part);

const SymbolType = enum { Instrument, Part, Song, Sfx };
const Symbol = struct { name: []const u8, sym: SymbolType, index: u32 };
const SymbolList = std.ArrayList(Symbol);

/// Parses a WAEL string into the song struct required by the WAE runner. Can be
/// run at comptime.
/// WAEL is specifically aimed at making music using the WAE runner working in a
/// WASM4 environment. No attempt has been made to generalize it, but feel free
/// to make variations that work in different environments.
/// TODO: Make it work at runtime
pub fn parse(alloc: std.mem.Allocator, buf: []const u8) !WriteContext {
    var songlist = std.ArrayList(std.ArrayList(music.ControlEvent)).init(alloc);
    defer songlist.deinit();
    var eventlist = std.ArrayList(music.Event).init(alloc);

    var currentOctave: u8 = 3;
    var currentDuration: u8 = 4;
    var currentRows: u8 = 0;
    var currentDynamic: Dynamic = .mp;
    // var currentChannel: ?CursorChannel = null;
    var currentInstrument: ?Instrument = null;
    var currentSfx: ?Sfx = null;

    var parts = PartList.init(alloc);
    var instruments = InstrumentList.init(alloc);
    var symbols = SymbolList.init(alloc);
    var sfx = SfxList.init(alloc);

    var readMode: ReadMode = .Top;

    var time = Time.init();

    var lineIter = std.mem.split(u8, buf, "\n");
    lineparse: while (lineIter.next()) |line| {
        var tokIter = std.mem.tokenize(u8, line, " \n\t");
        while (tokIter.next()) |tok| {
            if (tok[0] == '#') continue :lineparse;
            switch (readMode) {
                .Define => |defi| {
                    var symbol = symbols.items[defi];
                    if (tok[0] == ';') {
                        readMode = .Top;
                        if (symbol.sym == .Song) try songlist.items[symbol.index].append(.end);
                        continue; // End definition
                    }
                    switch (symbol.sym) {
                        .Part => {
                            var part = parts.items[symbol.index];
                            switch (tok[0]) {
                                '@' => {
                                    part.channel = std.meta.stringToEnum(CursorChannel, tok[1..tok.len]) orelse return error.InvalidChannel;
                                    parts.items[symbol.index] = part;
                                },
                                '[' => {
                                    time.reset();
                                    // Place goto command in event list w/ temporary value
                                    var position = @intCast(u16, eventlist.items.len);
                                    part.address = position;
                                    part.is_pitched = !(tok.len > 1 and tok[1] == '[');
                                    parts.items[symbol.index] = part;
                                    readMode = .{ .Part = defi };
                                },
                                else => return error.InvalidToken,
                            }
                        },
                        .Instrument => {
                            switch (tok[0]) {
                                '!' => {
                                    readMode = .{ .Set = .{
                                        .read = std.meta.stringToEnum(ReadToSymbol, tok[1..tok.len]) orelse return error.UnknownGlobal,
                                        .index = defi,
                                    } };
                                },
                                else => return error.InvalidToken,
                            }
                        },
                        .Sfx => {
                            switch (tok[0]) {
                                '!' => {
                                    readMode = .{ .Set = .{
                                        .read = std.meta.stringToEnum(ReadToSymbol, tok[1..tok.len]) orelse return error.UnknownGlobal,
                                        .index = defi,
                                    } };
                                },
                                else => return error.InvalidToken,
                            }
                        },
                        .Song => {
                            var s = &songlist.items[symbol.index];
                            if (std.mem.eql(u8, tok, "play")) {
                                const channelTok = tokIter.next() orelse return error.UnexpectedEOF;
                                const partTok = tokIter.next() orelse return error.UnexpectedEOF;

                                const channel = std.meta.stringToEnum(CursorChannel, channelTok[1..channelTok.len]) orelse return error.InvalidChannel;
                                const part = for (symbols.items) |sym| {
                                    if (sym.sym != .Part) continue;
                                    var part = parts.items[sym.index];
                                    if (part.channel != channel) continue;
                                    if (std.mem.eql(u8, sym.name, partTok)) {
                                        break part.address;
                                    }
                                } else {
                                    std.log.warn("Unknown part {s}", .{partTok});
                                    return error.UnknownLabel;
                                };

                                try s.append(ControlEvent.init_play(channel, part));
                            } else if (std.mem.eql(u8, tok, "at")) {
                                const barNumberTok = tokIter.next() orelse return error.UnexpectedEOF;

                                const bars = try std.fmt.parseInt(u16, barNumberTok, 10);

                                try s.append(ControlEvent{ .wait = @intCast(u16, time.bar * bars) });
                            } else if (std.mem.eql(u8, tok, "dalSegno")) {
                                try s.append(ControlEvent{ .goto = 0 });
                            } else return error.InvalidSongCommand;
                        },
                    }
                },
                .Set => |sym| {
                    var symbol = symbols.items[sym.index];
                    var ptr = switch (symbol.sym) {
                        .Instrument => switch (sym.read) {
                            .a => &instruments.items[symbol.index].a,
                            .d => &instruments.items[symbol.index].d,
                            .r => &instruments.items[symbol.index].r,
                            .mode => &instruments.items[symbol.index].flags,
                            else => return error.InvalidSet,
                        },
                        .Sfx => switch (sym.read) {
                            .a => &sfx.items[symbol.index].a,
                            .d => &sfx.items[symbol.index].d,
                            .s => &sfx.items[symbol.index].s,
                            .r => &sfx.items[symbol.index].r,
                            .mode => &sfx.items[symbol.index].flags,
                            .freq => &sfx.items[symbol.index].freq,
                            .glide => &sfx.items[symbol.index].glide,
                        },
                        else => return error.InvalidSet,
                    };
                    var tmp = try std.fmt.parseInt(u8, tok, 16);
                    if (sym.read == .mode) tmp <<= 2;
                    ptr.* = tmp;
                    readMode = switch (symbol.sym) {
                        .Instrument, .Sfx => .{ .Define = sym.index },
                        .Part => .{ .Part = sym.index },
                        else => return error.Unimplemented,
                    };
                },
                .SetGlobal => |readTo| {
                    switch (readTo) {
                        .spd => {
                            time.setSpeed(try std.fmt.parseInt(u8, tok, 10));
                        },
                        .time => {
                            time.setSig(tok[0] - '0', tok[2] - '0');
                        },
                        .tempo => {
                            time.setTempo(try std.fmt.parseInt(u8, tok, 10));
                        },
                    }
                    readMode = .Top;
                },
                .Part => |defi| {
                    var part = parts.items[symbols.items[defi].index];
                    switch (toLower(tok[0])) {
                        ']' => {
                            try eventlist.append(Event.end);
                            readMode = .{ .Define = defi };
                        },
                        '%' => {
                            // try eventlist.append(Event{ .param = mode });
                            var tokInstr = tok[1..tok.len];
                            if (part.is_pitched) {
                                for (symbols.items) |symbol| {
                                    if (symbol.sym != .Instrument) continue;
                                    if (!std.mem.eql(u8, symbol.name, tokInstr)) continue;
                                    var instr = instruments.items[symbol.index];
                                    try eventlist.append(Event{ .param = instr.flags });

                                    currentInstrument = instr;
                                    currentSfx = null;
                                    currentRows = 0; // Trigger adsr handling
                                    break;
                                } else {
                                    std.log.warn("Could not find instrument {s}", .{tokInstr});
                                    return error.UnknownInstrument;
                                }
                            } else {
                                for (symbols.items) |symbol| {
                                    if (symbol.sym != .Sfx) continue;
                                    if (!std.mem.eql(u8, symbol.name, tokInstr)) continue;
                                    var sound = sfx.items[symbol.index];
                                    try eventlist.append(Event{ .param = sound.flags });

                                    currentSfx = sound;
                                    currentInstrument = null;
                                    currentRows = 0; // Trigger adsr handling
                                    break;
                                } else {
                                    std.log.warn("Could not find sfx {s}", .{tokInstr});
                                    return error.UnknownSound;
                                }
                            }
                        },
                        '|' => {
                            if (!time.barCheck()) {
                                std.log.warn("{} % {} = {}", .{
                                    time.currentTick,
                                    time.bar,
                                    time.currentTick % time.bar,
                                });
                                return error.BarCheckFailed;
                            } else continue;
                        },
                        // octave up
                        '>' => currentOctave = std.math.sub(u8, currentOctave, 1) catch return error.OctaveTooLow,
                        // octave down
                        '<' => currentOctave = std.math.add(u8, currentOctave, 1) catch return error.OctaveTooHigh,
                        '(' => {
                            currentDynamic = std.meta.stringToEnum(Dynamic, tok[1 .. tok.len - 1]) orelse return error.InvalidDynamic;
                            try eventlist.append(Event{ .vol = @enumToInt(currentDynamic) });
                        },
                        'o' => if (tok.len > 1) {
                            currentOctave = (tok[1] - '0');
                        } else return error.MissingOctaveNumber,
                        else => {
                            // std.log.warn("{s}", .{tok});
                            var note_res = try parseNote(tok);
                            if (tok.len > 1 and note_res.end != tok.len) {
                                var duration_res = try parseDuration(tok[note_res.end + 1 .. tok.len]);
                                if (duration_res.duration != 0 and duration_res.end > 0) {
                                    currentDuration = duration_res.duration;
                                }
                                // TODO: implement ties (~)
                            }

                            // Update time keeping
                            var tick = time.tick(currentDuration);
                            if (currentRows != tick) {
                                if (currentInstrument) |instr| {
                                    const remainder = tick - (instr.a + instr.d + instr.r);
                                    try eventlist.append(Event.init_adsr(instr.a, instr.d, remainder, instr.r));
                                } else if (currentSfx) |sound| {
                                    try eventlist.append(Event.init_adsr(sound.a, sound.d, sound.s, sound.r));
                                } else return error.BadState;
                                currentRows = @intCast(u8, tick);
                            }

                            if (note_res.note) |note| {
                                if (currentInstrument) |_| try eventlist.append(Event.init_note(ntof(octave(currentOctave) + note), tick));
                                if (currentSfx) |sound| {
                                    if (sound.glide != 0) {
                                        const glideEvent = Event{ .slide = sound.glide };
                                        try eventlist.append(glideEvent);
                                    }
                                    const noteEvent = Event.init_note(ntof(sound.freq), tick);
                                    try eventlist.append(noteEvent);
                                }
                            } else {
                                try eventlist.append(Event.init_rest(tick));
                            }
                        },
                    }
                },
                .Top => {
                    switch (toLower(tok[0])) {
                        ':' => {
                            var t = std.meta.stringToEnum(SymbolType, tokIter.next() orelse return error.UnexpectedEOF) orelse return error.InvalidType;
                            var name = tokIter.next() orelse return error.UnexpectedEOF;
                            switch (t) {
                                .Instrument => {
                                    try instruments.append(Instrument{ .flags = 0, .a = 0, .d = 0, .r = 0 });
                                    try symbols.append(Symbol{ .name = name, .index = @intCast(u32, instruments.items.len - 1), .sym = .Instrument });
                                },
                                .Song => {
                                    try songlist.append(std.ArrayList(music.ControlEvent).init(alloc));
                                    try symbols.append(Symbol{ .name = name, .index = @intCast(u32, songlist.items.len - 1), .sym = .Song });
                                },
                                .Part => {
                                    var part: Part = .{ .channel = .none, .address = 255, .is_pitched = false };
                                    try parts.append(part);
                                    try symbols.append(Symbol{ .name = name, .index = @intCast(u32, parts.items.len - 1), .sym = .Part });
                                },
                                .Sfx => {
                                    try sfx.append(Sfx{ .flags = 0, .a = 0, .d = 0, .s = 0, .r = 0, .freq = 0, .glide = 0 });
                                    try symbols.append(Symbol{ .name = name, .index = @intCast(u32, sfx.items.len - 1), .sym = .Sfx });
                                },
                            }
                            readMode = .{ .Define = @intCast(u32, symbols.items.len - 1) };
                        },
                        '!' => {
                            readMode = .{
                                .SetGlobal = std.meta.stringToEnum(ReadToGlobal, tok[1..tok.len]) orelse return error.UnknownGlobal,
                            };
                        },
                        else => {
                            std.log.warn("Invalid Token: {s}", .{tok});
                            return error.InvalidToken;
                        },
                    }
                },
            }
        }
    }

    var songlist_offsets = try alloc.alloc(u16, songlist.items.len);
    var sum: usize = 0;
    for (songlist.items) |*song, i| {
        songlist_offsets[i] = @intCast(u16, sum);
        sum += song.items.len;
    }

    var songlist_events = try alloc.alloc(music.ControlEvent, sum);
    var index: usize = 0;
    for (songlist.items) |*song| {
        for (song.items) |control_event| {
            songlist_events[index] = control_event;
            index += 1;
        }
        song.deinit();
    }

    return music.WriteContext{
        .songs = songlist_offsets,
        .song_events = songlist_events,
        .events = eventlist.toOwnedSlice(),
    };
}

const NoteRes = struct { note: ?u8, end: usize };
fn parseNote(buf: []const u8) !NoteRes {
    var note: u8 = switch (buf[0]) {
        'c' => 0,
        'd' => 2,
        'e' => 4,
        'f' => 5,
        'g' => 7,
        'a' => 9,
        'b' => 11,
        'r' => return NoteRes{ .note = null, .end = 1 },
        else => return error.InvalidNote,
    };

    var end = if (buf.len > 1)
        for (buf[1..buf.len]) |char, i| {
            switch (char) {
                '+' => note += 1,
                '-' => note -= 1,
                else => break i,
            }
        } else buf.len
    else
        buf.len;
    return NoteRes{ .note = note, .end = end };
}

const DurationRes = struct { duration: u8, end: usize };
fn parseDuration(buf: []const u8) !DurationRes {
    var val: u8 = 0;
    var end: usize = for (buf) |char, i| {
        switch (char) {
            '0', '1', '2', '4', '8', '3', '5', '6', '7', '9' => {
                val = std.math.mul(u8, val, 10) catch return error.DurationMultiply;
                val = std.math.add(u8, val, (char - '0')) catch return error.DurationAdd;
            },
            else => break i,
        }
    } else buf.len;
    return DurationRes{ .duration = val, .end = end };
}

// octave
fn octave(o: u8) u8 {
    return switch (o) {
        0 => 12,
        1 => 24,
        2 => 36,
        3 => 48,
        4 => 60,
        5 => 72,
        6 => 84,
        7 => 96,
        8 => 108,
        9 => 120,
        else => unreachable,
    };
}

// note to frequency
fn ntof(note: u8) u16 {
    const a = 440.0;
    const n = @intToFloat(f32, note);
    return @floatToInt(u16, (a / 32.0) * std.math.pow(f32, 2.0, ((n - 9) / 12.0)));
}

/// Takes a note duration and returns the it as a frame duration (assumes 60 fps)
/// bpm = beats per minute
/// beatValue = lower part of time signature, indicates the value that is equivalent to a beat
/// duration = length of the note
fn note2ticks(bpm: u32, beatValue: u32, duration: u32) u32 {
    // whole = 240, half = 120, quarter = 60, etc.
    const one = (beatValue * 60 * 60);
    const two = bpm * duration;
    const ticks = one / two;
    return ticks;
}

fn tempo2beat(bpm: u32, beats: u32, beatValue: u32) u32 {
    return (beatValue * 60 * 60) / (bpm * beats);
}

fn tempo2bar(bpm: u32, beats: u32) u32 {
    // 60 * 60 == one minute in ticks
    return ((60 * 60) / bpm) * beats;
}

test "note2ticks" {
    const expectEqual = std.testing.expectEqual;
    try expectEqual(tempo2bar(112, 4), 128);
    try expectEqual(tempo2bar(112, 2), 64);

    // 225bpm, 4/4 time
    try expectEqual(note2ticks(225, 4, 64), 1);
    try expectEqual(note2ticks(225, 4, 32), 2);
    try expectEqual(note2ticks(225, 4, 16), 4);
    try expectEqual(note2ticks(225, 4, 8), 8);
    try expectEqual(note2ticks(225, 4, 4), 16);
    try expectEqual(note2ticks(225, 4, 2), 32);
    try expectEqual(note2ticks(225, 4, 1), 64);

    // 112bpm, 4/4 time
    // Technically this is 112.5bpm, but
    // the 0.5 is lost in rounding
    try expectEqual(note2ticks(112, 4, 64), 2);
    try expectEqual(note2ticks(112, 4, 32), 4);
    try expectEqual(note2ticks(112, 4, 16), 8);
    try expectEqual(note2ticks(112, 4, 8), 16);
    try expectEqual(note2ticks(112, 4, 4), 32);
    try expectEqual(note2ticks(112, 4, 2), 64);
    try expectEqual(note2ticks(112, 4, 1), 128);

    // 75bpm, 4/4 time
    try expectEqual(note2ticks(75, 4, 64), 3);
    try expectEqual(note2ticks(75, 4, 32), 6);
    try expectEqual(note2ticks(75, 4, 16), 12);
    try expectEqual(note2ticks(75, 4, 8), 24);
    try expectEqual(note2ticks(75, 4, 4), 48);
    try expectEqual(note2ticks(75, 4, 2), 96);
    try expectEqual(note2ticks(75, 4, 1), 192);

    // 120bpm, 4/4 time
    try expectEqual(note2ticks(120, 4, 1), 120); // whole note = 120 frames
    try expectEqual(note2ticks(120, 4, 2), 60); // whole note = 60 frames
    try expectEqual(note2ticks(120, 4, 4), 30); // quarter note = 30 frames
    try expectEqual(note2ticks(120, 4, 8), 15); // eighth note = 15 frames
    // Any lower values are inexact. I'm going to not think about them for now...
    // TODO: figure out how faster notes will be handled
    // expectEqual(note2ticks(120, 4, 16) , 7.5);    // sixteenth note = 7 frames (inexact)
    // expectEqual(note2ticks(120, 4, 32) , 3.75);  // thirty-second note =  frames

    // 60bpm, 4/4 time
    try expectEqual(note2ticks(60, 4, 4), 60); // quarter note = 60 frames
}
