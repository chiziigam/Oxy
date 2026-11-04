#include "main/voice_endpoint.h"
#include "main/pcm_stream.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static voice_endpoint_result_t blocks(voice_endpoint_t *state, int amplitude, int count) {
    int16_t pcm[512];
    for (size_t i = 0; i < 512; i++) pcm[i] = i % 2 ? amplitude : -amplitude;
    voice_endpoint_result_t result = VOICE_CONTINUE;
    while (count-- && result == VOICE_CONTINUE) result = voice_endpoint_process(state, pcm, 512);
    return result;
}

static uint8_t received[20000];
static size_t received_count, writes;
static bool fail_sink;
static bool sink(const uint8_t *bytes, size_t count, void *context) {
    assert(context == received);
    assert(count % 2 == 0);
    if (fail_sink) return false;
    assert(received_count + count <= sizeof(received));
    memcpy(received + received_count, bytes, count);
    received_count += count;
    writes++;
    return true;
}

int main(void) {
    voice_endpoint_t state;
    voice_endpoint_init(&state, 16000, 10);
    assert(blocks(&state, 10, 20) == VOICE_CONTINUE);
    assert(blocks(&state, 150, 20) == VOICE_CONTINUE);
    assert(blocks(&state, 10, 16) == VOICE_CONTINUE);
    assert(blocks(&state, 150, 20) == VOICE_CONTINUE);
    assert(blocks(&state, 10, 28) == VOICE_CONTINUE);
    assert(blocks(&state, 10, 1) == VOICE_ENDED);
    assert(state.speech && state.samples < 16000 * 4);

    voice_endpoint_init(&state, 16000, 10);
    assert(blocks(&state, 2000, 1) == VOICE_CONTINUE);
    assert(blocks(&state, 10, 124) == VOICE_NO_SPEECH);
    assert(!state.speech);
    voice_endpoint_init(&state, 16000, 100);
    assert(blocks(&state, 100, 125) == VOICE_NO_SPEECH);
    assert(!state.speech);
    voice_endpoint_init(&state, 16000, 10);
    assert(blocks(&state, 150, 469) == VOICE_LIMIT);
    int16_t dc[512];
    for (size_t i = 0; i < 512; i++) dc[i] = 1000;
    assert(voice_block_rms(dc, 512) == 0);

    uint8_t input[10000];
    for (size_t i = 0; i < sizeof(input); i++) input[i] = (uint8_t)i;
    for (size_t chunk = 1; chunk <= 3001; chunk += 137) {
        pcm_stream_t stream;
        received_count = writes = 0;
        pcm_stream_init(&stream, sink, received);
        for (size_t offset = 0; offset < sizeof(input); offset += chunk) {
            size_t count = sizeof(input) - offset;
            if (count > chunk) count = chunk;
            assert(pcm_stream_push(&stream, input + offset, count));
            if (offset + count >= 4096) assert(writes > 0);
        }
        assert(pcm_stream_finish(&stream));
        assert(received_count == sizeof(input));
        assert(memcmp(input, received, sizeof(input)) == 0);
    }
    pcm_stream_t stream;
    received_count = 0;
    pcm_stream_init(&stream, sink, received);
    assert(pcm_stream_push(&stream, input, 3));
    assert(!pcm_stream_finish(&stream));
    assert(received_count == 0);
    pcm_stream_init(&stream, sink, received);
    fail_sink = true;
    assert(!pcm_stream_push(&stream, input, 4096));
    puts("PASS: speech pauses, speech end, noise, transient rejection, recording limit, fragmented PCM, early playback, malformed PCM, sink failure");
    return 0;
}
