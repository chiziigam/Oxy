#include "pcm_stream.h"
#include <string.h>

void pcm_stream_init(pcm_stream_t *stream, pcm_sink_t sink, void *context) {
    stream->used = 0;
    stream->sink = sink;
    stream->context = context;
}

bool pcm_stream_push(pcm_stream_t *stream, const uint8_t *bytes, size_t count) {
    while (count) {
        size_t take = sizeof(stream->buffer) - stream->used;
        if (take > count) take = count;
        memcpy(stream->buffer + stream->used, bytes, take);
        stream->used += take;
        bytes += take;
        count -= take;
        if (stream->used == sizeof(stream->buffer)) {
            if (!stream->sink(stream->buffer, stream->used, stream->context)) return false;
            stream->used = 0;
        }
    }
    return true;
}

bool pcm_stream_finish(pcm_stream_t *stream) {
    if (stream->used % 2) return false;
    if (stream->used && !stream->sink(stream->buffer, stream->used, stream->context)) return false;
    stream->used = 0;
    return true;
}
