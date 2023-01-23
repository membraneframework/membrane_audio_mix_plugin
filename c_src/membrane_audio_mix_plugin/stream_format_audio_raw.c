#include "stream_format_audio_raw.h"

/**
 * Converts one raw sample into its numeric value, interpreting it for given
 * format.
 */
int64_t stream_format_audio_raw_sample_to_value(uint8_t *sample,
                                                RawAudioFormat *stream_format) {
  bool is_format_le =
      (stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_ENDIANITY) ==
      MEMBRANE_SAMPLE_FORMAT_ENDIANITY_LE;
  uint8_t size = stream_format_audio_raw_sample_byte_size(stream_format);
  union Value ret;
  ret.u_val = 0;

  if (is_format_le) {
    for (int8_t i = size - 1; i >= 0; --i) {
      ret.u_val <<= 8;
      ret.u_val += sample[i];
    }
  } else {
    for (int8_t i = 0; i < size; ++i) {
      ret.u_val <<= 8;
      ret.u_val += sample[i];
    }
  }

  uint32_t pad_left = MAX_SIZE - size;
  ret.u_val <<= 8 * pad_left;

  bool is_signed = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_TYPE;
  if (is_signed) {
    return (int64_t)(ret.s_val >> 8 * pad_left);
  } else {
    return (int64_t)(ret.u_val >> 8 * pad_left);
  }
}

/**
 * Converts value into one raw sample, encoding it in given format.
 */
void stream_format_audio_raw_value_to_sample(int64_t value, uint8_t *sample,
                                             RawAudioFormat *stream_format) {
  bool is_signed = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_TYPE;
  union Value ret;

  if (is_signed) {
    ret.s_val = (int32_t)value;
  } else {
    ret.u_val = (uint32_t)value;
  }

  bool is_format_le =
      (stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_ENDIANITY) ==
      MEMBRANE_SAMPLE_FORMAT_ENDIANITY_LE;

  uint8_t size = stream_format_audio_raw_sample_byte_size(stream_format);
  if (is_format_le) {
    for (uint8_t i = 0; i < size; ++i) {
      sample[i] = ret.u_val & 0xFF;
      ret.u_val >>= 8;
    }
  } else {
    for (int8_t i = size - 1; i >= 0; --i) {
      sample[i] = ret.u_val & 0xFF;
      ret.u_val >>= 8;
    }
  }
}

/**
 * Returns maximum sample value for given format.
 */
int64_t stream_format_audio_raw_sample_max(RawAudioFormat *stream_format) {
  bool is_signed = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_TYPE;
  uint32_t size = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_SIZE;
  if (is_signed) {
    return (1 << (size - 1)) - 1;
  } else {
    return (1 << size) - 1;
  }
}

/**
 * Returns minimum sample value for given format.
 */
int64_t stream_format_audio_raw_sample_min(RawAudioFormat *stream_format) {
  bool is_signed = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_TYPE;

  if (is_signed) {
    uint32_t size = stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_SIZE;
    return -(1 << (size - 1));
  } else {
    return 0;
  }
}

/**
 * Returns byte size for given format.
 */
uint8_t
stream_format_audio_raw_sample_byte_size(RawAudioFormat *stream_format) {
  const uint32_t stream_format_size =
      stream_format->sample_format & MEMBRANE_SAMPLE_FORMAT_SIZE;
  return (uint8_t)(stream_format_size / 8);
}
