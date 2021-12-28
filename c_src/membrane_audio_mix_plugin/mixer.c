#include "mixer.h"

UNIFEX_TERM init(UnifexEnv *env, params params)
{
    UNIFEX_TERM res;
    State *state = unifex_alloc_state(env);

    state->sample_max = params.sample_max;
    state->sample_min = params.sample_min;
    state->sample_size = params.sample_size;
    state->is_wave_positive = false;

    res = init_result_ok(env, state);
    return res;
}
