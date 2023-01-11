#pragma once

#include "stream_format_audio_raw.h"
#include <erl_nif.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct _mixer_state {
  StreamFormatAudioRaw stream_format;
  int32_t sample_size;
  int32_t sample_max;
  int32_t sample_min;
  bool is_wave_positive;
  int64_t *queue;
  uint32_t queue_length;
} State;

#include "_generated/mixer.h"
