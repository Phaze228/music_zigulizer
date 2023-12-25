const std = @import("std");
const math = std.math;
const Complex = math.Complex;

const I: Complex(f32) = math.complex.sqrt(Complex(f32).init(-1.0, 0));
const PI = std.math.pi;
const PI_CPLX: Complex(f32) = Complex(f32).init(PI, 0);

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
        while (l < sample_count) : (l += 2 * step) {
            const step_cplx = Complex(f32).init(@floatFromInt(step), 0);
            const euler: Complex(f32) = math.complex.exp(PI_CPLX.div(step_cplx).mul(I));
            twiddle = euler;
            // twiddle.im = @floor(twiddle.im);
            // std.debug.print("...............................\n", .{});
            // std.debug.print("Index: {d} | Twiddle Factor: {d} + {d}\n", .{ l, twiddle.re, twiddle.im });
            // std.debug.print("_______________________________________\n", .{});
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

pub fn hamming_window(freqs: []f32, hamming_freqs: []f32, samples: f32) void {
    for (freqs, 0..) |f, i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / samples - 1;
        const hamming: f32 = 0.5 - (0.5 * math.cos(2 * math.pi * t));
        hamming_freqs[i] = f * hamming;
    }
}

pub fn normalizeFFT(freqs: []Complex(f32), max_amp: f32) void {
    const amp: Complex(f32) = Complex(f32).init(max_amp, 0);

    for (freqs, 0..) |f, i| {
        freqs[i] = f.div(amp);
        if (freqs[i].magnitude() >= 1.0) freqs[i] = Complex(f32).init(0, 0);
    }
}

pub fn magToDecibels(magnitude: f32, ref_mag: f32) f32 {
    const mag: f32 = if (magnitude <= 0) 1 else magnitude;
    const val: f32 = 20 * std.math.log10(mag / ref_mag);
    return if (!math.isNan(val)) val else 0.01;
}
