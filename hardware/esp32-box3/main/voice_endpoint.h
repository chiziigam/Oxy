#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { VOICE_CONTINUE, VOICE_ENDED, VOICE_NO_SPEECH, VOICE_LIMIT } voice_endpoint_result_t;
typedef struct {
    uint32_t rate, samples, quiet_samples, onset_samples;
    float noise_rms;
    bool speech;
} voice_endpoint_t;

float voice_block_rms(const int16_t *samples, size_t count);
void voice_endpoint_init(voice_endpoint_t *state, uint32_t rate, float noise_rms);
voice_endpoint_result_t voice_endpoint_process(voice_endpoint_t *state, const int16_t *samples, size_t count);
