#include <membrane/membrane.h>
#include <stdbool.h>
#include <stdint.h>

#define MAX_SIZE 4

union Value {
  int32_t s_val;
  uint32_t u_val;
};

struct _StreamFormatAudioRaw {
  uint32_t channels;
  uint32_t sample_format;
  uint32_t sample_rate;
};
typedef struct _StreamFormatAudioRaw StreamFormatAudioRaw;

int64_t
stream_format_audio_raw_sample_to_value(uint8_t *sample,
                                        StreamFormatAudioRaw *stream_format);
void stream_format_audio_raw_value_to_sample(
    int64_t value, uint8_t *sample, StreamFormatAudioRaw *stream_format);
int64_t stream_format_audio_raw_sample_max(StreamFormatAudioRaw *stream_format);
int64_t stream_format_audio_raw_sample_min(StreamFormatAudioRaw *stream_format);
uint8_t
stream_format_audio_raw_sample_byte_size(StreamFormatAudioRaw *stream_format);
