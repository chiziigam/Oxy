#!/usr/bin/env node

// The Docker build intentionally excludes .git, so Fly cannot discover the
// source revision itself. Always deploy through this command to bake release
// provenance into the image that serves customers.
const { execFileSync } = require('child_process');
const path = require('node:path');

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

// The image is built from the working directory, not from HEAD. Without these two guards a
// deploy can ship unreviewed files while /version names a commit that is not what is serving.
function assertDeployable({ branch, status, env = process.env } = {}) {
  if (branch === 'HEAD') {
    throw new Error('Refusing to deploy from a detached HEAD: check out the release branch first.');
  }
  if (branch !== 'main' && env.OXY_DEPLOY_BRANCH !== '1') {
    throw new Error(`Refusing to deploy from "${branch}". Merge to main first, or set OXY_DEPLOY_BRANCH=1 deliberately.`);
  }
  if (String(status || '').trim() && env.OXY_DEPLOY_DIRTY !== '1') {
    throw new Error('Refusing to deploy a dirty working tree: the image would contain files that are not in the commit /version reports. Commit them, or set OXY_DEPLOY_DIRTY=1 deliberately.');
  }
}

function main() {
  const commit = git(['rev-parse', '--verify', 'HEAD']);
  const branch = git(['rev-parse', '--abbrev-ref', 'HEAD']);
  const status = git(['status', '--porcelain']);
  assertDeployable({ branch, status });

  // The live database is not part of the image, so a deploy can happily ship code whose
  // declared tables or columns do not exist in production. Refuse until both match.
  if (process.env.OXY_SKIP_SCHEMA_CHECK === '1') {
    console.warn('WARNING: skipping the live schema check because OXY_SKIP_SCHEMA_CHECK=1.');
  } else {
    for (const script of ['check-live-schema.js', 'check-live-columns.js']) {
      try {
        execFileSync('node', [path.join(__dirname, script)], { stdio: 'inherit' });
      } catch {
        throw new Error(`Refusing to deploy: the live database does not match the code (${script}, see above). Apply the missing migration, or set OXY_SKIP_SCHEMA_CHECK=1 to override deliberately.`);
      }
    }
  }

  const metadataArgs = [
    '--build-arg', `OXY_COMMIT_SHA=${commit}`,
    '--build-arg', `OXY_GIT_BRANCH=${branch}`,
    '--build-arg', `OXY_BUILD_TIME=${new Date().toISOString()}`
  ];

  execFileSync('fly', ['deploy', ...metadataArgs, ...process.argv.slice(2)], {
    stdio: 'inherit'
  });
}

if (require.main === module) main();

module.exports = { assertDeployable };
