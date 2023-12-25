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

#ifndef GST_DLBFFT_H_
#define GST_DLBFFT_H_

#define GST_DLBFFT_BINS		64
#define GST_DLBFFT_SLICE_RATE	64

#define GST_DLBFFT_SCALE	0.05
#define GST_DLBFFT_SMOOTHING	0.00007
#define GST_DLBFFT_GAMMA	2.0

#define GST_DLBFFT_COLOR	0xff008000

typedef struct _GstDLBFFT {
	GstElement		base;

	GstPad			*src_pad;
	GstPad			*sink_pad;

	/* Input format */
	int			rate;
	int			channels;

	/* Output format */
	int			width;
	int			height;
	int			fps_n;
	int			fps_d;
	int			vbuf_size;

	/* Slice collection buffer. Slices are uninterleaved. */
	int16_t			*slice_buf;
	int			slice_len;
	int			slice_samples;

	/* FFT processing */
	GstFFTS16		*fft;
	GstFFTS16Complex	*spectrum;

	float			power[GST_DLBFFT_BINS];

	/* Audio -> video rate matching counter */
	int			rate_counter;
} GstDLBFFT;

typedef struct _GstDLBFFTClass {
	GstElementClass		parent_class;
} GstDLBFFTClass;

#define GST_TYPE_DLBFFT			(gst_dlbfft_get_type())
#define GST_DLBFFT(obj)			(G_TYPE_CHECK_INSTANCE_CAST((obj), \
						GST_TYPE_DLBFFT, GstDLBFFT))
#define GST_IS_DLBFFT(obj)		(G_TYPE_CHECK_INSTANCE_TYPE((obj), \
						GST_TYPE_DLBFFT))
#define GST_DLBFFT_CLASS(klass)		(G_TYPE_CHECK_CLASS_CAST((klass), \
					 GST_TYPE_DLBFFT, GstDLBFFTClass))
#define GST_IS_DLBFFT_CLASS(klass)	(G_TYPE_CHECK_CLASS_TYPE((klass), \
					 GST_TYPE_DLBFFT))
#define GST_DLBFFT_GET_CLASS(obj)	(G_TYPE_INSTANCE_GET_CLASS((obj), \
					 GST_TYPE_DLBFFT, GstDLBFFTClass))

#endif
