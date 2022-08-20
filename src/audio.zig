const w4 = @import("wasm4.zig");
const std = @import("std");

pub const music = struct {
    pub const Flag = struct {
        pub const Pulse1: u8 = w4.TONE_PULSE1;
        pub const Pulse2: u8 = w4.TONE_PULSE2;
        pub const Triangle: u8 = w4.TONE_TRIANGLE;
        pub const Noise: u8 = w4.TONE_NOISE;
        pub const Mode1: u8 = w4.TONE_MODE1;
        pub const Mode2: u8 = w4.TONE_MODE2;
        pub const Mode3: u8 = w4.TONE_MODE3;
        pub const Mode4: u8 = w4.TONE_MODE4;
    };

    pub const EventEnum = enum {
        rest,
        param,
        adsr,
        vol,
        slide,
        note,
        end,
    };

    pub const Event = union(EventEnum) {
        /// Rests for the currently set duration
        rest: struct { duration: u8 },
        /// Sets a parameter for the current cursor. Currently only used on the
        /// Pulse1 and Pulse2 channels to set the duty cycle
        param: u8,
        /// Sets attack and decay registers
        adsr: u32,
        /// Sets volume register
        vol: u8,
        /// Set start freq of slide
        slide: u16,
        /// Outputs note with freq and values in register
        note: struct { freq: u16, duration: u8 },
        /// Signifies end of part, tells cursor to go back to beginning
        end,

        const Self = @This();
        pub fn init_adsr(a: u32, d: u32, s: u32, r: u32) Self {
            return Self{ .adsr = a << 24 | d << 16 | r << 8 | s };
        }
        pub fn init_note(f: u16, dur: u32) Self {
            return Self{ .note = .{ .freq = f, .duration = @intCast(u8, dur) } };
        }
        pub fn init_rest(dur: u32) Self {
            return Self{ .rest = .{ .duration = @intCast(u8, dur) } };
        }

        pub fn write(event: Event, writer: anytype) !void {
            try writer.writeInt(u8, @enumToInt(event), .Little);
            switch (event) {
                .rest => |rest| {
                    try writer.writeInt(u8, rest.duration, .Little);
                },
                .param => |param| {
                    try writer.writeInt(u8, param, .Little);
                },
                .adsr => |adsr| {
                    try writer.writeInt(u32, adsr, .Little);
                },
                .vol => |vol| {
                    try writer.writeInt(u8, vol, .Little);
                },
                .slide => |slide| {
                    try writer.writeInt(u16, slide, .Little);
                },
                .note => |note| {
                    try writer.writeInt(u16, note.freq, .Little);
                    try writer.writeInt(u8, note.duration, .Little);
                },
                .end => {},
            }
        }

        pub fn read(reader: anytype) !Event {
            const tag = @intToEnum(EventEnum, try reader.readInt(u8, .Little));
            switch (tag) {
                .rest => return Event{ .rest = .{
                    .duration = try reader.readInt(u8, .Little),
                } },
                .param => return Event{ .param = try reader.readInt(u8, .Little) },
                .adsr => return Event{ .adsr = try reader.readInt(u32, .Little) },
                .vol => return Event{ .vol = try reader.readInt(u8, .Little) },
                .slide => return Event{ .slide = try reader.readInt(u16, .Little) },
                .note => return Event{ .note = .{
                    .freq = try reader.readInt(u16, .Little),
                    .duration = try reader.readInt(u8, .Little),
                } },
                .end => return .end,
            }
        }
    };

    pub const ControlEventEnum = enum(u8) {
        play = 1,
        wait = 2,
        goto = 3,
        end = 0,
    };

    pub const ControlEvent = union(ControlEventEnum) {
        play: struct { channel: CursorChannel, pattern: u8 },
        wait: u16,
        goto: u16,
        end,

        pub fn init_play(channel: CursorChannel, pattern: u32) @This() {
            return @This(){ .play = .{ .channel = channel, .pattern = @intCast(u8, pattern) } };
        }

        pub fn write(control_event: ControlEvent, writer: anytype) !void {
            try writer.writeInt(u8, @enumToInt(control_event), .Little);
            switch (control_event) {
                .play => |play| {
                    try writer.writeInt(u8, @enumToInt(play.channel), .Little);
                    try writer.writeInt(u8, play.pattern, .Little);
                },
                .wait => |wait| try writer.writeInt(u16, wait, .Little),
                .goto => |goto| try writer.writeInt(u16, goto, .Little),
                .end => {},
            }
        }

        pub fn read(reader: anytype) !ControlEvent {
            const tag = @intToEnum(ControlEventEnum, try reader.readInt(u8, .Little));
            const val = switch (tag) {
                .play => .{ .play = .{
                    try reader.readInt(u8, .Little),
                    try reader.readInt(u8, .Little),
                } },
                .wait => .{ .wait = try reader.readInt(u16, .Little) },
                .goto => .{ .goto = try reader.readInt(u16, .Little) },
                .end => .end,
            };
            return val;
        }
    };

    pub const Song = []ControlEvent;

    pub const WriteContext = struct {
        events: []Event,
        /// Song list
        songs: []u16,
        song_events: []ControlEvent,

        pub fn write(ctx: WriteContext, writer: anytype) !void {
            // Write control events
            try writer.writeInt(u16, @intCast(u16, ctx.events.len), .Little);
            for (ctx.events) |event| {
                try event.write(writer);
            }
            // Write song offsets
            try writer.writeInt(u16, @intCast(u16, ctx.songs.len), .Little);
            for (ctx.songs) |song| {
                try writer.writeInt(u16, song, .Little);
            }
            // Write song data
            for (ctx.song_events) |control_event| {
                try control_event.write(writer);
            }
        }
    };

    pub const Context = struct {
        const Cursor = std.io.FixedBufferStream([]const u8);
        cursor: Cursor,
        // Event list
        events_start: usize,
        events_count: usize,
        /// Song list
        songs_start: usize,
        songs_count: usize,

        song_events_start: usize,
        song_events_count: usize,

        pub fn read(buffer: []const u8) !Context {
            var cursor = Cursor{
                .pos = 0,
                .buffer = buffer,
            };
            var reader = cursor.reader();

            const events_len = try reader.readInt(u16, .Little);
            const events_start = @intCast(u32, try cursor.getPos());

            var eventi: usize = 0;
            while (eventi < events_len) : (eventi += 1) {
                _ = try Event.read(reader);
            }

            const songs_len = try reader.readInt(u16, .Little);
            const songs_start = @intCast(u32, try cursor.getPos());
            const songs_bytes = songs_len * @sizeOf(u16);

            try cursor.seekTo(songs_start + songs_bytes);

            const song_events_len = try reader.readInt(u16, .Little);
            const song_events_start = @intCast(u32, try cursor.getPos());

            return Context{
                .cursor = cursor,
                .events_start = events_start,
                .events_count = events_len,
                .songs_start = songs_start,
                .songs_count = songs_len,
                .song_events_start = song_events_start,
                .song_events_count = song_events_len,
            };
        }
    };

    /// What channel each cursor corresponds to
    pub const CursorChannel = enum(u8) {
        p1 = w4.TONE_PULSE1,
        p2 = w4.TONE_PULSE2,
        tri = w4.TONE_TRIANGLE,
        noise = w4.TONE_NOISE,
        any,
        none,
    };

    pub const WAE = struct {
        /// Pointer to the song data structure
        context: Context,
        /// Index of the current song
        song: ?u16 = null,
        /// Index of the next song to play
        nextSong: ?u16 = null,
        /// Index into current song
        contextCursor: u16 = 0,
        /// Next frame to update contextCursor
        contextNext: u32 = 0,
        /// Internal counter for timing
        counter: u32 = 0,
        /// Next tick to process commands at, per channel
        next: [4]u32 = .{ 0, 0, 0, 0 },
        /// Indexes into song event list. Each audio channel has one
        cursor: [4]?u32 = .{ null, null, null, null },
        /// Beginning of current loop
        begin: [4]u32 = .{ 0, 0, 0, 0 },
        /// Parameter byte for each channel. Only used by
        /// PULSE1 and PULSE2 for setting duty cycle
        param: [4]u8 = .{ 0, 0, 0, 0 },
        /// Bit Format:
        /// a = attack, d = decay, r = release, s = sustain
        /// aaaaaaaa dddddddd rrrrrrrr ssssssss
        /// The duration of the note is determined by summing each of the components.
        adsr: [4]u32 = .{ 0, 0, 0, 0 },
        /// Values can range from 0 to 100. Values outside that range are undefined
        /// behavior.
        volume: [4]u8 = .{ 0, 0, 0, 0 },
        /// If this value is set, it is used as the initial frequency in a slide.
        /// It is assumed this will only be set at the beginning of a slide.
        freq: [4]?u16 = .{ 0, 0, 0, 0 },

        pub fn init(context: Context) @This() {
            return @This(){
                .context = context,
            };
        }

        /// Clear state
        pub fn reset(this: *@This()) void {
            this.song = null;
            this.contextCursor = 0;
            this.contextNext = 0;
            this.begin = .{ 0, 0, 0, 0 };
            this.counter = 0;
            this.next = .{ 0, 0, 0, 0 };
            this.cursor = .{ null, null, null, null };
            this.param = .{ 0, 0, 0, 0 };
            this.adsr = .{ 0, 0, 0, 0 };
            this.volume = .{ 0, 0, 0, 0 };
            this.freq = .{ null, null, null, null };
        }

        /// Set the song to play next
        pub fn playSong(this: *@This(), song: u16) void {
            this.reset();
            this.song = song;
        }

        pub fn setNextSong(this: *@This(), song: u16) void {
            if (this.song == null) {
                this.playSong(song);
                return;
            }
            this.nextSong = song;
        }

        const ChannelState = struct {
            begin: *u32,
            next: *u32,
            cursor: *u32,
            param: *u8,
            adsr: *u32,
            volume: *u8,
            freq: *?u16,
        };
        /// Returns pointers to every register
        fn getChannelState(this: *@This(), channel: usize) ChannelState {
            return ChannelState{
                .begin = &this.begin[channel],
                .next = &this.next[channel],
                .cursor = &this.cursor[channel].?,
                .param = &this.param[channel],
                .adsr = &this.adsr[channel],
                .volume = &this.volume[channel],
                .freq = &this.freq[channel],
            };
        }

        pub fn _controlUpdate(this: *@This()) bool {
            var songIndex = this.song orelse return false;
            var song = this.context.songs.slice()[songIndex].slice();
            var event = song[this.contextCursor];
            while (this.contextNext <= this.counter) {
                switch (event) {
                    .play => |p| {
                        const channel = @enumToInt(p.channel);
                        this.cursor[channel] = p.pattern;
                        this.begin[channel] = p.pattern;
                    },
                    .wait => |w| this.contextNext = this.counter + w,
                    .goto => |a| this.contextCursor = a,
                    .end => {
                        if (this.nextSong) |next| {
                            this.song = next;
                            this.nextSong = null;
                            song = this.context.songs.slice()[next].slice();
                            this.contextCursor = 0;
                            event = song[this.contextCursor];
                            continue;
                        }
                        this.song = null;
                        return false;
                    },
                }
                if (event != .goto) this.contextCursor += 1;
                event = song[this.contextCursor];
            }
            return true;
        }

        /// Call once per frame. Frames are expected to be at 60 fps.
        pub fn update(this: *@This()) void {
            if (!this._controlUpdate()) return;
            // Increment counter at end of function
            defer this.counter += 1;
            // Only attempt to update if we have a song
            const song = this.context;
            const events = song.events.constSlice();
            for (this.cursor) |c, i| {
                if (c == null) continue;
                var state = this.getChannelState(i);
                // Stop once the end of the song is reached
                if (state.cursor.* >= song.events.len) continue;
                // Get current event
                var event = events[state.cursor.*];
                // Wait to play note until current note finishes
                if (event == .note and this.counter < state.next.*) continue;
                while (state.next.* <= this.counter) {
                    event = events[state.cursor.*];
                    switch (event) {
                        .end => {
                            state.cursor.* = state.begin.*;
                        },
                        .param => |param| {
                            // w4.trace("param");
                            state.param.* = param;
                        },
                        .adsr => |adsr| state.adsr.* = adsr,
                        .vol => |vol| state.volume.* = vol,
                        .slide => |freq| state.freq.* = freq,
                        .rest => |rest| {
                            // w4.trace("rest");
                            state.next.* = this.counter + rest.duration;
                        },
                        .note => |note| {
                            var freq = if (state.freq.*) |freq| (freq |
                                (@intCast(u32, note.freq) << 16)) else note.freq;
                            defer state.freq.* = null;
                            var flags = @intCast(u8, i) | state.param.*;

                            w4.tone(freq, state.adsr.*, state.volume.*, flags);

                            state.next.* = this.counter + note.duration;
                        },
                    }
                    state.cursor.* = (state.cursor.* + 1);
                    if (state.cursor.* >= song.events.len) break;
                }
            }
        }
    };
};
