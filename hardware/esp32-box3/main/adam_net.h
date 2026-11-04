#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "pcm_stream.h"

typedef struct {
    uint8_t *audio;      // mono 16 kHz PCM16 reply (caller frees), or NULL
    size_t audio_bytes;
    char heard[256];     // what Adam understood
    char reply[384];     // what Adam said
    int http_status;
} adam_reply_t;

// Starts Wi-Fi when the box has been provisioned. Safe to call when it has not.
void adam_net_init(void);
bool adam_net_configured(void);
bool adam_net_online(void);
int adam_net_disconnect_reason(void);
char *adam_net_scan(void);
const char *adam_net_last_error(void);
int adam_net_tls_error(void);
// Saves {"ssid","pass","url","id","token"} to flash. The box restarts afterwards to use it.
bool adam_net_store_config(const char *json);
// Sends one recording and receives the spoken answer. Returns false when no HTTP answer was received at all.
bool adam_net_voice(const int16_t *pcm, size_t bytes, adam_reply_t *reply, pcm_sink_t sink, void *context);

// The same turn, but the recording is sent while it is still being captured, so the upload is
// not added to the wait. Returns NULL when the stream could not be opened; the caller then
// falls back to adam_net_voice with the whole recording.
typedef struct adam_voice_stream adam_voice_stream_t;
adam_voice_stream_t *adam_net_voice_begin(adam_reply_t *reply, pcm_sink_t sink, void *context);
bool adam_net_voice_send(adam_voice_stream_t *stream, const int16_t *pcm, size_t bytes);
// Sends the tail, reads the answer into reply and plays it through the sink.
bool adam_net_voice_finish(adam_voice_stream_t *stream, const int16_t *tail, size_t tail_bytes, adam_reply_t *reply);
void adam_net_voice_abort(adam_voice_stream_t *stream);
bool adam_net_post_json(const char *path, const char *json);
