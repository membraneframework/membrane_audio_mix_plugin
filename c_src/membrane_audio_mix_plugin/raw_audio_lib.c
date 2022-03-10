#include "raw_audio_lib.h"

int64_t sample_to_value(unsigned char *sample, CapsAudioRaw *caps)
{
    bool format_le = (caps->format & MEMBRANE_SAMPLE_FORMAT_ENDIANITY) == MEMBRANE_SAMPLE_FORMAT_ENDIANITY_LE;
    unsigned int size = sample_size(caps);
    unsigned int pad_left = MAX_SIZE - size;
    union Value ret;
    if (format_le)
    {
        for (unsigned int i = 0; i < size; ++i)
        {
            ret.bytes[i + pad_left] = sample[i];
        }
    }
    else
    {
        for (unsigned int i = MAX_SIZE - 1, j = 0; j < size; --i, ++j)
        {
            ret.bytes[i] = sample[j];
        }
    }

    bool format_u = (caps->format & MEMBRANE_SAMPLE_FORMAT_TYPE) == MEMBRANE_SAMPLE_FORMAT_TYPE_U;
    if (format_u)
    {
        return (int64_t)(ret.u_val >> 8 * pad_left);
    }
    else
    {
        return (int64_t)(ret.s_val >> 8 * pad_left);
    }
}

void value_to_sample(int64_t value, unsigned char *sample, CapsAudioRaw *caps)
{
    bool format_u = (caps->format & MEMBRANE_SAMPLE_FORMAT_TYPE) == MEMBRANE_SAMPLE_FORMAT_TYPE_U;
    union Value ret;

    if (format_u)
    {
        ret.u_val = (uint32_t)value;
    }
    else
    {
        ret.s_val = (int32_t)value;
    }
    bool format_le = (caps->format & MEMBRANE_SAMPLE_FORMAT_ENDIANITY) == MEMBRANE_SAMPLE_FORMAT_ENDIANITY_LE;
    unsigned int size = sample_size(caps);

    if (format_le)
    {
        for (unsigned int i = 0; i < size; ++i)
        {
            sample[i] = ret.bytes[i];
        }
    }
    else
    {
        for (unsigned int i = size - 1, j = 0; j < size; --i, ++j)
        {
            sample[j] = ret.bytes[i];
        }
    }
}

int64_t sample_max(CapsAudioRaw *caps)
{
    bool format_u = (caps->format & MEMBRANE_SAMPLE_FORMAT_TYPE) == MEMBRANE_SAMPLE_FORMAT_TYPE_U;
    unsigned int size = caps->format & MEMBRANE_SAMPLE_FORMAT_SIZE;
    if (format_u)
    {
        return (1 << size) - 1;
    }
    else
    {
        return (1 << (size - 1)) - 1;
    }
}

int64_t sample_min(CapsAudioRaw *caps)
{
    bool format_u = (caps->format & MEMBRANE_SAMPLE_FORMAT_TYPE) == MEMBRANE_SAMPLE_FORMAT_TYPE_U;

    if (format_u)
    {
        return 0;
    }
    else
    {
        unsigned int size = caps->format & MEMBRANE_SAMPLE_FORMAT_SIZE;
        return -(1 << (size - 1));
    }
}

int8_t sample_size(CapsAudioRaw *caps)
{
    return (int8_t)((caps->format & MEMBRANE_SAMPLE_FORMAT_SIZE) / 8);
}
