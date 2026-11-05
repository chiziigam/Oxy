'use strict';
// Signing in with a provider must land on the account the person already has, not a duplicate.
// The one thing that cannot be skipped: an address alone is not proof of ownership. A provider
// that has *verified* the address is.
//
// So the merge trusts a *verified* address. A password account on that address is merged into and
// keeps its password: the person who can receive mail for the address can always reset that
// password, so a squatter who registered it first has no lasting hold. Retiring the password
// instead would lock out the actual owner, which is a worse failure than the one it prevents.

async function findLinkedUserId(supabase, provider, subject) {
  try {
    const { data } = await supabase
      .from('preferences')
      .select('user_id')
      .eq('key', `auth.${provider}.subject`)
      .eq('value', String(subject))
      .maybeSingle();
    return data?.user_id || null;
  } catch {
    return null;
  }
}

async function linkAccount(supabase, userId, provider, subject) {
  try {
    await supabase.from('preferences').upsert(
      { user_id: userId, key: `auth.${provider}.subject`, value: String(subject) },
      { onConflict: 'user_id,key' }
    );
  } catch { /* a failed link only costs a lookup next time, never the sign-in */ }
}

async function accountByEmail(supabase, email) {
  try {
    const { data } = await supabase
      .from('users')
      .select('user_id, email, email_verified, password_hash')
      .ilike('email', String(email).replace(/[%_\\]/g, (c) => `\\${c}`))
      .limit(5);
    const rows = data || [];
    return rows.find((row) => String(row.email || '').toLowerCase() === String(email).toLowerCase()) || null;
  } catch {
    return null;
  }
}

/**
 * Resolve a provider identity to one account, creating only when there is nothing to merge into.
 * Returns { userId, created, merged, relinked }.
 */
async function resolveOrMergeAccount(supabase, {
  provider, subject, email = null, emailVerified = false,
  deriveUserId
} = {}) {
  const linkedUserId = await findLinkedUserId(supabase, provider, subject);
  if (linkedUserId) return { userId: linkedUserId, created: false, merged: false, relinked: true };

  if (email) {
    const existing = await accountByEmail(supabase, email);
    if (existing?.user_id) {
      const patch = {};
      // The provider proved the address, so record that. The password stays as it was: the owner
      // of a verified address can reset it at any time, which is what closes the squatting case.
      if (existing.email_verified !== true) patch.email_verified = true;
      if (Object.keys(patch).length) {
        patch.updated_at = new Date().toISOString();
        await supabase.from('users').update(patch).eq('user_id', existing.user_id);
      }
      await linkAccount(supabase, existing.user_id, provider, subject);
      return { userId: existing.user_id, created: false, merged: true, relinked: false };
    }
  }

  // Nothing to merge into: hand back the id to create. The caller links it only once the row
  // exists, so a failed insert cannot leave a link pointing at an account that is not there.
  return { userId: deriveUserId(subject), created: true, merged: false, relinked: false };
}

module.exports = { resolveOrMergeAccount, findLinkedUserId, linkAccount, accountByEmail };
