'use strict';

function csvEnv(name) {
  const value = process.env[name];
  if (!value) return undefined;
  const items = value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
  return items.length > 0 ? items : undefined;
}

const repositories = csvEnv('RENOVATE_REPOSITORIES');
const autodiscover = process.env.RENOVATE_AUTODISCOVER === 'true';
const autodiscoverFilter = csvEnv('RENOVATE_AUTODISCOVER_FILTER');
const autodiscoverNamespaces = csvEnv('RENOVATE_AUTODISCOVER_NAMESPACES');

if (!autodiscover && !repositories) {
  throw new Error(
    'Set RENOVATE_REPOSITORIES, or set RENOVATE_AUTODISCOVER=true with a restrictive filter.'
  );
}

if (autodiscover && !autodiscoverFilter && !autodiscoverNamespaces) {
  throw new Error(
    'RENOVATE_AUTODISCOVER=true requires RENOVATE_AUTODISCOVER_FILTER or RENOVATE_AUTODISCOVER_NAMESPACES.'
  );
}

module.exports = {
  platform: process.env.RENOVATE_PLATFORM || 'github',
  endpoint: process.env.RENOVATE_ENDPOINT || undefined,
  token: process.env.RENOVATE_TOKEN,
  repositories,
  autodiscover,
  autodiscoverFilter,
  autodiscoverNamespaces,

  onboarding: true,
  onboardingBranch: 'renovate/configure',
  onboardingPrTitle: '[CHORE] -TECHNICAL- configure Renovate',
  requireConfig: 'required',

  automerge: false,
  dependencyDashboard: true,
  prConcurrentLimit: 5,
  prHourlyLimit: 2,
  branchConcurrentLimit: 5,
  minimumReleaseAge: '7 days',
  internalChecksFilter: 'strict',

  allowScripts: false,
  allowPlugins: false,
  allowCustomCrateRegistries: false,
  allowShellExecutorForPostUpgradeCommands: false,
  allowedCommands: [],
  allowedEnv: [],
  allowedUnsafeExecutions: [],
  ignoreScripts: true,

  onboardingConfig: {
    $schema: 'https://docs.renovatebot.com/renovate-schema.json',
    extends: ['config:recommended'],
    automerge: false,
    dependencyDashboard: true,
    prConcurrentLimit: 5,
    prHourlyLimit: 2,
    minimumReleaseAge: '7 days',
    internalChecksFilter: 'strict',
    labels: ['dependencies'],
    packageRules: [
      {
        description: 'Group low-risk patch and digest updates.',
        matchUpdateTypes: ['patch', 'digest', 'pinDigest'],
        groupName: 'patch and digest updates',
      },
      {
        description: 'Keep major updates isolated for manual review.',
        matchUpdateTypes: ['major'],
        dependencyDashboardApproval: true,
      },
    ],
  },
};
