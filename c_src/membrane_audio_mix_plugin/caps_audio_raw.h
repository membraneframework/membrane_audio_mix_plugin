#include <membrane/membrane.h>
#include <stdbool.h>
#include <stdint.h>

#define MAX_SIZE 4

union Value {
  int32_t s_val;
  uint32_t u_val;
};

struct _CapsAudioRaw {
  uint32_t channels;
  uint32_t sample_format;
  uint32_t sample_rate;
};
typedef struct _CapsAudioRaw CapsAudioRaw;

int64_t caps_audio_raw_sample_to_value(uint8_t *sample, CapsAudioRaw *caps);
void caps_audio_raw_value_to_sample(int64_t value, uint8_t *sample,
                                    CapsAudioRaw *caps);
int64_t caps_audio_raw_sample_max(CapsAudioRaw *caps);
int64_t caps_audio_raw_sample_min(CapsAudioRaw *caps);
uint8_t caps_audio_raw_sample_byte_size(CapsAudioRaw *caps);
