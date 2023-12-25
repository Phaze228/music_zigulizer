/* DLBFFT - GST visualization plugin
 * Copyright (c) 2011 Daniel Beer <dlbeer@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA  02110-1301  USA
 */

#include <stdint.h>
#include <string.h>
#include <gst/gst.h>
#include <gst/fft/gstffts16.h>
#include <gst/video/video.h>

#include "dlbfft.h"

G_DEFINE_TYPE(GstDLBFFT, gst_dlbfft, GST_TYPE_ELEMENT);

/************************************************************************
 * FFT processing and drawing
 */

static void process_slice(GstDLBFFT *fft)
{
	const int freqs = fft->slice_samples / 2;
	int f_start = 0;
	int i;
	const float smoothing = powf(GST_DLBFFT_SMOOTHING,
					(float)(fft->slice_samples) /
					(float)(fft->rate));

	gst_fft_s16_window(fft->fft, fft->slice_buf, GST_FFT_WINDOW_HAMMING);
	gst_fft_s16_fft(fft->fft, fft->slice_buf, fft->spectrum);

	for (i = 0; i < GST_DLBFFT_BINS; i++) {
		int f_end = round(powf(((float)(i + 1)) /
			(float)GST_DLBFFT_BINS, GST_DLBFFT_GAMMA) * freqs);
		int f_width;
		int j;
		float bin_power = 0.0f;

		if (f_end > freqs)
			f_end = freqs;

		f_width = f_end - f_start;
		if (f_width <= 0)
			f_width = 1;

		for (j = 0; j < f_width; j++) {
			const GstFFTS16Complex *s =
				&fft->spectrum[f_start + j];
			float p = s->r * s->r + s->i * s->i;

			if (p > bin_power)
				bin_power = p;
		}

		bin_power = log(bin_power);
		if (bin_power < 0.0f)
			bin_power = 0.0f;

		fft->power[i] = fft->power[i] * smoothing +
			(bin_power * GST_DLBFFT_SCALE * (1.0f - smoothing));

		f_start = f_end;
	}
}

static void draw_frame(GstDLBFFT *fft, uint32_t *pixdata)
{
	const int bar_spacing = fft->width / GST_DLBFFT_BINS;
	const int bar_width = bar_spacing * 3 / 4;
	int i;

	memset(pixdata, 0, fft->vbuf_size);

	for (i = 0; i < GST_DLBFFT_BINS; i++) {
		int rect_height = fft->height * fft->power[i];
		int y;

		if (rect_height > fft->height)
			rect_height = fft->height;

		for (y = 0; y < rect_height; y++) {
			uint32_t *row =
				pixdata + (fft->height - y - 1) * fft->width +
					i * bar_spacing;
			int x;

			for (x = 0; x < bar_width; x++)
				row[x] = GST_DLBFFT_COLOR;
		}
	}
}

static void process_init(GstDLBFFT *fft)
{
	fft->slice_buf = NULL;
	fft->fft = NULL;
	fft->spectrum = NULL;

	fft->slice_samples = 0;
	fft->slice_len = 0;
	fft->rate_counter = 0;
}

static void process_free(GstDLBFFT *fft)
{
	if (fft->slice_buf)
		free(fft->slice_buf);

	if (fft->fft)
		gst_fft_s16_free(fft->fft);

	if (fft->spectrum)
		free(fft->spectrum);

	process_init(fft);
}

static int process_setup(GstDLBFFT *fft)
{
	process_free(fft);

	fft->slice_samples = 2;

	while (fft->slice_samples * GST_DLBFFT_SLICE_RATE < fft->rate)
		fft->slice_samples <<= 1;

	fft->slice_buf = malloc(sizeof(fft->slice_buf[0]) *
				fft->slice_samples);
	if (!fft->slice_buf)
		return -1;

	fft->fft = gst_fft_s16_new(fft->slice_samples, 0);
	if (!fft->fft) {
		process_free(fft);
		return -1;
	}

	fft->spectrum = malloc(sizeof(fft->spectrum[0]) *
			       fft->slice_samples / 2);
	if (!fft->spectrum) {
		process_free(fft);
		return -1;
	}

	memset(fft->power, 0, sizeof(fft->power));
	return 0;
}

/************************************************************************
 * Object methods
 */

static GstFlowReturn alloc_buffer(GstDLBFFT *fft, GstBuffer **buffer)
{
	if (!GST_PAD_CAPS(fft->src_pad)) {
		const GstCaps *mine =
			gst_pad_get_pad_template_caps(fft->src_pad);
		GstCaps *theirs = gst_pad_peer_get_caps(fft->src_pad);
		GstCaps *both;
		GstStructure *str;

		if (theirs) {
			both = gst_caps_intersect(theirs, mine);
			gst_caps_unref(theirs);
		} else {
			both = gst_caps_ref((GstCaps *)mine);
		}

		if (gst_caps_is_empty(both)) {
			gst_caps_unref(both);
			return GST_FLOW_NOT_NEGOTIATED;
		}

		str = gst_caps_get_structure(both, 0);
		gst_structure_fixate_field_nearest_int(str, "width", 320);
		gst_structure_fixate_field_nearest_int(str, "height", 240);
		gst_structure_fixate_field_nearest_fraction(str,
			"framerate", fft->rate, fft->slice_samples);

		gst_pad_set_caps(fft->src_pad, both);
		gst_caps_unref(both);
	}

	return gst_pad_alloc_buffer_and_set_caps(fft->src_pad,
		GST_BUFFER_OFFSET_NONE, fft->vbuf_size,
		GST_PAD_CAPS(fft->src_pad), buffer);
}

static GstFlowReturn handle_frame(GstDLBFFT *fft)
{
	GstFlowReturn r;
	GstBuffer *outbuf;

	r = alloc_buffer(fft, &outbuf);
	if (r != GST_FLOW_OK)
		return r;

	draw_frame(fft, (uint32_t *)GST_BUFFER_DATA(outbuf));
	return gst_pad_push(fft->src_pad, outbuf);
}

static GstFlowReturn collect_samples(GstDLBFFT *fft,
				     int16_t *samples, int nsamp)
{
	GstFlowReturn ret = GST_FLOW_OK;
	int i;

	/* Downmix and collect samples */
	for (i = 0; i < nsamp; i += fft->channels) {
		int total = 0;
		int j;

		for (j = 0; j < fft->channels; j++)
			total += samples[i + j];

		fft->slice_buf[fft->slice_len++] = total / fft->channels;

		if (fft->slice_len >= fft->slice_samples) {
			GstFlowReturn r;

			fft->slice_len = 0;
			process_slice(fft);
			r = handle_frame(fft);

			if (r != GST_FLOW_OK)
				ret = r;
		}
	}

	return ret;
}

static GstFlowReturn sink_chain(GstPad *pad, GstBuffer *inbuf)
{
	GstDLBFFT *fft = GST_DLBFFT(gst_pad_get_parent(pad));
	GstFlowReturn ret;

	ret = collect_samples(fft, (int16_t *)GST_BUFFER_DATA(inbuf),
			GST_BUFFER_SIZE(inbuf) / sizeof(int16_t));
	gst_buffer_unref(inbuf);

	return ret;
}

static gboolean sink_setcaps(GstPad *pad, GstCaps *caps)
{
	GstDLBFFT *fft = GST_DLBFFT(gst_pad_get_parent(pad));
	GstStructure *str = gst_caps_get_structure(caps, 0);

	if (!(gst_structure_get_int(str, "channels", &fft->channels) &&
	      gst_structure_get_int(str, "rate", &fft->rate)))
		return FALSE;

	if (process_setup(fft) < 0)
		return FALSE;

	return TRUE;
}

static gboolean sink_event(GstPad *pad, GstEvent *event)
{
	GstDLBFFT *fft = GST_DLBFFT(gst_pad_get_parent(pad));

	return gst_pad_push_event(fft->src_pad, event);
}

static gboolean src_setcaps(GstPad *pad, GstCaps *caps)
{
	GstDLBFFT *fft = GST_DLBFFT(gst_pad_get_parent(pad));
	GstStructure *str = gst_caps_get_structure(caps, 0);

	if (!(gst_structure_get_int(str, "width", &fft->width) &&
	      gst_structure_get_int(str, "height", &fft->height) &&
	      gst_structure_get_fraction(str, "framerate",
			&fft->fps_n, &fft->fps_d)))
		return FALSE;

	fft->vbuf_size = fft->width * fft->height * sizeof(uint32_t);
	fft->rate_counter = 0;

	return TRUE;
}

static gboolean src_event(GstPad *pad, GstEvent *event)
{
	GstDLBFFT *fft = GST_DLBFFT(gst_pad_get_parent(pad));

	return gst_pad_push_event(fft->sink_pad, event);
}

static GstStateChangeReturn dlbfft_change_state(GstElement *element,
						GstStateChange trans)
{
	GstDLBFFT *fft = GST_DLBFFT(element);

	if (trans == GST_STATE_CHANGE_READY_TO_NULL)
		process_free(fft);

	return GST_ELEMENT_CLASS(gst_dlbfft_parent_class)->
			change_state(element, trans);
}

static void dlbfft_finalize(GObject *object)
{
	GstDLBFFT *fft = GST_DLBFFT(object);

	process_free(fft);

	G_OBJECT_CLASS(gst_dlbfft_parent_class)->finalize(object);
}

static GstStaticPadTemplate src_template =
	GST_STATIC_PAD_TEMPLATE("src",
		GST_PAD_SRC,
		GST_PAD_ALWAYS,
		GST_STATIC_CAPS(GST_VIDEO_CAPS_xRGB_HOST_ENDIAN)
	);

static GstStaticPadTemplate sink_template =
	GST_STATIC_PAD_TEMPLATE("sink",
		GST_PAD_SINK,
		GST_PAD_ALWAYS,
		GST_STATIC_CAPS("audio/x-raw-int, "
			"endianness = (int) BYTE_ORDER, "
			"signed = (boolean) TRUE, "
			"width = (int) 16, "
			"depth = (int) 16, "
			"rate = (int) [ 8000, 96000 ], "
			"channels = (int) { 1, 2 }"
		));

static void gst_dlbfft_init(GstDLBFFT *fft)
{
	fft->sink_pad =
		gst_pad_new_from_static_template(&sink_template, "sink");
	gst_pad_set_chain_function(fft->sink_pad, sink_chain);
	gst_pad_set_setcaps_function(fft->sink_pad, sink_setcaps);
	gst_pad_set_event_function(fft->sink_pad, sink_event);
	gst_element_add_pad(GST_ELEMENT(fft), fft->sink_pad);

	fft->src_pad =
		gst_pad_new_from_static_template(&src_template, "src");
	gst_pad_set_setcaps_function(fft->src_pad, src_setcaps);
	gst_pad_set_event_function(fft->src_pad, src_event);
	gst_element_add_pad(GST_ELEMENT(fft), fft->src_pad);

	process_init(fft);
}

static void gst_dlbfft_class_init(GstDLBFFTClass *klass)
{
	GstElementClass *ec = GST_ELEMENT_CLASS(klass);
	GObjectClass *oc = G_OBJECT_CLASS(klass);

	gst_element_class_set_details_simple(ec, "DLBFFT",
		"Visualization",
		"Draws a smoothly animated FFT-based spectrum analyzer",
		"Daniel Beer <dlbeer@gmail.com>");
	gst_element_class_add_pad_template(ec,
		gst_static_pad_template_get(&sink_template));
	gst_element_class_add_pad_template(ec,
		gst_static_pad_template_get(&src_template));

	ec->change_state = dlbfft_change_state;
	oc->finalize = dlbfft_finalize;
}

/************************************************************************
 * Plugin registration
 */

#define FFT_VERSION		"20111021"
#define FFT_LICENSE		"LGPL"
#define FFT_PACKAGE_NAME	"dlbfft"
#define FFT_PACKAGE_ORIGIN	"http://www.dlbeer.co.nz/"
#define PACKAGE			FFT_PACKAGE_NAME

static gboolean plugin_init(GstPlugin *plugin)
{
	return gst_element_register(plugin, FFT_PACKAGE_NAME, GST_RANK_NONE,
				    GST_TYPE_DLBFFT);
}


GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR,
    "dlbfft", "FFT visualization", plugin_init, FFT_VERSION,
    FFT_LICENSE, FFT_PACKAGE_NAME, FFT_PACKAGE_ORIGIN);
