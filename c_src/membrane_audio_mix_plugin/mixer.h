#pragma once

#include <erl_nif.h>
#include <stdbool.h>

typedef struct _mixer_state
{
    int sample_size;
    int sample_max;
    int sample_min;
    bool is_wave_positive;
    void *queue;
} State;

#include "_generated/mixer.h"