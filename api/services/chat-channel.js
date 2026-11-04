'use strict';

const TELEGRAM_BOT_CHANNEL = 'telegram_bot';
const ROOM_DEVICE_CHANNEL = 'display';

// A speaker is not the place to fill in a tenancy form. These are the capabilities that make
// sense said out loud in a room; anything bigger is handed to the background (create_agent_task)
// and finished on the phone. The profile is about where the device is, not what the task is:
// every one of these is an ordinary capability the phone also has.
const ROOM_DEVICE_TOOLS = Object.freeze([
  'web_search',
  'get_weather',
  'get_forecast',
  'get_calendar_events',
  'create_calendar_event',
  'create_reminder',
  'send_message',
  'send_adam_email',
  'send_adam_sms',
  'play_music',
  'set_notification_preference',
  'change_setting',
  'list_scheduled_tasks',
  'create_scheduled_task',
  'cancel_scheduled_task',
  'find_commitments',
  'resolve_commitment',
  'find_place',
  'get_directions',
  'search_trains',
  'remember_person',
  'find_people',
  'forget_memory',
  'calculate',
  'create_agent_task'
]);

function toolsForChannel(channel) {
  return normalizeChatChannel(channel) === ROOM_DEVICE_CHANNEL ? ROOM_DEVICE_TOOLS : null;
}

// A spoken answer is a sentence or two and the phone is one tap away, so the room does not need
// deep reasoning to answer out loud. Anything it hands to the background keeps the full effort.
function reasoningEffortForChannel(channel, env = process.env) {
  if (normalizeChatChannel(channel) !== ROOM_DEVICE_CHANNEL) return null;
  return env.OXY_ROOM_REASONING_EFFORT || 'low';
}


// "Text" is ordinary conversational language, so on a Telegram conversation it means
// use the channel the person is already in. Keep explicit native-channel requests on the
// native action instead of silently changing the user's chosen medium.
const EXPLICIT_NATIVE_MESSAGE_CHANNEL = /\b(?:sms|i\s*message|messages\s+app|text\s+message|phone\s+message)\b/i;

function normalizeChatChannel(value) {
  const channel = String(value || '').trim().toLowerCase();
  return channel || null;
}

function adaptActionForChannel(action, context = {}) {
  if (
    normalizeChatChannel(context.channel) !== TELEGRAM_BOT_CHANNEL ||
    action?.type !== 'send_message' ||
    action.input?.platform ||
    EXPLICIT_NATIVE_MESSAGE_CHANNEL.test(String(context.userMessage || ''))
  ) {
    return action;
  }

  return { ...action, type: 'send_telegram' };
}

function buildTelegramChatRequest(userId, message) {
  return { userId, message, channel: TELEGRAM_BOT_CHANNEL };
}

function buildDisplayChatRequest(userId, message) {
  return { userId, message, channel: ROOM_DEVICE_CHANNEL };
}

function buildChatChannelContext(channel) {
  if (normalizeChatChannel(channel) !== TELEGRAM_BOT_CHANNEL) return '';
  return `CURRENT CONVERSATION CHANNEL: Telegram.
For an unqualified request to message a personal contact, use Telegram through the user's connected Telegram account. Do not use the native phone Messages action unless the user explicitly asks for SMS, iMessage, or another native phone channel.`;
}

module.exports = {
  TELEGRAM_BOT_CHANNEL,
  ROOM_DEVICE_CHANNEL,
  ROOM_DEVICE_TOOLS,
  toolsForChannel,
  reasoningEffortForChannel,
  normalizeChatChannel,
  adaptActionForChannel,
  buildTelegramChatRequest,
  buildDisplayChatRequest,
  buildChatChannelContext,
  _private: { EXPLICIT_NATIVE_MESSAGE_CHANNEL }
};
