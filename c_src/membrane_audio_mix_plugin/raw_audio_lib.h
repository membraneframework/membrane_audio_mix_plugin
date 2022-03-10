#include <stdint.h>
#include <stdbool.h>
#include <membrane/membrane.h>

#define MAX_SIZE 4

union Value
{
    unsigned char bytes[4];
    int32_t s_val;
    uint32_t u_val;
};

struct _CapsAudioRaw
{
    unsigned int channels;
    unsigned int format;
    unsigned int sample_rate;
};
typedef struct _CapsAudioRaw CapsAudioRaw;

int64_t sample_to_value(unsigned char *sample, CapsAudioRaw *caps);
void value_to_sample(int64_t value, unsigned char *sample, CapsAudioRaw *caps);
int64_t sample_max(CapsAudioRaw *caps);
int64_t sample_min(CapsAudioRaw *caps);
int8_t sample_size(CapsAudioRaw *caps);
