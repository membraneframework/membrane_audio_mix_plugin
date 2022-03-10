#pragma once

#include <erl_nif.h>
#include <stdbool.h>
#include <stdint.h>
#include "raw_audio_lib.h"

#include <stdio.h>

typedef struct _mixer_state
{
    CapsAudioRaw *caps;
    int sample_size;
    int sample_max;
    int sample_min;
    bool is_wave_positive;
    int64_t *queue;
    unsigned int queue_length;
} State;

#include "_generated/mixer.h"