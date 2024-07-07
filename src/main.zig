const std = @import("std");
const math = std.math;
const rl = @cImport({
    @cInclude("raylib.h");
});

const Complex = std.math.Complex;
const I = Complex(f32).init(0, -1);
const PI_CPLX = Complex(f32).init(std.math.pi, 0);
const FFT_SIZE: usize = math.pow(i32, 2, 11);
const FFT_SIZE_FLOAT: f32 = math.pow(f32, 2.0, 11);
const SAMPLE_RATE: usize = 48000;
// const SAMPLE_RATE_FLOAT: f32 = 44100;
const MAX_FREQUENCY_BINS: usize = SAMPLE_RATE / 2;
const RESOLUTION: f32 = SAMPLE_RATE / FFT_SIZE_FLOAT / 2;
const MAIN_LABEL = "Drop files to begin";
const BACKGROUND_COLOR = rl.CLITERAL(rl.Color{ .r = 0x17, .g = 0x17, .b = 0x17, .a = 0x12 });
const LOW_FREQ: f32 = 1.0;
// This frequency step is generated from 2 * (frequency_step) ^ width = usable_frequencies
// So for our current configuration it's 2 * f_step ^ 600 = 24000
// Do some log math.... log(12000)/600 = log(x) => 10^(log(12000)/600) = x
const WIDTH: f32 = 600.0;
const HEIGHT: f32 = 800.0;
const FREQ_STEP: f32 = (SAMPLE_RATE / 2) / (RESOLUTION * WIDTH);
const FREQUENCY_STEP: f32 = 1.06;
const DEFAULT_MUSIC_VOLUME: f32 = 0.02;

var loop_counter: usize = 0;
var time_start: i64 = 0;
var time_end: i64 = 0;
var prev_pow: f32 = 0;

pub const Direction = enum { Previous, Next };

const Config = struct {
    background_color: rl.Color = BACKGROUND_COLOR,
    sample_rate: usize = SAMPLE_RATE,
};

const Sample = struct {
    chan1: f32,
    chan2: f32,
};

const Container = struct {
    const Self = @This();
    frames: [FFT_SIZE]f32,
    windowed: [FFT_SIZE]f32,
    frequencies: [FFT_SIZE]Complex(f32),
    amplitudes: [FFT_SIZE / 2]f32,
    last_amp: [FFT_SIZE]f32,
    count: usize = 0,

    pub fn print_magnitudes(self: *Self) void {
        for (self.amplitudes, 0..) |value, i| {
            std.debug.print("{d}: {d}, ", .{ i, value });
        }
        std.debug.print("\n", .{});
    }
};

const TextConfig = struct {
    const Self = @This();
    height: i32 = 69,
    width: i32,

    pub fn heightAsFloat(self: *Self) f32 {
        return @as(f32, @floatFromInt(self.height));
    }

    pub fn widthAsFloat(self: *Self) f32 {
        return @as(f32, @floatFromInt(self.height));
    }
};

var global_container = std.mem.zeroes(Container);

pub fn main() !void {
    var music = Music{ .callback = &getFreqs };
    rl.InitAudioDevice();
    rl.InitWindow(800, 600, "Zigulizer");
    defer rl.CloseAudioDevice();
    rl.SetTargetFPS(30);
    @memset(&global_container.last_amp, 1);
    const window_height: f32 = @floatFromInt(rl.GetRenderHeight());
    const window_width: f32 = @floatFromInt(rl.GetRenderWidth());
    const TEXT_HEIGHT: i32 = 69;
    const TEXT_WIDTH: i32 = rl.MeasureText(MAIN_LABEL, TEXT_HEIGHT);
    const text_width: f32 = @floatFromInt(TEXT_WIDTH);
    const text_height: f32 = @floatFromInt(TEXT_HEIGHT);
    // const cell_width: f32 = SAMPLE_RATE / FFT_SIZE_FLOAT / 2;
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(BACKGROUND_COLOR);
        if (rl.IsFileDropped()) {
            music.initialize(rl.LoadDroppedFiles());
        }
        if (!music.isReady()) {
            rl.DrawText(MAIN_LABEL, @intFromFloat(window_width / 2 - text_width / 2), @intFromFloat(window_height / 2 - text_height / 2), text_height, rl.WHITE);
            if (music.current_file) |_| {
                music.load();
            }
        }
        if (music.isReady()) {
            music.update();
            renderFFT(&global_container.amplitudes, RESOLUTION, window_height, window_width);
        }
        rl.EndDrawing();
        if (rl.IsKeyPressed(rl.KEY_SPACE)) music.pause();
        if (rl.IsKeyPressed(rl.KEY_R)) music.restart();
        if (rl.IsKeyPressed(rl.KEY_G)) music.load();
        if (rl.IsKeyPressed(rl.KEY_U)) music.unloadFiles();
        if (rl.IsKeyPressed(rl.KEY_F)) music.listFiles();
        if (rl.IsKeyPressed(rl.KEY_L)) music.change(Direction.Next);
        if (rl.IsKeyPressed(rl.KEY_H)) music.change(Direction.Previous);
    }
    if (music.isReady()) music.detach();
}
// [][*c]const u8
const Music = struct {
    const Self = @This();
    files: rl.FilePathList = std.mem.zeroes(rl.FilePathList),
    current_file: ?[*c]const u8 = null,
    playing: rl.Music = undefined,
    volume: f32 = DEFAULT_MUSIC_VOLUME,
    callback: *const fn (buf: ?*anyopaque, frames: u32) callconv(.C) void,

    pub fn initialize(self: *Self, files: rl.FilePathList) void {
        if (self.files.count >= files.count) return;
        self.files = files;
        if (self.current_file) |_| {
            std.debug.print("---=File is loaded=---\n", .{});
            return;
        } else {
            std.debug.print("Loading\n", .{});
            self.current_file = self.files.paths[0];
        }
    }

    pub fn isReady(self: *Self) bool {
        return rl.IsMusicReady(self.playing);
    }

    pub fn isPlaying(self: *Self) bool {
        return rl.IsMusicStreamPlaying(self.playing);
    }

    pub fn update(self: *Self) void {
        rl.UpdateMusicStream(self.playing);
    }

    pub fn detach(self: *Self) void {
        rl.DetachAudioStreamProcessor(self.playing.stream, self.callback);
    }

    pub fn unloadFiles(self: *Self) void {
        rl.UnloadDroppedFiles(self.files);
    }

    pub fn setMusic(self: *Self, new_file: *?[*c]const u8) void {
        const files = self.files.paths;
        if (files.count < 1) return;
        if (new_file.* == null) {
            new_file.* = files[0];
        }
        self.current_file = new_file.*;
    }

    pub fn load(self: *Self) void {
        const music_file = self.current_file.?;
        if (self.isPlaying()) {
            rl.StopMusicStream(self.playing);
            rl.DetachAudioStreamProcessor(self.playing.stream, self.callback);
            rl.UnloadMusicStream(self.playing);
            self.playing = rl.LoadMusicStream(music_file);
        } else {
            self.playing = rl.LoadMusicStream(music_file);
        }
        if (self.isReady()) {
            rl.SetMusicVolume(self.playing, self.volume);
            rl.PlayMusicStream(self.playing);
            rl.AttachAudioStreamProcessor(self.playing.stream, self.callback);
        }
    }

    pub fn change(self: *Self, direction: Direction) void {
        if (self.files.count < 2) {
            return;
        }
        var current_place: usize = for (self.files.paths, 0..self.files.count) |file, index| {
            if (file == self.current_file.?) break index;
        } else 0;
        switch (direction) {
            .Previous => {
                current_place = @mod(current_place - 1, self.files.count);
            },
            .Next => {
                current_place = @mod(current_place + 1, self.files.count);
            },
        }
        self.current_file = self.files.paths[current_place];
        return;
    }

    pub fn pause(self: *Self) void {
        if (rl.IsMusicStreamPlaying(self.playing)) rl.PauseMusicStream(self.playing) else rl.PlayMusicStream(self.playing);
    }

    pub fn restart(self: *Self) void {
        rl.StopMusicStream(self.playing);
        rl.PlayMusicStream(self.playing);
    }

    pub fn listFiles(self: *Self) void {
        var i: usize = 0;
        while (i < self.files.count) : (i += 1) {
            std.debug.print("{s:^5} {d:^5}: {s}\n", .{ "File", i, self.files.paths[i] });
        }
        std.debug.print("{s} -> {s} \n", .{ "Current File", self.current_file.? });
    }
};

// USED FOR JUST GETTING THE FRAME AS IT PASSES
pub fn getFreqs(buf: ?*anyopaque, frames: u32) callconv(.C) void {
    const frames_to_copy: usize = @min(FFT_SIZE - global_container.count, frames - 1);
    const samples: *[512][2]f32 = @alignCast(@ptrCast(buf.?));
    for (samples, 0..) |samp, i| {
        const idx: usize = (i + global_container.count) % (global_container.frames.len);
        global_container.frames[idx] = samp[0];
    }

    global_container.count += (global_container.count + frames_to_copy) % FFT_SIZE;

    if (global_container.count >= global_container.frames.len) {
        global_container.count = 0;
        hamming_window(&global_container.frames, &global_container.windowed);
        fft(&global_container.windowed, &global_container.frequencies, FFT_SIZE);
        normalizeFFT(&global_container.frequencies, &global_container.amplitudes);
        // global_container.print_magnitudes();
    }
}

pub fn fft(input_samples: []f32, output_frequencies: []Complex(f32), sample_count: usize) void {
    var step: usize = 1;
    const r: usize = @intFromFloat(@floor(@log2(@as(f32, @floatFromInt(sample_count)))));
    var l: usize = 0;
    var k: usize = 0;
    var p: usize = 0;
    var q: usize = 0;
    while (k < sample_count) : (k += 1) {
        l = reverse_bits(k, r);
        output_frequencies[l] = Complex(f32).init(input_samples[k], 0);
    }

    var twiddle: Complex(f32) = std.mem.zeroes(Complex(f32));
    var twid: Complex(f32) = std.mem.zeroes(Complex(f32));
    k = 0;
    while (k < r) : (k += 1) {
        l = 0;
        const step_cplx = Complex(f32).init(@floatFromInt(step), 0);
        twiddle = math.complex.exp(PI_CPLX.div(step_cplx).mul(I));
        while (l < sample_count) : (l += 2 * step) {
            // const euler: Complex(f32) = math.complex.exp(PI_CPLX.div(step_cplx).mul(I));
            twid = Complex(f32).init(1, 0);
            var n: usize = 0;
            while (n < step) : (n += 1) {
                p = l + n;
                q = p + step;
                output_frequencies[q] = output_frequencies[p].sub(twid.mul(output_frequencies[q]));
                output_frequencies[p] = (output_frequencies[p].mul(Complex(f32).init(2, 0))).sub(output_frequencies[q]);
                twid = twid.mul(twiddle);
            }
        }
        step <<= 1;
    }
}

pub fn reverse_bits(v: usize, k: usize) usize {
    var c: usize = v;
    var l: usize = 0;
    var i: usize = 0;
    while (i < k) : (i += 1) {
        l = (l << 1) + (c & 1);
        c >>= 1;
    }
    return l;
}

pub fn hamming_window(samps: []f32, hamming_samps: []f32) void {
    for (samps, 0..) |f, i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / FFT_SIZE_FLOAT - 1;
        const hamming: f32 = 0.5 - (0.5 * math.cos(2 * math.pi * t));
        hamming_samps[i] = f * hamming; // /(FFT_SIZE_FLOAT / 2);
    }
}

pub fn normalizeAmp(freqs: []Complex(f32), f_amps: []f32) void {
    const max_power: f32 = getMaxPower(freqs);
    // const rms: f32 = getRMSPower(freqs);
    const max_amp: f32 = @max(max_power, 1.0);

    for (freqs, 0..) |f, i| {
        if (i == FFT_SIZE / 2) break;
        const power: f32 = @log10(f.re * f.re + f.im * f.im);
        // var power: f32 = f.magnitude();
        // std.debug.print("{d}:{d}\n", .{ i, power });
        f_amps[i] = power / max_amp;
    }
}

pub fn normalizeFFT(freqs: []Complex(f32), amplitudes: []f32) void {
    var i: usize = 0;
    while (i < FFT_SIZE / 2) : (i += 1) {
        // const res: f32 = freqs[i].magnitude() / @as(f32, @floatFromInt(1 / math.sqrt(freqs.len)));
        const mag: f32 = freqs[i].magnitude();
        amplitudes[i] = mag;
    }
}

pub fn magToDecibels(magnitude: f32, ref_mag: f32) f32 {
    const mag: f32 = if (magnitude <= 0) 1 else magnitude;
    const val: f32 = (20 * std.math.log10(mag / ref_mag));
    return if (!math.isNan(val)) val else 0.01;
}

pub fn getMaxPower(freqs: []Complex(f32)) f32 {
    var max_power: f32 = 1.0;
    for (freqs) |f| {
        const power: f32 = (f.re * f.re + f.im * f.im);
        // const power: f32 = f.magnitude();
        max_power = @max(power, max_power);
    }
    return @log10(max_power);
}

pub fn getRMSPower(freqs: []f32, start: usize, end: usize) f32 {
    var rms: f32 = 0;
    const f_len: f32 = @floatFromInt(freqs.len);
    var q = start;
    const e = if (end > freqs.len) freqs.len - 1 else end;
    while (q < e) : (q += 1) {
        rms += freqs[q] * freqs[q];
    }
    rms /= f_len;
    return math.sqrt(rms);
}

pub fn getAvgPower(freqs: []f32, start: usize, end: usize) f32 {
    var avg_power: f32 = 0;
    var q = start;
    const e = if (end > freqs.len) freqs.len - 1 else end;
    while (q < e) : (q += 1) {
        avg_power += freqs[q];
    }
    avg_power /= @as(f32, @floatFromInt(e));
    return avg_power;
}

pub fn getPeakPower(freqs: []f32, start: usize, end: usize) f32 {
    var peak_power: f32 = 0;
    var q = start;
    var e = if (end > freqs.len or end > FFT_SIZE / 2) (FFT_SIZE / 2) - 1 else end;
    if (e == start and e < freqs.len - 1) e += 1;
    while (q < e) : (q += 1) {
        const power: f32 = freqs[q];
        peak_power = @max(power, peak_power);
    }
    return peak_power;
}

pub fn renderFFT(freqs: []f32, bar_width: f32, height: f32, width: f32) void {
    var curr: f32 = 0;
    _ = bar_width;
    while (curr < FFT_SIZE_FLOAT / 2) : (curr += FREQ_STEP) {
        const x_position: f32 = if (curr < 4) curr * FREQ_STEP else curr + FREQ_STEP;
        const idx: usize = @intFromFloat(curr);
        const max_value: f32 = getPeakPower(freqs, idx, @as(usize, (@intFromFloat(@ceil(curr + RESOLUTION)))));
        const last_value: f32 = global_container.last_amp[idx];
        var smoothed: f32 = undefined;
        if (last_value < max_value) {
            smoothed = last_value * 0.1 + (0.8 * max_value);
        } else {
            smoothed = last_value * 0.8 + (0.2 * max_value);
        }
        if (smoothed < 0) continue;
        drawBars(@floor(x_position), smoothed, height, width);
        if (idx == 0) continue;
        global_container.last_amp[idx] = max_value;
    }
}

pub fn drawBars(x_pos: f32, power: f32, height: f32, width: f32) void {
    const centered_x: f32 = if (@mod(x_pos, 2) == 0) @mod((width / 2) + x_pos, width) else @mod((width / 2) - x_pos, width);
    const bar_color = rl.ColorFromHSV(@mod(centered_x * 0.5, 360), 0.7, 0.8);
    const start = rl.Vector2{ .x = centered_x, .y = height - (power * 2.5) };
    const end = rl.Vector2{ .x = centered_x, .y = height };
    rl.DrawLineEx(start, end, RESOLUTION, bar_color);
}
