// Offline release-generation preview; never writes to GitHub or package source.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
  if (index % 2 === 0) pairs.push([value, all[index + 1]]);
  return pairs;
}, []));
for (const key of ['--release-please-dir', '--pr-json', '--output']) {
  assert(args[key], `Missing ${key}`);
}
const root = path.resolve(__dirname, '..');
const installed = path.resolve(args['--release-please-dir']);
const version = require(path.join(installed, 'package.json')).version;
assert.equal(version, '17.6.0', 'Revalidate the preview adapter before changing Release Please versions.');
const {Manifest} = require(path.join(installed, 'build/src/manifest.js'));
const {parseConventionalCommits} = require(path.join(installed, 'build/src/commit.js'));
const {TagName} = require(path.join(installed, 'build/src/util/tag-name.js'));
const pr = JSON.parse(fs.readFileSync(args['--pr-json'], 'utf8').replace(/^\uFEFF/, ''));
assert(pr.title && pr.body && pr.base?.sha && pr.head?.sha, 'Export the complete actual promotion PR JSON.');
const git = (...arguments) => cp.execFileSync('git', arguments, {cwd: root, encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), pr.head.sha, 'PR snapshot and candidate HEAD must match.');
assert.equal(git('status', '--porcelain'), '', 'Preview the clean committed candidate.');
const files = git('diff', '--name-only', pr.base.sha, 'HEAD').split(/\r?\n/).filter(Boolean);
const raw = file => fs.readFileSync(path.join(root, file), 'utf8');
const hash = content => crypto.createHash('sha256').update(content).digest('hex');
const local = {
  repository: {owner: 'open-feature', repo: 'dart-sdk'},
  getFileJson: async file => JSON.parse(raw(file)),
  getFileContentsOnBranch: async file => ({parsedContent: raw(file), content: Buffer.from(raw(file)).toString('base64'), sha: hash(raw(file))}),
};

(async () => {
  // Use the production parser, including all defaults and changelog filters.
  const manifest = await Manifest.fromManifest(local, 'main');
  assert.equal(manifest.separatePullRequests, true);
  assert.equal(manifest.plugins.length, 0, 'Plugin behavior needs a full manifest preview.');
  const strategies = await manifest.getStrategiesByPath();
  const results = [];
  for (const scenario of ['actual_promotion', 'hidden_chore_negative_control']) {
    const body = scenario === 'actual_promotion' ? pr.body : '';
    const title = scenario === 'actual_promotion' ? pr.title : 'chore(main): prepare releases';
    const commits = parseConventionalCommits([{
      sha: pr.head.sha,
      message: `${title}\n\n${body}`,
      files,
      pullRequest: {number: pr.number, title, body},
    }]);
    for (const [packagePath, strategy] of Object.entries(strategies)) {
      assert(files.some(file => file.startsWith(`${packagePath}/`)), `No changed files for ${packagePath}`);
      const config = manifest.repositoryConfig[packagePath];
      const previous = manifest.releasedVersions[packagePath].toString();
      const tag = config.includeComponentInTag ? `${config.component}-v${previous}` : `v${previous}`;
      const proposal = await strategy.buildReleasePullRequest(commits, {tag: TagName.parse(tag), sha: pr.base.sha, notes: ''}, config.draftPullRequest);
      const result = {scenario, package: packagePath, previous, generated: Boolean(proposal)};
      if (scenario === 'actual_promotion') {
        assert(proposal, `No release PR for ${packagePath}; check actual promotion notes.`);
        assert.equal(proposal.version.toString(), config.releaseAs);
        assert.equal(proposal.draft, true);
        const staged = {};
        for (const update of proposal.updates) {
          const file = path.join(root, update.path);
          staged[update.path] = update.updater.updateContent(fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : undefined);
        }
        const proposed = proposal.version.toString();
        assert(staged[`${packagePath}/pubspec.yaml`].includes(`version: ${proposed}`));
        if (packagePath.endsWith('client_sdk')) {
          assert.equal(staged[`${packagePath}/.release-please-version`].trim(), proposed);
          assert(staged[`${packagePath}/README.md`].includes(`openfeature_dart_client_sdk: ^${proposed} # x-release-please-version`));
          assert(!staged[`${packagePath}/README.md`].includes(previous));
        }
        result.version = proposed;
        result.draft = proposal.draft;
        result.notes = proposal.body.toString();
        result.updates = Object.keys(staged);
      } else if (packagePath.endsWith('client_sdk')) {
        assert.equal(proposal, undefined, 'Negative control must reject hidden chore-only client notes.');
      }
      results.push(result);
    }
  }
  const receipt = {
    observed_at: new Date().toISOString(),
    release_please_version: version,
    head: pr.head.sha,
    base: pr.base.sha,
    pr: pr.number,
    title: pr.title,
    changed_files: files,
    config_sha256: hash(raw('release-please-config.json')),
    manifest_sha256: hash(raw('.release-please-manifest.json')),
    body_sha256: hash(pr.body),
    configuration: 'Release Please Manifest.fromManifest; complete configured defaults/sections',
    boundary: 'Offline local SCM and supplied actual PR JSON; release generation/updaters only, no publication or provider acceptance',
    results,
  };
  fs.writeFileSync(args['--output'], `${JSON.stringify(receipt, null, 2)}\n`);
  console.log(JSON.stringify({head: receipt.head, results: results.map(({notes, ...result}) => result)}, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
