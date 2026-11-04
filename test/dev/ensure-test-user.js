#!/usr/bin/env node

// The smoke suite writes rows that carry a foreign key to users, so the accounts it runs as
// must exist before the first test starts. Creating them here keeps the suite self-sufficient
// instead of depending on a row somebody happened to create months ago.

require('dotenv').config();

const { createSupabaseServiceClient } = require('../../runtime');

const FIXTURE_USERS = ['demo-test-user'];

async function main() {
  const db = createSupabaseServiceClient();
  for (const userId of FIXTURE_USERS) {
    const { data, error } = await db.from('users').select('user_id').eq('user_id', userId).maybeSingle();
    if (error) throw new Error(`Could not read users for ${userId}: ${error.message}`);
    if (data) continue;
    const { error: insertError } = await db.from('users').insert({
      user_id: userId,
      password_hash: 'fixture:no-login',
      email: null
    });
    if (insertError) throw new Error(`Could not create the ${userId} fixture: ${insertError.message}`);
    console.log(`created fixture user ${userId}`);
  }
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
