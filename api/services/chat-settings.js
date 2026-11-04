'use strict';

const DEFAULTS = { effort: 'medium', guardMode: false };

async function getChatSettings(supabase, userId) {
  try {
    const { data, error } = await supabase.from('chat_settings').select('*').eq('user_id', userId).single();
    if (error) {
      // No row yet is normal (PGRST116). Any other failure is not: treating it as the
      // default would silently switch "ask before acting" off for that turn.
      if (error.code === 'PGRST116') return { ...DEFAULTS };
      console.warn('[chat-settings] read failed; keeping the strict default:', error.message);
      return { ...DEFAULTS, guardMode: true, unavailable: true };
    }
    if (!data) return { ...DEFAULTS };
    return { effort: data.effort, guardMode: data.guard_mode };
  } catch (err) {
    console.warn('[chat-settings] read failed; keeping the strict default:', err.message);
    return { ...DEFAULTS, guardMode: true, unavailable: true };
  }
}

async function saveChatSettings(supabase, userId, { effort, guardMode }) {
  try {
    const { error } = await supabase
      .from('chat_settings')
      .upsert({ user_id: userId, effort, guard_mode: guardMode, updated_at: new Date().toISOString() });
    if (error) return { error };
    return { ok: true };
  } catch (err) {
    return { error: err.message };
  }
}

module.exports = { getChatSettings, saveChatSettings };
