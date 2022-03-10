#include "mixer.h"

UNIFEX_TERM init(UnifexEnv *env, int channels, unsigned int format, int sample_rate)
{
    UNIFEX_TERM res;
    State *state = unifex_alloc_state(env);
    state->caps = unifex_alloc(sizeof(CapsAudioRaw));
    state->caps->format = format;
    state->caps->channels = channels;
    state->caps->sample_rate = sample_rate;
    state->sample_max = sample_max(state->caps);
    state->sample_min = sample_min(state->caps);
    state->sample_size = sample_size(state->caps);
    state->queue = NULL;
    state->queue_length = 0;
    state->is_wave_positive = false;

    res = init_result_ok(env, state);
    return res;
}

void get_values(UnifexPayload **buffers, unsigned int buffers_length, int64_t *values, unsigned int values_length, UnifexState *state)
{
    for (unsigned int chunk_start = 0, i = 0; i < values_length; chunk_start += state->sample_size, ++i)
    {
        values[i] = 0;
        for (unsigned int j = 0; j < buffers_length; ++j)
        {
            unsigned char *sample = buffers[j]->data + chunk_start;
            values[i] += sample_to_value(sample, state->caps);
        }
    }
}

unsigned int split_values(int64_t *values, unsigned int values_length, bool is_wave_positive)
{
    unsigned int i = 0;
    int8_t multiplier = 1;
    if (is_wave_positive)
    {
        multiplier = -1;
    }

    for (; i < values_length && values[i] * multiplier >= 0; ++i)
        ;

    return i;
}

void scale(int64_t *values, unsigned int values_length, double quotient, UnifexState *state)
{

    for (unsigned int i = 0; i < state->queue_length; ++i)
    {
        state->queue[i] = (int64_t)(state->queue[i] * quotient);
    }

    for (unsigned int i = 0; i < values_length; ++i)
    {
        values[i] = (int64_t)(values[i] * quotient);
    }
}

void get_samples(unsigned char *samples, int64_t *values, unsigned int values_length, UnifexState *state)
{
    int64_t min = state->sample_max;
    int64_t max = state->sample_min;

    for (unsigned int i = 0; i < state->queue_length; ++i)
    {
        if (state->queue[i] < min)
        {
            min = state->queue[i];
        }

        if (state->queue[i] > max)
        {
            max = state->queue[i];
        }
    }

    for (unsigned int i = 0; i < values_length; ++i)
    {
        if (values[i] < min)
        {
            min = values[i];
        }

        if (values[i] > max)
        {
            max = values[i];
        }
    }

    if (min < state->sample_min)
    {
        double quotient = (state->sample_min * 1.0) / min;
        scale(values, values_length, quotient, state);
    }
    else if (max > state->sample_max)
    {
        double quotient = (state->sample_max * 1.0) / max;
        scale(values, values_length, quotient, state);
    }

    int samples_start = 0;
    for (unsigned int i = 0; i < state->queue_length; ++i, samples_start += state->sample_size)
    {
        value_to_sample(state->queue[i], samples + samples_start, state->caps);
    }

    for (unsigned int i = 0; i < values_length; ++i, samples_start += state->sample_size)
    {
        value_to_sample(values[i], samples + samples_start, state->caps);
    }

    unifex_free(state->queue);
    state->queue = NULL;
    state->queue_length = 0;
}

void add_values(int64_t *values, unsigned int values_length, unsigned char *samples, unsigned int *samples_length, UnifexState *state)
{
    if (values_length == 0 || !values)
    {
        return;
    }

    bool is_wave_positive = state->is_wave_positive;
    unsigned int start = 0;
    unsigned int end = split_values(values, values_length, is_wave_positive);

    unsigned int samples_start = 0;
    while (end < values_length)
    {
        get_samples(samples + samples_start, values + start, end - start, state);
        samples_start += (end - start + state->queue_length) * state->sample_size;
        start = end;
        is_wave_positive = !is_wave_positive;
        end = split_values(values + end, values_length - end, is_wave_positive) + end;
    }

    state->is_wave_positive = is_wave_positive;

    unsigned int new_queue_length = state->queue_length + end - start;
    int64_t *new_queue = unifex_alloc(new_queue_length * sizeof(int64_t));
    memcpy(new_queue, state->queue, state->queue_length * sizeof(int64_t));
    memcpy(new_queue + state->queue_length, values + start, (end - start) * sizeof(int64_t));
    state->queue_length = new_queue_length;
    unifex_free(state->queue);
    state->queue = new_queue;
    *samples_length = start;
}

UNIFEX_TERM mix(UnifexEnv *env, UnifexPayload **buffers, unsigned int buffers_length, UnifexState *state)
{
    unsigned int values_length = 0;
    int64_t *values = NULL;

    if (buffers_length > 0)
    {
        unsigned int min_size = buffers[0]->size;
        for (unsigned int i = 1; i < buffers_length; ++i)
        {
            if (buffers[i]->size < min_size)
            {
                min_size = buffers[i]->size;
            }
        }
        values_length = min_size / state->sample_size;
        values = unifex_alloc(values_length * sizeof(int64_t));
        get_values(buffers, buffers_length, values, values_length, state);
    }
    unsigned int samples_length = values_length + state->queue_length;
    unsigned char *samples = unifex_alloc(samples_length * state->sample_size);

    add_values(values, values_length, samples, &samples_length, state);

    unifex_free(values);
    UnifexPayload *out_payload;
    unsigned int output_size = samples_length * state->sample_size;
    out_payload = unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, output_size);
    memcpy(out_payload->data, samples, output_size);
    unifex_free(samples);

    UNIFEX_TERM res = mix_result_ok(env, out_payload, state);
    return res;
}

UNIFEX_TERM flush(UnifexEnv *env, State *state)
{
    unsigned int samples_length = state->queue_length;
    unsigned char *samples = unifex_alloc(samples_length * state->sample_size);

    get_samples(samples, NULL, 0, state);

    UnifexPayload *out_payload;
    unsigned int output_size = samples_length * state->sample_size;
    out_payload = unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, output_size);
    memcpy(out_payload->data, samples, output_size);
    unifex_free(samples);

    UNIFEX_TERM res = flush_result_ok(env, out_payload, state);
    return res;
}

void handle_destroy_state(UnifexEnv *env, State *state)
{
    unifex_free(state->queue);
    unifex_free(state->caps);
}
