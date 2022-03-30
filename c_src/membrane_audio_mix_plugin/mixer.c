#include "mixer.h"

/**
 * Initializes new native mixer based on number of channels, sample format and
 * sample rate.
 */
UNIFEX_TERM init(UnifexEnv *env, int32_t channels, uint32_t sample_format,
                 int32_t sample_rate) {
  UNIFEX_TERM res;
  State *state = unifex_alloc_state(env);
  state->caps.sample_format = sample_format;
  state->caps.channels = channels;
  state->caps.sample_rate = sample_rate;
  state->sample_max = caps_audio_raw_sample_max(&state->caps);
  state->sample_min = caps_audio_raw_sample_min(&state->caps);
  state->sample_size = caps_audio_raw_sample_byte_size(&state->caps);
  state->queue = NULL;
  state->queue_length = 0;
  state->is_wave_positive = false;

  res = init_result_ok(env, state);
  return res;
}

/**
 * Parses the samples from the array of buffers to arrays of sample values and
 * then adds them together, creating a single array of sample values.
 */
void get_values(UnifexPayload **buffers, uint32_t buffers_length,
                int64_t *values, uint32_t values_length, UnifexState *state) {
  for (uint32_t chunk_start = 0, i = 0; i < values_length;
       chunk_start += state->sample_size, ++i) {
    values[i] = 0;
    for (uint32_t j = 0; j < buffers_length; ++j) {
      uint8_t *sample = buffers[j]->data + chunk_start;
      values[i] += caps_audio_raw_sample_to_value(sample, &state->caps);
    }
  }
}

/**
 * Finds index of the next sign change in values.
 */
uint32_t next_sign_change(int64_t *values, uint32_t values_length,
                          bool is_wave_positive) {
  uint32_t i = 0;
  int8_t multiplier = is_wave_positive ? -1 : 1;

  while (i < values_length && values[i] * multiplier >= 0) {
    i++;
  }

  return i;
}

/**
 * Scales values and queue by quotient.
 */
void scale(int64_t *values, uint32_t values_length, double quotient,
           UnifexState *state) {

  for (uint32_t i = 0; i < state->queue_length; ++i) {
    state->queue[i] = (int64_t)(state->queue[i] * quotient);
  }

  for (uint32_t i = 0; i < values_length; ++i) {
    values[i] = (int64_t)(values[i] * quotient);
  }
}

/**
 * Takes given values and values in queue and coverts them to samples.
 *
 * If any of the values overflows limits of the format, values will be
 * scaled down so the peak of the wave will become
 * maximal (minimal) allowed value.
 */
void get_samples(uint8_t *samples, int64_t *values, uint32_t values_length,
                 UnifexState *state) {
  int64_t min = state->sample_max;
  int64_t max = state->sample_min;

  for (uint32_t i = 0; i < state->queue_length; ++i) {
    if (state->queue[i] < min) {
      min = state->queue[i];
    }

    if (state->queue[i] > max) {
      max = state->queue[i];
    }
  }

  for (uint32_t i = 0; i < values_length; ++i) {
    if (values[i] < min) {
      min = values[i];
    }

    if (values[i] > max) {
      max = values[i];
    }
  }

  if (min < state->sample_min) {
    double quotient = (state->sample_min * 1.0) / min;
    scale(values, values_length, quotient, state);
  } else if (max > state->sample_max) {
    double quotient = (state->sample_max * 1.0) / max;
    scale(values, values_length, quotient, state);
  }

  uint8_t *current_sample = samples;
  for (uint32_t i = 0; i < state->queue_length;
       ++i, current_sample += state->sample_size) {
    caps_audio_raw_value_to_sample(state->queue[i], current_sample,
                                   &state->caps);
  }

  for (uint32_t i = 0; i < values_length;
       ++i, current_sample += state->sample_size) {
    caps_audio_raw_value_to_sample(values[i], current_sample, &state->caps);
  }

  unifex_free(state->queue);
  state->queue = NULL;
  state->queue_length = 0;
}

/**
 * Takes given values, divides them into parts where every part must have only
 * nonnegative or nonpositive values. The whole part consists of values from the
 * sign change to the sign change. Converts each of these parts into samples -
 * values might be scaled down to the limit of the format during conversion.
 *
 * Any remaining values are put into the state's queue.
 */
void chunk_and_scale_to_samples(int64_t *values, uint32_t values_length,
                                uint8_t *samples, uint32_t *samples_length,
                                UnifexState *state) {
  if (values_length == 0 || !values) {
    return;
  }

  bool is_wave_positive = state->is_wave_positive;
  uint32_t start = 0;
  uint32_t end = next_sign_change(values, values_length, is_wave_positive);

  uint32_t samples_size = 0;
  while (end < values_length) {
    uint32_t queue_length = state->queue_length;
    get_samples(samples + samples_size, values + start, end - start, state);
    samples_size += (end - start + queue_length) * state->sample_size;
    start = end;
    is_wave_positive = !is_wave_positive;
    end =
        next_sign_change(values + end, values_length - end, is_wave_positive) +
        end;
  }

  state->is_wave_positive = is_wave_positive;

  uint32_t new_queue_length = state->queue_length + end - start;
  int64_t *new_queue = unifex_alloc(new_queue_length * sizeof(*new_queue));
  memcpy(new_queue, state->queue, state->queue_length * sizeof(*new_queue));
  memcpy(new_queue + state->queue_length, values + start,
         (end - start) * sizeof(*new_queue));
  state->queue_length = new_queue_length;
  unifex_free(state->queue);
  state->queue = new_queue;

  *samples_length = samples_size / state->sample_size;
}

/**
 *  Mixes `buffers` to one buffer.
 */
UNIFEX_TERM mix(UnifexEnv *env, UnifexPayload **buffers,
                uint32_t buffers_length, UnifexState *state) {
  uint32_t values_length = 0;
  int64_t *values = NULL;

  if (buffers_length > 0) {
    uint32_t min_size = buffers[0]->size;
    for (uint32_t i = 1; i < buffers_length; ++i) {
      if (buffers[i]->size < min_size) {
        min_size = buffers[i]->size;
      }
    }
    values_length = min_size / state->sample_size;
    values = unifex_alloc(values_length * sizeof(*values));
    get_values(buffers, buffers_length, values, values_length, state);
  }

  uint32_t initial_output_length = values_length + state->queue_length;
  uint32_t output_length = initial_output_length;
  UnifexPayload out_payload;
  uint32_t output_size = output_length * state->sample_size;
  unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, output_size, &out_payload);

  chunk_and_scale_to_samples(values, values_length, out_payload.data,
                             &output_length, state);
  unifex_free(values);
  if (output_length < initial_output_length) {
    unifex_payload_realloc(&out_payload, output_length * state->sample_size);
  }

  UNIFEX_TERM res = mix_result_ok(env, &out_payload, state);
  unifex_payload_release(&out_payload);
  return res;
}

/**
 * Forces mixer to flush the remaining buffers.
 */
UNIFEX_TERM flush(UnifexEnv *env, State *state) {
  uint32_t samples_length = state->queue_length;
  uint8_t *samples = unifex_alloc(samples_length * state->sample_size);

  get_samples(samples, NULL, 0, state);

  UnifexPayload out_payload;
  uint32_t output_size = samples_length * state->sample_size;
  unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, output_size, &out_payload);
  memcpy(out_payload.data, samples, output_size);
  unifex_free(samples);

  UNIFEX_TERM res = flush_result_ok(env, &out_payload, state);
  unifex_payload_release(&out_payload);
  return res;
}

/**
 *  Handles deallocation of mixer's state.
 */
void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);

  if (state) {
    if (state->queue) {
      unifex_free(state->queue);
    }
  }
}
