#pragma once

#include <erl_nif.h>
#include <membrane_raw_audio/raw_audio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct _mixer_state {
  RawAudio raw_audio;
  int32_t sample_size;
  int32_t sample_max;
  int32_t sample_min;
  bool is_wave_positive;
  int64_t *queue;
  uint32_t queue_length;
} State;

#include "_generated/mixer.h"
