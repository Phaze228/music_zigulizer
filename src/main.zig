const std = @import("std");
const math = std.math;
const rl = @cImport({
    @cInclude("raylib.h");
});

const Complex = std.math.Complex;
const I = Complex(f32).init(0, -1);
const PI_CPLX = Complex(f32).init(std.math.pi, 0);
const FFT_SIZE: usize = math.pow(i32, 2, 13);
const FFT_SIZE_FLOAT: f32 = math.pow(f32, 2.0, 13);
const SAMPLE_RATE: usize = 44100;
// const SAMPLE_RATE_FLOAT: f32 = 44100;
const MAX_FREQUENCY_BINS: usize = SAMPLE_RATE / 2;
const MAIN_LABEL = "Drop files to begin";
const BACKGROUND_COLOR = rl.CLITERAL(rl.Color{ .r = 0x17, .g = 0x17, .b = 0x17, .a = 0x12 });
const LOW_FREQ: f32 = 1.0;
// This frequency step is generated from 2 * (frequency_step) ^ width = usable_frequencies
// So for our current configuration it's 2 * f_step ^ 600 = 24000
// Do some log math.... log(12000)/600 = log(x) => 10^(log(12000)/600) = x
const FREQUENCY_STEP: f32 = 1.06;
const DEFAULT_MUSIC_VOLUME: f32 = 0.01;

var loop_counter: usize = 0;
var time_start: i64 = 0;
var time_end: i64 = 0;
var prev_pow: f32 = 0;

var music: rl.Music = undefined;
var dropped_files: rl.FilePathList = undefined;

const Sample = struct {
    chan1: f32,
    chan2: f32,
};

var global_frames: [FFT_SIZE]f32 = std.mem.zeroes([FFT_SIZE]f32);
var global_windowed_frames: [FFT_SIZE]f32 = std.mem.zeroes([FFT_SIZE]f32);
var global_frame_count: usize = 0;
// var global_frames: [FFT_SIZE]Sample = std.mem.zeroes([FFT_SIZE]Sample);
var global_freqs: [FFT_SIZE]Complex(f32) = std.mem.zeroes([FFT_SIZE]Complex(f32));
var global_amps: [FFT_SIZE / 2]f32 = std.mem.zeroes([FFT_SIZE / 2]f32);
var last_frames_amp: [FFT_SIZE]f32 = undefined;

pub fn main() !void {
    rl.InitAudioDevice();
    rl.InitWindow(800, 600, "Zigulizer");
    defer rl.CloseAudioDevice();
    rl.SetTargetFPS(60);
    @memset(&last_frames_amp, 1);
    var files: rl.FilePathList = std.mem.zeroes(rl.FilePathList);
    var file: ?[*c]const u8 = null; // "src/tacw.mp3";
    const h: f32 = @floatFromInt(rl.GetRenderHeight());
    const w: f32 = @floatFromInt(rl.GetRenderWidth());
    const TEXT_HEIGHT: i32 = 69;
    const TEXT_WIDTH: i32 = rl.MeasureText(MAIN_LABEL, TEXT_HEIGHT);
    const text_width: f32 = @floatFromInt(TEXT_WIDTH);
    const text_height: f32 = @floatFromInt(TEXT_HEIGHT);
    std.debug.print("Sample Rate: {d}\n ", .{music.stream.sampleRate});
    const cell_width: f32 = 44100.0 / FFT_SIZE_FLOAT / 2;
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(BACKGROUND_COLOR);
        if (rl.IsFileDropped()) {
            files = rl.LoadDroppedFiles();
            setMusicFile(&files, &file);
        }
        if (!rl.IsMusicReady(music)) rl.DrawText(MAIN_LABEL, @intFromFloat(w / 2 - text_width / 2), @intFromFloat(h / 2 - text_height / 2), text_height, rl.WHITE);
        if (!rl.IsMusicReady(music) and file != null) {
            loadMusic(&music, file);
        }
        if (rl.IsMusicReady(music)) {
            rl.UpdateMusicStream(music);
            drawFFT(&global_amps, cell_width, h, w);
        }
        rl.EndDrawing();
        if (rl.IsKeyPressed(rl.KEY_SPACE)) pauseMusic(music);
        if (rl.IsKeyPressed(rl.KEY_R)) restartMusic(music);
        if (rl.IsKeyPressed(rl.KEY_G)) loadMusic(&music, file);
        if (rl.IsKeyPressed(rl.KEY_U)) rl.UnloadDroppedFiles(files);
        if (rl.IsKeyPressed(rl.KEY_F)) listFiles(&files, file);
        if (rl.IsKeyPressed(rl.KEY_L)) nextMusicFile(&files, &file);
        if (rl.IsKeyPressed(rl.KEY_H)) prevMusicFile(&files, &file);
    }
    if (rl.IsMusicReady(music)) rl.DetachAudioStreamProcessor(music.stream, getFreqs);
}
// [][*c]const u8
pub fn setMusicFile(file_paths: *rl.FilePathList, f: *?[*c]const u8) void {
    const files = file_paths.paths;
    if (file_paths.count < 1) {
        return;
    }
    if (f.* == null) f.* = files[0];
}
pub fn nextMusicFile(file_paths: *rl.FilePathList, f: *?[*c]const u8) void {
    std.debug.print("Pressed L\n", .{});
    const files = file_paths.paths;
    var i: usize = 0;
    while (i < file_paths.count) : (i += 1) {
        if (f.*.? == files[i] and i < file_paths.count - 1) {
            std.debug.print("Changed:\n{s} -> {s}\n", .{ files[i], files[i + 1] });
            f.* = files[i + 1];
            return;
        } else if (i == file_paths.count - 1) {
            std.debug.print("End of list:\n{s} -> {s}\n", .{ f.*.?, files[0] });
            f.*.? = files[0];
            return;
        }
    }
}
pub fn prevMusicFile(file_paths: *rl.FilePathList, f: *?[*c]const u8) void {
    std.debug.print("Pressed H\n", .{});
    const files = file_paths.paths;
    var i: usize = file_paths.count;
    while (i >= 0) : (i -= 1) {
        if (f.*.? == files[i] and i > 0) {
            std.debug.print("Changed:\n{s} -> {s}\n", .{ files[i], files[i - 1] });
            f.*.? = files[i - 1];
            return;
        } else if (i == 0) {
            std.debug.print("End of list:\n{s} -> {s}\n", .{ f.*.?, files[file_paths.count - 1] });
            f.*.? = files[file_paths.count - 1];
            return;
        }
    }
}
// [*][*c]const u8

pub fn listFiles(file_paths: *rl.FilePathList, f: ?[*c]const u8) void {
    var i: usize = 0;
    while (i < file_paths.count) : (i += 1) {
        std.debug.print("{s:^5} {d:^5}: {s}\n", .{ "File", i, file_paths.paths[i] });
    }
    std.debug.print("{s} -> {s} \n", .{ "Current File", f.? });
}

pub fn loadMusic(m: *rl.Music, f_opt: ?[*c]const u8) void {
    const f = f_opt.?;
    // std.debug.print("Optional: {any} || String: {s} \n", .{ f_opt, f });
    if (rl.IsMusicStreamPlaying(m.*)) {
        rl.StopMusicStream(m.*);
        rl.DetachAudioStreamProcessor(m.stream, getFreqs);
        rl.UnloadMusicStream(m.*);
        m.* = rl.LoadMusicStream(f);
    } else m.* = rl.LoadMusicStream(f);
    if (rl.IsMusicReady(m.*)) {
        rl.SetMusicVolume(m.*, DEFAULT_MUSIC_VOLUME);
        rl.PlayMusicStream(m.*);
        rl.AttachAudioStreamProcessor(m.stream, getFreqs);
    }
}

pub fn pauseMusic(m: rl.Music) void {
    if (rl.IsMusicStreamPlaying(m)) {
        rl.PauseMusicStream(m);
    } else {
        rl.ResumeMusicStream(m);
    }
}

pub fn restartMusic(m: rl.Music) void {
    rl.StopMusicStream(m);
    rl.PlayMusicStream(m);
}

// USED FOR JUST GETTING THE FRAME AS IT PASSES
pub fn getFreqs(buf: ?*anyopaque, frames: u32) callconv(.C) void {
    const frames_to_copy: usize = @min(FFT_SIZE - global_frame_count, frames - 1);
    const samples: *[441][2]f32 = @alignCast(@ptrCast(buf.?));
    for (samples, 0..) |samp, i| {
        const idx: usize = (i + global_frame_count) % (FFT_SIZE - 1);
        global_frames[idx] = samp[0];
    }

    global_frame_count = (global_frame_count + frames_to_copy) % FFT_SIZE;
    hamming_window(&global_frames, &global_windowed_frames);
    fft(&global_windowed_frames, &global_freqs, FFT_SIZE);
    normalizeAmp(&global_freqs, &global_amps);
}

pub fn getFreqs_2(buf: ?*anyopaque, frames: u32) callconv(.C) void {
    const samples: *[441][2]f32 = @alignCast(@ptrCast(buf.?));
    _ = frames;
    for (samples, 0..) |sample, i| {
        global_frames[i] = sample[0];
    }
    hamming_window(&global_frames, &global_windowed_frames);
    fft(&global_windowed_frames, &global_freqs, FFT_SIZE);
    normalizeAmp(&global_freqs, &global_amps);
}

pub fn fft(input_samples: []f32, output_frequencies: []Complex(f32), sample_count: usize) void {
    var step: usize = 1;
    var r: usize = @intFromFloat(@floor(@log2(@as(f32, @floatFromInt(sample_count)))));
    var l: usize = 0;
    var k: usize = 0;
    var p: usize = 0;
    var q: usize = 0;
    while (k < sample_count) : (k += 1) {
        l = reverse_bits(k, r);
        output_frequencies[l] = Complex(f32).init(input_samples[k], 0);
    }

    var twiddle: Complex(f32) = undefined;
    var twid: Complex(f32) = undefined;
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
        var power: f32 = @log10(f.re * f.re + f.im * f.im);
        // var power: f32 = f.magnitude();
        // std.debug.print("{d}:{d}\n", .{ i, power });
        f_amps[i] = power / max_amp;
    }
}

pub fn printFFT(freqs: []Complex(f32), sample_rate: usize, fft_size: usize) void {
    const freq_multiple: usize = sample_rate / fft_size;
    std.debug.print("{s:^15} | {s:^15} | {s:^15} | {s:^15}\n", .{ "Frequency", "Real", "Imaginary", "Power" });
    for (freqs, 0..) |f, i| {
        if (i > fft_size / 2) break;
        std.debug.print("{d:^10}Hz : {d:^10.5} | {d:^10.5} | {d:^10.5}\n", .{ i * freq_multiple, f.re, f.im, math.pow(f32, f.magnitude(), 2.0) });
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
    var f_len: f32 = @floatFromInt(freqs.len);
    var q = start;
    var e = if (end > freqs.len) freqs.len - 1 else end;
    while (q < e) : (q += 1) {
        rms += freqs[q] * freqs[q];
    }
    rms /= f_len;
    return math.sqrt(rms);
}

pub fn getAvgPower(freqs: []f32, start: usize, end: usize) f32 {
    var avg_power: f32 = 0;
    var q = start;
    var e = if (end > freqs.len) freqs.len - 1 else end;
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

pub fn drawFFT(amps: []f32, bin_width: f32, h: f32, w: f32) void {
    const max_bins: f32 = @floatFromInt(MAX_FREQUENCY_BINS);
    const dt: f32 = rl.GetFrameTime();
    var cur: f32 = 1;
    const bins_per_pixel: f32 = (max_bins / bin_width) / w;
    const half_window: f32 = (2 * w / FFT_SIZE_FLOAT) * FFT_SIZE_FLOAT / 4;
    // var step: f32 = math.pow(f32, 10, @log10(FFT_SIZE_FLOAT / 4) / (w / 15));
    var step: f32 = 1.0;
    var start_step: f32 = 1.0;
    // FREQUENCY RESOLUTION = fs / N => 48k / 8192 => 5.85 Hz
    // Each bin should be 5.85 Hz, so we have 4096 * 5.85 => 24,000 Hz of Frequencies.
    // We need to display 24,000 Frequencies in an 600 pixel window but logarithmically view their presence.
    // So that way frequencies from 1 - 3000 are about the same as the frequencies from 3001-24000
    while (cur < (FFT_SIZE_FLOAT / 2)) : (cur = @ceil(start_step + cur * step)) {
        if (cur > (half_window) and start_step != 0) {
            step = math.pow(f32, 10, @log10((FFT_SIZE_FLOAT / 2) / (FFT_SIZE_FLOAT / 4)) / (1 * w / 5));
            start_step = 0;
        }
        const i: usize = @intFromFloat(cur);
        const bpp: usize = @intFromFloat(@ceil(start_step + cur * step));

        const power: f32 = getPeakPower(amps, i, bpp);

        const smoothed_power: f32 = (last_frames_amp[i] * 0.5 + 0.2 * power) * (50 * h / 3) * dt;
        renderDrawings(cur, bins_per_pixel, bin_width, smoothed_power, h, w);
        last_frames_amp[i] += (power - last_frames_amp[i]);
    }
}

// const adjusted_power: f32 = @sqrt(power * cur) / w;
// std.debug.print("{d}-{d} : {d} \n", .{ i, i + bpp, power });
// std.debug.print("cur/power: {d} / {d} \n", .{ cur, power });
// const power = if (cur_power == prev_pow) cur_power * @log2(cur) * 1.2 else cur_power;
// std.debug.print("bin_width: {d} -- bins_per_pixel: {d}\n", .{ bin_width, bins_per_pixel });
pub fn renderDrawings(index: f32, frequency_bin: f32, bin_width: f32, power: f32, win_height: f32, win_width: f32) void {
    _ = frequency_bin;
    const height_float: f32 = power;
    const x_float: f32 = index;
    const y_float: f32 = ((win_height - height_float)); //+ (index * 90 / FFT_SIZE_FLOAT / 2)));
    const ipow: f32 = index * power;
    // const circle_center: rl.Vector2 = rl.Vector2{ .x = win_width / 2, .y = win_height / 3 };
    // const circle_radius: f32 = @mod(power * index, 200);
    const drop_x: f32 = if (index > FFT_SIZE_FLOAT / 4) @mod(ipow * 0.005, (win_width - win_width / 3)) else @mod(ipow * 0.005, 2 * win_width / 3);
    const drops_center: rl.Vector2 = rl.Vector2{ .x = drop_x, .y = @mod(index, win_height / 2) };
    const drops_radius: f32 = @mod(@sqrt(power), win_height * 0.01);

    // const height: i32 = @intFromFloat(height_float);
    // const width: i32 = @intFromFloat(bin_width); //* ((half_ft - index) / half_ft));
    // const y_pos: i32 = @intFromFloat(y_float);
    // const x_pos: i32 = @intFromFloat(x_float);
    const color = rl.ColorFromHSV(@mod(index * 0.2, 350), 0.6, 0.9);
    const start_position = rl.Vector2{ .x = x_float, .y = y_float };
    const end_position = rl.Vector2{ .x = x_float, .y = win_height };

    // std.debug.print("Index: {d} | Height: {d} \n", .{ index, height_float });
    // rl.DrawRectangle(x_pos, y_pos, width, height, color);
    rl.DrawLineEx(start_position, end_position, bin_width / 2, color);
    rl.DrawCircleV(drops_center, drops_radius, color);
    // rl.DrawRing(circle_center, @mod(power, 150), circle_radius, 0, 360, 6, color);
    // rl.DrawCircleV(circle_center, circle_radius, color);
    // rl.DrawCircleV(start_position, @sqrt((bin_width * height_float) / 20), color);
}
//
// const normalizer_ratio: Complex(f32) = Complex(f32).init(1.0, 0).div(amp);
// pub fn callback(buf: ?*anyopaque, frames: u32) callconv(.C) void {
//     const capacity = global_frames.len;
//     if (frames > 0) {
//         const bp: *[1024]Sample = @alignCast(@ptrCast(buf.?));
//         const frame = if (frames > global_frames.len) global_frames.len else frames;
//         if (frame > global_frame_count or global_frame_count > capacity) {
//             global_frames = std.mem.zeroes([1024]Sample);
//         }
//         for (bp, 0..1024) |samp, i| {
//             global_frames[i] = samp;
//         }
//         global_frame_count = frame;
//     }
//
// }

// for (global_frames, 0..) |sample, i| {
//     const s: f32 = sample.chan1;
//     const h: f32 = @floatFromInt(rl.GetRenderHeight());
//     const m: f32 = @floatFromInt(i);
//     const x_pos: i32 = @intFromFloat(cell_width * m);
//     const y_pos: i32 = if (s > 0) std.math.lossyCast(i32, h / 2 - h / 2 * s) else @intFromFloat(h / 2);
//     const rect_height: i32 = if (s > 0) std.math.lossyCast(i32, (h / 2 * s)) else std.math.lossyCast(i32, (h / 2 * s * (-1.0)));
//     rl.DrawRectangle(x_pos, y_pos, @intFromFloat(cell_width * 2), rect_height, rl.RED);
// }
//pub fn drawMusic(freqs: []Complex(f32), cell_width: f32, h: f32, w: f32) void {
//     var max_amplitude: f32 = 0;
//     _ = max_amplitude;
//     const WINDOW_MAX: f32 = w / cell_width;
//     // x ^ ( 1/ Samples/second)
//     const SMOOTHING_FACTOR = math.pow(f32, 10, 1 / 441);
//     var max_power: f32 = 0;
//     var f: f32 = LOW_FREQ;
//     // for (freqs) |freq| {
//     //     if (@fabs(freq.magnitude()) > max_amplitude) max_amplitude = (freq.magnitude());
//     // }
//     for (freqs) |freq| {
//         const power: f32 = freq.im * freq.re;
//         if (power > max_power) max_power = power;
//     }
//     // if (max_amplitude == 0) return;
//     var cur: f32 = 0;
//     while (f < FFT_SIZE_FLOAT) : (f = @ceil(f * FREQUENCY_STEP)) {
//         // var avg_amp: f32 = 0;
//         var current_power: f32 = 0;
//         var middle_freqs: f32 = f;
//         while (middle_freqs < @ceil(f * FREQUENCY_STEP) and middle_freqs < FFT_SIZE_FLOAT) : (middle_freqs += 1) {
//             const f_idx: usize = @intFromFloat(@floor(middle_freqs));
//             const p = freqs[f_idx].re * freqs[f_idx].im;
//             current_power = @max(current_power, p);
//         }
//         if (max_power == 0) return;
//         const bin_position: f32 = math.pow(f32, (f / FFT_SIZE_FLOAT), 1.0 / 2.0) * WINDOW_MAX;
//         const bin: usize = @intFromFloat(bin_position);
//         const amp: f32 = @fabs(magToDecibels(current_power, 1.0) / magToDecibels(max_power, 1.0));
//         const smoothed_amp: f32 = last_frames_amp[bin] * SMOOTHING_FACTOR + amp * (1 - SMOOTHING_FACTOR);
//         const x_pos: i32 = @intFromFloat(@floor(cell_width * bin_position));
//         const y_pos: i32 = @intFromFloat(@floor(h - @floor(h / 2.0 * smoothed_amp)));
//         const height: i32 = @intFromFloat(@floor(smoothed_amp * h / 2.0));
//         const width: i32 = @intFromFloat(amp * cell_width);
//         const color = rl.ColorFromHSV(@mod(cur * 2, 350), 0.6, 0.9);
//         // if (amp > 1) std.debug.print("POSITIVE -> Total Amp: {d} gotten from AVERAGE: {d} and MAX: {d}\n", .{ amp, amp_sum, max_sum });
//         // if (amp < 0) std.debug.print("NEGATIVE -> Total Amp: {d} gotten from AVERAGE: {d} and MAX: {d}\n", .{ amp, current_power, max_power });
//         // std.debug.print("CURRENT: {d} | FREQUENCY: {d} | AMP: {d:.16} |  x_pos: {d:.3} | y_pos: {d:.3} | height: {d:.3} | color = {any} \n", .{ cur, f, amp, x_pos, y_pos, height, color });
//         // rl.DrawCircle(x_pos, y_pos, amp * (h / 10), color);
//         // const amp_sum: f32 = magToDecibels(avg_amp, 1.0);
//         // const max_sum: f32 = magToDecibels(max_amplitude, 1.0);
//         // const amp: f32 = if (@fabs(amp_sum / max_sum) < 1) @fabs(amp_sum / max_sum) else 0.01;
//
//         rl.DrawRectangle(x_pos, y_pos, width, height, color);
//         last_frames_amp[bin] = amp;
//         cur += 1;
//     }
//     // std.debug.print("Final Cur -> {d} | Final Freq -> {d}\n", .{ cur, f });
// }
