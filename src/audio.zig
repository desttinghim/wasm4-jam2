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
            std.log.warn("[event write] {s} {}", .{ @tagName(event), @enumToInt(event) });
            try writer.writeInt(u8, @enumToInt(event), .Little);
            switch (event) {
                .rest => |rest| {
                    try writer.writeInt(u8, rest.duration, .Little);
                },
                .param => |param| {
                    std.log.warn("[event write] param={}", .{ param });
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
            const int_tag = try reader.readInt(u8, .Little);
            const tag = @intToEnum(EventEnum, int_tag);
            w4.tracef("[event read] %s event", @tagName(tag).ptr);
            const data = switch (tag) {
                .rest => Event{ .rest = .{
                    .duration = try reader.readInt(u8, .Little),
                } },
                .param => param: {
                    const param = try reader.readInt(u8, .Little);
                    w4.tracef("[event read] param=%d");
                    break :param Event{ .param = param };
                },
                .adsr => Event{ .adsr = try reader.readInt(u32, .Little) },
                .vol => Event{ .vol = try reader.readInt(u8, .Little) },
                .slide => Event{ .slide = try reader.readInt(u16, .Little) },
                .note => Event{ .note = .{
                    .freq = try reader.readInt(u16, .Little),
                    .duration = try reader.readInt(u8, .Little),
                } },
                .end => .end,
            };
            w4.tracef("[event read] finished reading");
            return data;
        }

        pub fn toByteSize(event: Event) u16 {
            const tag = @sizeOf(EventEnum);
            const data: u16 = switch (event) {
                .rest => @sizeOf(u8),
                .param => @sizeOf(u8),
                .adsr => @sizeOf(u32),
                .vol => @sizeOf(u8),
                .slide => @sizeOf(u16),
                .note => @sizeOf(u16) + @sizeOf(u8),
                .end => 0,
            };
            return tag + data;
        }
    };

    pub const ControlEventEnum = enum(u8) {
        play = 1,
        wait = 2,
        goto = 3,
        end = 0,
    };

    pub const ControlEvent = union(ControlEventEnum) {
        /// Start playing at the specified pattern
        play: struct { channel: CursorChannel, pattern: u8 },
        /// Wait for x ticks
        wait: u16,
        /// Go to song x
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
            const val: ControlEvent = switch (tag) {
                .play => .{ .play = .{
                    .channel = @intToEnum(CursorChannel, try reader.readInt(u8, .Little)),
                    .pattern = try reader.readInt(u8, .Little),
                } },
                .wait => .{ .wait = try reader.readInt(u16, .Little) },
                .goto => .{ .goto = try reader.readInt(u16, .Little) },
                .end => .end,
            };
            return val;
        }

        pub fn toByteSize(control_event: ControlEvent) u16 {
            const tag = @sizeOf(ControlEventEnum);
            const data: u16 = switch (control_event) {
                .play => @sizeOf(u8) + @sizeOf(u8),
                .wait => @sizeOf(u16),
                .goto => @sizeOf(u16),
                .end => 0,
            };
            return tag + data;
        }
    };

    pub const Song = []ControlEvent;

    pub const WriteContext = struct {
        /// Offset into buffer of events
        // patterns: []u16,
        events: []Event,
        /// Offset into buffer of song_events
        songs: []u16,
        song_events: []ControlEvent,

        pub fn write(ctx: WriteContext, writer: anytype) !void {
            // Write control events
            try writer.writeInt(u16, @intCast(u16, ctx.events.len), .Little);
            for (ctx.events) |event, i| {
                std.log.warn("[wae] -- event {} {}", .{ i, event });
                try event.write(writer);
            }
            std.log.warn("[wae] wrote {} events", .{ctx.events.len});

            // Write song offsets
            try writer.writeInt(u16, @intCast(u16, ctx.songs.len), .Little);
            for (ctx.songs) |song, i| {
                std.log.warn("[wae] -- song {} {}", .{ i, song });
                try writer.writeInt(u16, song, .Little);
            }
            std.log.warn("[wae] wrote {} song offsets", .{ctx.songs.len});

            // Write song data
            try writer.writeInt(u16, @intCast(u16, ctx.song_events.len), .Little);
            for (ctx.song_events) |control_event, i| {
                std.log.warn("[wae] -- song event {} {}", .{ i, control_event });
                try control_event.write(writer);
            }
            std.log.warn("[wae] wrote {} song events", .{ctx.song_events.len});

            // try writer.writeInt(u16, @intCast(u16, ctx.patterns.len), .Little);
            // for (ctx.patterns) |pattern, i| {
            //     std.log.warn("[wae] -- pattern {} {}", .{i, pattern});
            //     try writer.writeInt(u16, pattern, .Little);
            // }
            // std.log.warn("[wae] wrote {} patterns", .{ctx.patterns.len});
        }
    };

    pub const Context = struct {
        const Cursor = std.io.FixedBufferStream([]const u8);

        buffer: []const u8,
        /// Event list
        events_start: usize,
        events_count: usize,
        /// Song list
        songs_start: usize,
        songs_count: usize,
        songs: []u16,

        song_events_start: usize,
        song_events_count: usize,

        // patterns_start: usize,
        // patterns_count: usize,
        // patterns: []u16,

        pub fn init(buffer: []const u8) !Context {
            var cursor = Cursor{
                .pos = 0,
                .buffer = buffer,
            };
            var reader = cursor.reader();

            const events_len = try reader.readInt(u16, .Little);
            const events_start = @intCast(u32, try cursor.getPos());

            w4.tracef("[audio context init] events_len=%d", events_len);

            var eventi: usize = 0;
            while (eventi < events_len) : (eventi += 1) {
                _ = try Event.read(reader);
            }

            const songs_len = try reader.readInt(u16, .Little);
            const songs_start = @intCast(u32, try cursor.getPos());
            // const songs_bytes = songs_len * @sizeOf(u16);
            const songs = @ptrCast([]u16, buffer[songs_start .. songs_start + songs_len]);

            w4.tracef("[audio context init] song_len=%d", songs_len);
            var songi: usize = 0;
            while (songi < songs_len) : (songi += 1) {
                const song = try reader.readInt(u16, .Little);
                w4.tracef("[audio context init] song %d: %d", songi, song);
            }

            const song_events_len = try reader.readInt(u16, .Little);
            const song_events_start = @intCast(u32, try cursor.getPos());

            w4.tracef("[audio context init] song_events_len=%d", song_events_len);

            var idx_s_e: usize = 0;
            while (idx_s_e < song_events_len) : (idx_s_e += 1) {
                const event = try ControlEvent.read(reader);
                w4.tracef("[audio context init] song %d: %s", idx_s_e, @tagName(event).ptr);
            }

            // const patterns_len = try reader.readInt(u16, .Little);
            // const patterns_start = @intCast(u32, try cursor.getPos());
            // // const patterns_bytes = patterns_len * @sizeOf(u16);
            // const patterns = @ptrCast([]u16, buffer[patterns_start..patterns_start + patterns_len]);

            // w4.tracef("[audio context init] patterns_len=%d", patterns_len);
            // for (patterns) |pattern, i| {
            //     w4.tracef("[audio context init] patterns %d: %d", i, pattern);
            // }

            return Context{
                .buffer = buffer,
                .events_start = events_start,
                .events_count = events_len,
                .songs_start = songs_start,
                .songs_count = songs_len,
                .songs = songs,
                .song_events_start = song_events_start,
                .song_events_count = song_events_len,
                // .patterns_start = patterns_start,
                // .patterns_count = patterns_len,
                // .patterns = patterns,
            };
        }

        pub fn getEventCursor(ctx: *Context) Cursor {
            return Cursor{ .pos = ctx.events_start, .buffer = ctx.buffer };
        }

        pub fn getSongCursor(ctx: *Context, song: u16) Cursor {
            return Cursor{ .pos = ctx.song_events_start + ctx.songs[song], .buffer = ctx.buffer };
        }

        pub fn getPatternCursor(ctx: *Context, pattern: u16) Cursor {
            var cursor = Cursor{ .pos = ctx.events_start, .buffer = ctx.buffer };
            const reader = cursor.reader();
            var i: usize = 0;
            while (i < pattern) : (i += 1) {
                _ = Event.read(reader) catch @panic("fdsafdf");
            }
            return cursor;
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
        /// Song cursor
        song_cursor: ?Context.Cursor = null,
        current_song_event: ?ControlEvent = null,
        /// Index of the current song
        song: ?u16 = null,
        /// Index of the next song to play
        nextSong: ?u16 = null,
        /// Next frame to read from song_cursor
        next_update_tick: u32 = 0,
        /// Internal counter for timing
        tick_count: u32 = 0,
        /// Song event list cursor. Each audio channel has one
        cursors: [4]?Context.Cursor = .{ null, null, null, null },
        /// Last event
        current_event: [4]?Event = .{ null, null, null, null },

        /// Next tick to process commands at, per channel
        next_channel_tick: [4]u32 = .{ 0, 0, 0, 0 },
        /// Beginning of current pattern
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
            this.current_song_event = null;
            this.next_update_tick = 0;
            this.begin = .{ 0, 0, 0, 0 };
            this.tick_count = 0;
            this.next_channel_tick = .{ 0, 0, 0, 0 };
            this.cursors = .{ null, null, null, null };
            this.current_event = .{ null, null, null, null };
            this.param = .{ 0, 0, 0, 0 };
            this.adsr = .{ 0, 0, 0, 0 };
            this.volume = .{ 0, 0, 0, 0 };
            this.freq = .{ null, null, null, null };
        }

        /// Set the song to play next
        pub fn playSong(this: *@This(), song: u16) void {
            this.reset();
            this.song = song;
            this.song_cursor = this.context.getSongCursor(song);
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
            current_event: *?Event,
            next_channel_tick: *u32,
            cursors: *?Context.Cursor,
            param: *u8,
            adsr: *u32,
            volume: *u8,
            freq: *?u16,
        };
        /// Returns pointers to every register
        fn getChannelState(this: *@This(), channel: usize) ChannelState {
            return ChannelState{
                .begin = &this.begin[channel],
                .current_event = &this.current_event[channel],
                .next_channel_tick = &this.next_channel_tick[channel],
                .cursors = &this.cursors[channel],
                .param = &this.param[channel],
                .adsr = &this.adsr[channel],
                .volume = &this.volume[channel],
                .freq = &this.freq[channel],
            };
        }

        pub fn _controlUpdate(this: *@This()) bool {
            var song_cursor = this.song_cursor orelse return false;
            var song_reader = song_cursor.reader();
            var event = ControlEvent.read(song_reader) catch @panic("_controlUpdate");
            while (this.next_update_tick <= this.tick_count) {
                switch (event) {
                    .play => |p| {
                        // Look up byte offset in pattern table
                        const channel = @enumToInt(p.channel);
                        this.cursors[channel] = this.context.getPatternCursor(p.pattern);
                        // this.begin[channel] = @intCast(u32, );
                        var reader = this.cursors[channel].?.reader();
                        this.current_event[channel] = Event.read(reader) catch @panic("wae controlupdate");
                    },
                    .wait => |w| this.next_update_tick = this.tick_count + w,
                    .goto => |n| {
                        // Find the nth item
                        song_cursor.seekTo(this.context.songs[this.song.?]) catch @panic("wae controlupdate");
                        var i: usize = 0;
                        while (i < n) : (i += 1) {
                            _ = ControlEvent.read(song_reader) catch @panic("wae controlupdate");
                        }
                    },
                    .end => {
                        if (this.nextSong) |next| {
                            this.nextSong = null;
                            this.song_cursor = this.context.getSongCursor(next);
                            song_reader = song_cursor.reader();
                            // event = song[this.contextCursor];
                            // continue;
                        }
                        return false;
                    },
                }
                // if (event != .goto) this.contextCursor += 1;
                event = ControlEvent.read(song_reader) catch @panic("wae controlupdate");
            }
            return true;
        }

        /// Call once per frame. Frames are expected to be at 60 fps.
        pub fn update(this: *@This()) void {
            // Check that there is a song playing
            if (!this._controlUpdate()) return;
            // Increment counter at end of function
            defer this.tick_count += 1;
            for (this.cursors) |cursor_opt, i| {
                var cursor = cursor_opt orelse continue;
                var reader = cursor.reader();
                var state = this.getChannelState(i);
                // Stop once the end of the song is reached
                // if (state.current_event.* == null) continue;
                // Get current event
                var event = state.current_event.* orelse continue; // ;
                // Wait to play note until current note finishes
                if (event == .note and this.tick_count < state.next_channel_tick.*) continue;
                while (state.next_channel_tick.* <= this.tick_count) {
                    switch (event) {
                        .end => {
                            state.cursors.*.?.seekTo(state.begin.*) catch @panic("wae update");
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
                            state.next_channel_tick.* = this.tick_count + rest.duration;
                        },
                        .note => |note| {
                            var freq = if (state.freq.*) |freq| (freq |
                                (@intCast(u32, note.freq) << 16)) else note.freq;
                            defer state.freq.* = null;
                            var flags = @intCast(u8, i) | state.param.*;

                            w4.tone(freq, state.adsr.*, state.volume.*, flags);

                            state.next_channel_tick.* = this.tick_count + note.duration;
                        },
                    }
                    state.current_event.* = Event.read(reader) catch |e| switch (e) {
                        error.EndOfStream => null,
                    };
                    event = state.current_event.* orelse break;
                    // state.cursors.* = (state.cursors.* + 1);
                    // if (state.cursors.* >= this.context.events.len) break;
                }
            }
        }
    };
};
