#include <membrane/membrane.h>
#include <stdbool.h>
#include <stdint.h>

#define MAX_SIZE 4

union Value {
  int32_t s_val;
  uint32_t u_val;
};

struct _RawAudioFormat {
  uint32_t channels;
  uint32_t sample_format;
  uint32_t sample_rate;
};
typedef struct _RawAudioFormat RawAudioFormat;

int64_t raw_audio_format_sample_to_value(uint8_t *sample,
                                         RawAudioFormat *stream_format);
void raw_audio_format_value_to_sample(int64_t value, uint8_t *sample,
                                      RawAudioFormat *stream_format);
int64_t raw_audio_format_sample_max(RawAudioFormat *stream_format);
int64_t raw_audio_format_sample_min(RawAudioFormat *stream_format);
uint8_t raw_audio_format_sample_byte_size(RawAudioFormat *stream_format);
