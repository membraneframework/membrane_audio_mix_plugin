#pragma once

#include "raw_audio_format.h"
#include <erl_nif.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct _mixer_state {
  RawAudioFormat stream_format;
  int32_t sample_size;
  int32_t sample_max;
  int32_t sample_min;
  bool is_wave_positive;
  int64_t *queue;
  uint32_t queue_length;
} State;

#include "_generated/mixer.h"
