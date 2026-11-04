'use strict';
// A ceiling on what one account can keep. Without it a single user can fill the bucket and the
// next person's first upload fails with a storage error nobody can explain. Counted from the
// documents table, which already records byte_size for every stored file.

const DEFAULT_MB = 500;
// Reading every row to add up a size is fine at a person's scale and avoids depending on a
// database aggregate being enabled; the cap is a guard rail, not an invoice.
const ROW_LIMIT = 5000;

function capBytes(env = process.env) {
  const mb = Number(env.OXY_USER_STORAGE_MB);
  return (Number.isFinite(mb) && mb > 0 ? mb : DEFAULT_MB) * 1024 * 1024;
}

async function usedBytes(supabase, userId) {
  if (!supabase || !userId) return 0;
  try {
    const { data } = await supabase
      .from('documents')
      .select('byte_size')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(ROW_LIMIT);
    return (data || []).reduce((total, row) => total + (Number(row.byte_size) || 0), 0);
  } catch {
    return 0;
  }
}

// Called before storing, with the size of what is about to be added.
async function checkQuota(supabase, userId, incomingBytes = 0) {
  const used = await usedBytes(supabase, userId);
  const cap = capBytes();
  const room = Math.max(0, cap - used);
  const incoming = Number(incomingBytes) || 0;
  const ok = incoming <= room;
  return {
    ok,
    used,
    cap,
    room,
    error: ok ? null : `This account has used ${Math.round(used / 1024 / 1024)}MB of its ${Math.round(cap / 1024 / 1024)}MB file storage. Delete something to make room.`,
  };
}

module.exports = { checkQuota, usedBytes, capBytes };
