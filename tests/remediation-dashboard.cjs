const assert = require('node:assert/strict');
const { summarizeRemediation } = require('../cluster/homepage/dashboard.cjs');
const finding = { application: 'invoice-portal', package: 'PyPDF2', installed_version: '3.0.1',
  profile_sha256: 'profile', assessment_state: 'affected', advisories: ['TEST-1'],
  candidate: { sha256: 'wheel' }, observations: [{ business_passed: true }, { business_passed: false }] };
const validation = { id: 1, status: 'successful', elapsed: 42, artifacts: { invoice_validation: {
  passed: true, application: 'invoice-portal', wheel_sha256: 'wheel', source_revision: 'source',
  profile_sha256: 'profile', acceptance_suite: 'trusted-invoice-v1' } } };
const deployment = { id: 2, status: 'successful', artifacts: { invoice_release_evidence: {
  release: { wheel_sha256: 'wheel', source_revision: 'source' } } } };
assert.equal(summarizeRemediation(finding, validation, deployment).deployment, 'Succeeded #2');
assert.equal(summarizeRemediation(finding, validation, deployment).business, '1/2 hosts passed');
const changedPolicy = structuredClone(finding);
changedPolicy.profile_sha256 = 'different-profile';
assert.equal(summarizeRemediation(changedPolicy, validation, deployment).validation, 'No matching acceptance');
const failed = { ...validation, status: 'failed' };
assert.equal(summarizeRemediation(finding, failed, deployment).deployment, 'No matching deployment');
const changedSource = structuredClone(deployment);
changedSource.artifacts.invoice_release_evidence.release.source_revision = 'untested';
assert.equal(summarizeRemediation(finding, validation, changedSource).deployment, 'No matching deployment');
assert.equal(summarizeRemediation(null, validation, deployment).assessment, 'No observations yet');
console.log('Remediation dashboard checks passed.');
