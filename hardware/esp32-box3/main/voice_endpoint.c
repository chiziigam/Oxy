#include "voice_endpoint.h"
#include <math.h>
#include <string.h>

float voice_block_rms(const int16_t *samples, size_t count) {
    if (!count) return 0;
    int64_t sum = 0, power = 0;
    for (size_t i = 0; i < count; i++) {
        sum += samples[i];
        power += (int32_t)samples[i] * (int32_t)samples[i];
    }
    float mean = (float)sum / count;
    return sqrtf(fmaxf(0, (float)power / count - mean * mean));
}

void voice_endpoint_init(voice_endpoint_t *state, uint32_t rate, float noise_rms) {
    memset(state, 0, sizeof(*state));
    state->rate = rate;
    state->noise_rms = fmaxf(4, noise_rms);
}

voice_endpoint_result_t voice_endpoint_process(voice_endpoint_t *state, const int16_t *samples, size_t count) {
    state->samples += count;
    float rms = voice_block_rms(samples, count);
    float threshold = fmaxf(28, state->noise_rms * 2.8f);
    if (rms >= threshold) {
        state->onset_samples += count;
        if (state->onset_samples >= state->rate * 0.064f) state->speech = true;
        state->quiet_samples = 0;
    } else {
        state->onset_samples = 0;
        if (state->speech) state->quiet_samples += count;
        else state->noise_rms = state->noise_rms * 0.98f + rms * 0.02f;
    }
    if (state->speech && state->quiet_samples >= state->rate * 0.9f) return VOICE_ENDED;
    if (!state->speech && state->samples >= state->rate * 4) return VOICE_NO_SPEECH;
    if (state->samples >= state->rate * 15) return VOICE_LIMIT;
    return VOICE_CONTINUE;
}
