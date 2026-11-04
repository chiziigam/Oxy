#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef bool (*pcm_sink_t)(const uint8_t *bytes, size_t count, void *context);
typedef struct {
    uint8_t buffer[4096];
    size_t used;
    pcm_sink_t sink;
    void *context;
} pcm_stream_t;

void pcm_stream_init(pcm_stream_t *stream, pcm_sink_t sink, void *context);
bool pcm_stream_push(pcm_stream_t *stream, const uint8_t *bytes, size_t count);
bool pcm_stream_finish(pcm_stream_t *stream);
